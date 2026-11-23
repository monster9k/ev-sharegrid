import json
import secrets

import pytest

from fastapi.testclient import TestClient

from backend import auth
from backend.auth import AuthUser
from backend.main import app
from backend.routes import auth as auth_route


client = TestClient(app)
ACTIVE_USER = {
    "user_id": 3,
    "role": "USER",
    "email": "user1@sharegrid.vn",
    "full_name": "Test User",
}
VEHICLE = {
    "vehicle_id": 101,
    "model_id": 2,
    "plate_number": "43A-123.45",
    "nickname": "EV",
    "default_soc_target": 80,
    "is_default": True,
    "brand": "VinFast",
    "model_name": "VF 5",
    "connector_type": "CCS2",
    "battery_kwh": 60,
    "max_kw": 11,
}


class AuthCursor:
    def __init__(self):
        self.one = None
        self.many = []

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.one = None
        self.many = []
        if "FROM app_user" in normalized:
            self.one = dict(ACTIVE_USER)
        elif "FROM vehicle v" in normalized:
            self.many = [dict(VEHICLE)]
        else:
            raise AssertionError(f"Unexpected SQL: {normalized}")

    def fetchone(self):
        return self.one

    def fetchall(self):
        return self.many

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False


class AuthConnection:
    def __init__(self):
        self.fake_cursor = AuthCursor()
        self.closed = False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def close(self):
        self.closed = True


