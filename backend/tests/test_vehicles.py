import pytest
from fastapi.testclient import TestClient

from backend.auth import AuthUser, get_current_user
from backend.main import app
from backend.routes import vehicles as vehicles_route

CLIENT = TestClient(app)
USER = AuthUser(user_id=7, role="USER", email="driver7@sharegrid.vn", full_name="Anh Driver")


class FakeCursor:
    def __init__(self, vehicles_data=None, active_request=False):
        self.vehicles = vehicles_data or [
            {
                "vehicle_id": 10,
                "user_id": 7,
                "model_id": 1,
                "plate_number": "43A-999.99",
                "nickname": "Xe Cưng",
                "default_soc_target": 80.0,
                "is_default": True,
                "brand": "VinFast",
                "model_name": "VF 8",
                "vehicle_type": "CAR",
                "connector_type": "CCS2",
                "battery_kwh": 87.7,
                "max_kw": 250.0,
            }
        ]
        self.active_request = active_request
        self.executed = []
        self.one = None
        self.many = []

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False

    def execute(self, query, params=()):
        norm = " ".join(query.split())
        self.executed.append((norm, params))
        if "FROM vehicle_model WHERE model_id" in norm:
            self.one = {"model_id": params[0]}
        elif "SELECT COUNT(*)" in norm:
            self.one = {"count": len(self.vehicles)}
        elif "INSERT INTO vehicle" in norm:
            self.one = {
                "vehicle_id": 11,
                "model_id": params[1],
                "plate_number": params[2],
                "nickname": params[3],
                "default_soc_target": params[4],
                "is_default": params[5],
            }
        elif "SELECT v.vehicle_id" in norm and "WHERE v.vehicle_id = %s" in norm:
            self.one = {
                "vehicle_id": params[0],
                "model_id": 1,
                "plate_number": "43A-888.88",
                "license_plate": "43A-888.88",
                "nickname": "Xe Mới",
                "default_soc_target": 80.0,
                "is_default": True,
                "brand": "VinFast",
                "model_name": "VF 8",
                "vehicle_type": "CAR",
                "connector_type": "CCS2",
                "battery_kwh": 87.7,
                "max_kw": 250.0,
            }
        elif "SELECT v.vehicle_id" in norm and "WHERE v.user_id = %s" in norm:
            self.many = list(self.vehicles)
        elif "SELECT vehicle_id, is_default FROM vehicle" in norm:
            self.one = {"vehicle_id": params[0], "is_default": True}
        elif "SELECT request_id FROM charging_request" in norm:
            self.one = {"request_id": 99} if self.active_request else None
        elif "DELETE FROM vehicle" in norm:
            self.one = None
        elif "UPDATE vehicle" in norm:
            self.one = None
        else:
            self.one = None
            self.many = []

    def fetchone(self):
        return self.one

    def fetchall(self):
        return self.many


class FakeConnection:
    def __init__(self, vehicles_data=None, active_request=False):
        self.fake_cursor = FakeCursor(vehicles_data, active_request)
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def close(self):
        self.closed = True


@pytest.fixture(autouse=True)
def override_user():
    app.dependency_overrides[get_current_user] = lambda: USER
    yield
    app.dependency_overrides.pop(get_current_user, None)


def test_get_vehicles(monkeypatch):
    conn = FakeConnection()
    monkeypatch.setattr(vehicles_route, "connect", lambda: conn)
    monkeypatch.setattr(vehicles_route, "dict_cursor", lambda _c: conn.fake_cursor)

    resp = CLIENT.get("/api/v1/vehicles")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "success"
    assert body["count"] == 1
    assert body["data"][0]["plate_number"] == "43A-999.99"


def test_create_vehicle(monkeypatch):
    conn = FakeConnection()
    monkeypatch.setattr(vehicles_route, "connect", lambda: conn)
    monkeypatch.setattr(vehicles_route, "dict_cursor", lambda _c: conn.fake_cursor)

    payload = {
        "model_id": 1,
        "license_plate": "43A-888.88",
        "nickname": "Xe Mới",
        "is_default": True,
    }
    resp = CLIENT.post("/api/v1/vehicles", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    assert body["status"] == "success"
    assert body["data"]["plate_number"] == "43A-888.88"


def test_patch_vehicle(monkeypatch):
    conn = FakeConnection()
    monkeypatch.setattr(vehicles_route, "connect", lambda: conn)
    monkeypatch.setattr(vehicles_route, "dict_cursor", lambda _c: conn.fake_cursor)

    payload = {"nickname": "Tên Đã Sửa", "is_default": True}
    resp = CLIENT.patch("/api/v1/vehicles/10", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "success"


def test_delete_vehicle_success(monkeypatch):
    conn = FakeConnection(active_request=False)
    monkeypatch.setattr(vehicles_route, "connect", lambda: conn)
    monkeypatch.setattr(vehicles_route, "dict_cursor", lambda _c: conn.fake_cursor)

    resp = CLIENT.delete("/api/v1/vehicles/10")
    assert resp.status_code == 200
    assert "Đã xóa" in resp.json()["message"]


def test_delete_vehicle_blocked_when_active(monkeypatch):
    conn = FakeConnection(active_request=True)
    monkeypatch.setattr(vehicles_route, "connect", lambda: conn)
    monkeypatch.setattr(vehicles_route, "dict_cursor", lambda _c: conn.fake_cursor)

    resp = CLIENT.delete("/api/v1/vehicles/10")
    assert resp.status_code == 400
    assert "Không thể xóa xe đang có lịch" in resp.json()["detail"]
