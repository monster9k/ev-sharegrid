from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient

from backend.auth import AuthUser, get_current_user
from backend.main import app
from backend.routes import host


client = TestClient(app)


class HostCursor:
    def __init__(self, *, owned=True):
        self.owned = owned
        self.one = None
        self.many = []
        self.executed = []

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.executed.append((normalized, params))
        self.one = None
        self.many = []
        if "FROM grid_cluster" in normalized:
            self.one = {"cluster_id": 7}
        elif "SELECT station_id FROM charging_station" in normalized:
            if self.owned:
                self.one = {"station_id": 10}
        elif "INSERT INTO charging_station" in normalized:
            self.one = (10, "PENDING", False)
        elif "INSERT INTO port" in normalized:
            self.one = (42, "ACTIVE")
        elif "UPDATE port p SET status" in normalized:
            if self.owned:
                self.one = {"port_id": 42, "status": "OFFLINE", "cluster_id": 7}
        elif "FROM schedule sc" in normalized:
            self.many = [{
                "schedule_id": 901,
                "request_id": 31,
                "port_id": 42,
                "slot_start": datetime(2026, 11, 19, 10, 0, tzinfo=timezone.utc),
                "power_kw": 7,
                "version": 4,
            }]
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


class HostConnection:
    def __init__(self, *, owned=True):
        self.fake_cursor = HostCursor(owned=owned)
        self.closed = False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def close(self):
        self.closed = True


def setup(monkeypatch, *, owned=True):
    connection = HostConnection(owned=owned)
    monkeypatch.setattr(host, "connect", lambda: connection)
    monkeypatch.setattr(host, "dict_cursor", lambda conn: conn.cursor())
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(2, "HOST", "host1@sharegrid.vn", "Station Host"),
    )
    return connection


def test_host_station_is_created_pending_and_unverified(monkeypatch):
    connection = setup(monkeypatch)
    payload = {
        "cluster_id": 7,
        "name": "New Station",
        "address": "123 Main Street",
        "province": "Đà Nẵng",
        "lat": 16.05,
        "lng": 108.2,
        "station_power_kw": 44,
    }

    response = client.post("/api/v1/host/stations", json=payload)

    assert response.status_code == 201
    assert response.json() == {"station_id": 10, "status": "PENDING", "verified": False}
    insert_sql, params = next(item for item in connection.fake_cursor.executed if "INSERT INTO charging_station" in item[0])
    assert "'PENDING'" in insert_sql and "FALSE" in insert_sql
    assert params[1] == 2


def test_host_can_add_port_only_to_owned_station(monkeypatch):
    connection = setup(monkeypatch)

    response = client.post(
        "/api/v1/host/stations/10/ports",
        json={
            "port_code": "P1",
            "connector_type": "CCS2",
            "control_type": "CONTINUOUS",
            "min_power_kw": 2,
            "max_power_kw": 11,
        },
    )

    assert response.status_code == 201
    assert response.json() == {"port_id": 42, "status": "ACTIVE"}
    assert (10, 2) in [params for sql, params in connection.fake_cursor.executed if "owner_id" in sql]

    other_connection = setup(monkeypatch, owned=False)
    other = client.post(
        "/api/v1/host/stations/999/ports",
        json={"port_code": "P1", "connector_type": "CCS2", "control_type": "CONTINUOUS", "max_power_kw": 11},
    )
    assert other.status_code == 404
    assert not any("INSERT INTO port" in sql for sql, _ in other_connection.fake_cursor.executed)


def test_port_fault_is_owner_scoped_and_reoptimizes(monkeypatch):
    setup(monkeypatch)
    calls = []
    monkeypatch.setattr(
        host,
        "trigger_cluster_reoptimize",
        lambda cluster_id, **kwargs: calls.append((cluster_id, kwargs)) or SimpleNamespace(status=SimpleNamespace(value="FEASIBLE")),
    )

    response = client.patch("/api/v1/host/ports/42/status", json={"status": "OFFLINE"})

    assert response.status_code == 200
    assert calls == [(7, {"trigger_type": "PORT_FAULT"})]


def test_user_cannot_promote_themselves_to_host_with_role_header(monkeypatch):
    setup(monkeypatch)
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(3, "USER", "user1@sharegrid.vn", "User"),
    )

    response = client.post(
        "/api/v1/host/stations/10/ports",
        headers={"X-User-Role": "HOST"},
        json={"port_code": "P1", "connector_type": "CCS2", "control_type": "CONTINUOUS", "max_power_kw": 11},
    )

    assert response.status_code == 403


def test_host_station_schedule_returns_quarter_hour_slots(monkeypatch):
    setup(monkeypatch)

    response = client.get("/api/v1/host/stations/10/schedule")

    assert response.status_code == 200
    assert response.json()["slot_minutes"] == 15
    assert response.json()["slots"][0]["slot_end"] == "2026-11-19T10:15:00+00:00"