def set_auth_config(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", "test-only-signing-secret-with-32-bytes")
    monkeypatch.setenv("JWT_TTL_MINUTES", "15")
    monkeypatch.setenv("AUTH_PASSWORD_HASHES_JSON", json.dumps({"user1@sharegrid.vn": auth.hash_password("correct-password", salt=b"0123456789abcdef")}))
    monkeypatch.setenv("DEV_AUTH_BYPASS", "0")


def install_auth_db(monkeypatch):
    connections = []

    def connect():
        connection = AuthConnection()
        connections.append(connection)
        return connection

    monkeypatch.setattr(auth, "connect", connect)
    monkeypatch.setattr(auth_route, "connect", connect)
    monkeypatch.setattr(auth, "dict_cursor", lambda connection: connection.cursor())
    monkeypatch.setattr(auth_route, "dict_cursor", lambda connection: connection.cursor())
    return connections


def test_login_issues_expiring_signed_token_and_me_lists_vehicles(monkeypatch):
    set_auth_config(monkeypatch)
    connections = install_auth_db(monkeypatch)

    login_response = client.post(
        "/api/v1/auth/login",
        json={"email": " USER1@sharegrid.vn ", "password": "correct-password"},
    )

    assert login_response.status_code == 200
    body = login_response.json()
    assert body["token_type"] == "bearer"
    assert body["expires_in"] == 900
    claims = auth.decode_access_token(body["access_token"])
    assert claims["sub"] == 3
    assert claims["role"] == "USER"

    me_response = client.get(
        "/api/v1/auth/me",
        headers={
            "Authorization": f"Bearer {body['access_token']}",
            "X-User-Role": "ADMIN",
        },
    )
    assert me_response.status_code == 200
    assert me_response.json()["role"] == "USER"
    assert me_response.json()["vehicles"] == [VEHICLE]
    assert all(connection.closed for connection in connections)


def test_bad_password_and_unsigned_role_header_are_rejected(monkeypatch):
    set_auth_config(monkeypatch)
    install_auth_db(monkeypatch)

    login_response = client.post(
        "/api/v1/auth/login",
        json={"email": "user1@sharegrid.vn", "password": "wrong-password"},
    )
    no_token_response = client.get("/api/v1/auth/me", headers={"X-User-Role": "ADMIN"})

    assert login_response.status_code == 401
    assert login_response.json()["detail"] == "Invalid email or password"
    assert no_token_response.status_code == 401


def test_development_bypass_requires_explicit_environment_setting(monkeypatch):
    monkeypatch.setenv("DEV_AUTH_BYPASS", "1")
    monkeypatch.setenv("DEV_AUTH_USER_ID", "3")
    install_auth_db(monkeypatch)

    response = client.get("/api/v1/auth/me")

    assert response.status_code == 200
    assert response.json()["user_id"] == 3


def test_expired_or_tampered_tokens_are_rejected(monkeypatch):
    set_auth_config(monkeypatch)
    user = AuthUser(3, "USER", "user1@sharegrid.vn", "Test User")
    token, _ = auth.create_access_token(user, now=100)

    try:
        auth.decode_access_token(token, now=100 + 15 * 60)
        assert False, "expired token should be rejected"
    except ValueError:
        pass

    tampered = token[:-1] + ("A" if token[-1] != "A" else "B")
    try:
        auth.decode_access_token(tampered, now=101)
        assert False, "tampered token should be rejected"
    except ValueError:
        pass

@pytest.fixture(autouse=True)
def reset_limit(monkeypatch):
    monkeypatch.setattr(auth_route, "_buckets", auth_route.OrderedDict())


def test_register_login_and_profile_only_expose_public_fields(monkeypatch):
    set_auth_config(monkeypatch)
    install_auth_db(monkeypatch)
    users = {}
    base_execute = AuthCursor.execute

    def execute(self, query, params=()):
        if "INSERT INTO app_user" in query:
            name, email, phone, encoded, _ = params
            self.one = None
            if email not in users:
                self.one = dict(user_id=9, role="USER", email=email, full_name=name)
                users[email] = dict(self.one, password_hash=encoded, phone=phone)
        elif "FROM app_user" in query:
            self.one = next(iter(users.values()))
        else:
            base_execute(self, query, params)
    monkeypatch.setattr(AuthCursor, "execute", execute)
    password = secrets.token_urlsafe(24)
    payload = dict(full_name="  Chủ xe  ", email=" Test@Example.org ", password=password,
                   role="ADMIN", phone="0900123456")
    reg = client.post("/api/v1/auth/register", json=payload)
    assert reg.status_code == 200
    body = reg.json()
    assert set(body) == {"access_token", "token_type", "expires_in", "user"}
    assert body["user"] == dict(user_id=9, role="USER", email="test@example.org", full_name="Chủ xe")
    stored = users["test@example.org"]
    assert stored["phone"] == payload["phone"] and auth.verify_password(password, stored["password_hash"])
    login = client.post("/api/v1/auth/login", json=payload)
    assert login.status_code == 200 and login.json()["user"] == body["user"]
    me = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.status_code == 200 and me.json()["role"] == "USER"
    duplicate = client.post("/api/v1/auth/register", json=dict(payload, email="TEST@EXAMPLE.ORG"))
    assert duplicate.status_code == 409
    for response in (reg, login, me, duplicate):
        assert "password_hash" not in response.text and stored["password_hash"] not in response.text
        assert password not in response.text


@pytest.mark.parametrize("email", auth.DEMO_EMAILS)
def test_cannot_register_demo_even_before_seed(email):
    response = client.post("/api/v1/auth/register", json={
        "full_name": "Test", "email": email.upper(), "password": secrets.token_urlsafe(12)})
    assert response.status_code == 409


@pytest.mark.parametrize(("field", "value"), [
    ("email", "invalid"), ("password", "t!3x"), ("password", "x" * 129),
    ("full_name", "    "), ("full_name", "a" * 101), ("phone", "1" * 21),
])
def test_invalid_registration_never_echoes_credentials(field, value):
    payload = dict(full_name="Test", email="one@example.test", password=secrets.token_urlsafe(12))
    payload[field] = value
    response = client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 422
    assert payload["password"] not in response.text
    assert all("input" not in error for error in response.json()["detail"])


def test_null_db_hash_denied_and_configured_hash_has_priority(monkeypatch):
    set_auth_config(monkeypatch)
    install_auth_db(monkeypatch)
    monkeypatch.setitem(ACTIVE_USER, "password_hash", None)
    assert client.post("/api/v1/auth/login", json={"email": "other@example.test", "password": ""}).status_code == 401
    db_password = secrets.token_urlsafe(16)
    monkeypatch.setitem(ACTIVE_USER, "password_hash", auth.hash_password(db_password))
    assert client.post("/api/v1/auth/login", json={"email": ACTIVE_USER["email"], "password": db_password}).status_code == 401


def test_login_and_register_share_ip_limit_and_recover(monkeypatch):
    monkeypatch.setattr(auth_route, "AUTH_LIMIT", 2)
    now = [100.]
    monkeypatch.setattr(auth_route, "monotonic", lambda: now[0])
    data = dict(full_name="Test", email=auth.DEMO_EMAILS[0], password=secrets.token_urlsafe(16))
    assert client.post("/api/v1/auth/register", json=data).status_code == 409
    set_auth_config(monkeypatch)
    install_auth_db(monkeypatch)
    assert client.post("/api/v1/auth/login", json=data).status_code == 401
    for endpoint in ("login", "register"):
        response = client.post(f"/api/v1/auth/{endpoint}", json=data)
        assert response.status_code == 429 and response.headers["Retry-After"] == "60"
    now[0] += 60
    assert client.post("/api/v1/auth/register", json=data).status_code == 409


def test_update_profile_and_change_password(monkeypatch):
    set_auth_config(monkeypatch)
    connections = install_auth_db(monkeypatch)

    current_user_data = {
        "user_id": 3,
        "role": "USER",
        "email": "user1@sharegrid.vn",
        "full_name": "Test User",
        "phone": "0912345678",
        "password_hash": auth.hash_password("old-password-123"),
    }

    def fake_execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.one = None
        self.many = []
        if "UPDATE app_user" in normalized:
            if "password_hash" in normalized:
                current_user_data["password_hash"] = params[0]
            else:
                if len(params) == 3:
                    current_user_data["full_name"] = params[0]
                    current_user_data["phone"] = params[1]
                elif len(params) == 2:
                    if "full_name" in normalized:
                        current_user_data["full_name"] = params[0]
                    elif "phone" in normalized:
                        current_user_data["phone"] = params[0]
            self.one = dict(current_user_data)
        elif "FROM app_user" in normalized:
            self.one = dict(current_user_data)
        elif "FROM vehicle v" in normalized:
            self.many = [dict(VEHICLE)]

    monkeypatch.setattr(AuthCursor, "execute", fake_execute)

    user = AuthUser(3, "USER", "user1@sharegrid.vn", "Test User")
    token, _ = auth.create_access_token(user)
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Update profile
    patch_resp = client.patch(
        "/api/v1/auth/me",
        headers=headers,
        json={"full_name": "Nguyễn Văn A", "phone": "0987654321"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["full_name"] == "Nguyễn Văn A"
    assert patch_resp.json()["phone"] == "0987654321"

    # 2. Change password - wrong old password
    bad_pw = client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={"current_password": "wrong-password", "new_password": "new-password-123"},
    )
    assert bad_pw.status_code == 400
    assert "Mật khẩu hiện tại không chính xác" in bad_pw.json()["detail"]

    # 3. Change password - success
    good_pw = client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={"current_password": "old-password-123", "new_password": "new-password-123"},
    )
    assert good_pw.status_code == 200
    assert auth.verify_password("new-password-123", current_user_data["password_hash"])

