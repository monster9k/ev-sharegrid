import json

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
