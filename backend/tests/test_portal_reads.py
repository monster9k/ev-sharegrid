from datetime import datetime, timezone

import httpx
import pytest
from fastapi.testclient import TestClient

from backend.auth import AuthUser, get_current_user
from backend.main import app
from backend.routes import admin, host, requests


client = TestClient(app)


class ReadConnection:
    def __init__(self, rows):
        self.rows = rows
        self.executed = []
        self.closed = False

    def execute(self, sql, params=()):
        self.executed.append((sql, params))

    def fetchall(self):
        return self.rows

    def close(self):
        self.closed = True

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def setup(monkeypatch, module, role, rows, user_id=41):
    connection = ReadConnection(rows)
    monkeypatch.setattr(module, "connect", lambda: connection)
    monkeypatch.setattr(module, "dict_cursor", lambda conn: conn)
    monkeypatch.setitem(
        app.dependency_overrides, get_current_user,
        lambda: AuthUser(user_id, role, "test@example.test", "Test"),
    )
    return connection


def test_requests_me_uses_authenticated_user_and_validates_limit(monkeypatch):
    db = setup(monkeypatch, requests, "USER", [{"request_id": 8}])
    response = client.get("/api/v1/requests/me?limit=1&user_id=10")
    assert response.json() == {"count": 1, "data": [{"request_id": 8}]}
    query, params = db.executed[0]
    assert "WHERE r.user_id = %s" in query
    assert params == (41, 1)
    assert db.closed
    assert client.get("/api/v1/requests/me?limit=201").status_code == 422


def test_host_stations_filters_owner_and_embeds_owned_ports(monkeypatch):
    owned = [{"station_id": 12, "ports": [{"port_id": 32, "status": "ACTIVE"}]}]
    db = setup(monkeypatch, host, "HOST", owned, user_id=7)
    response = client.get("/api/v1/host/stations?owner_id=99")
    assert response.json() == {"count": 1, "data": owned}
    query, params = db.executed[0]
    assert "WHERE s.owner_id = %s" in query
    assert "station_id = s.station_id" in query
    assert params == (7,)
    other = setup(monkeypatch, host, "HOST", [], user_id=99)
    assert client.get("/api/v1/host/stations?owner_id=7").json()["data"] == []
    assert other.executed[0][1] == (99,)


def test_admin_station_status_filter(monkeypatch):
    db = setup(monkeypatch, admin, "ADMIN", [{"station_id": 12, "status": "PENDING"}])
    result = client.get("/api/v1/admin/stations?status=PENDING")
    assert result.json() == {"count": 1, "data": [{"station_id": 12, "status": "PENDING"}]}
    assert db.executed[0][1] == ("PENDING", "PENDING")
    assert client.get("/api/v1/admin/stations?status=REJECTED").status_code == 422


def test_admin_clusters_load_active_tariff_windows(monkeypatch):
    rows = [{"cluster_id": 1, "tariffs": [{"day_type": "MON_SAT", "price_vnd_kwh": 1620}]}]
    db = setup(monkeypatch, admin, "ADMIN", rows)
    assert client.get("/api/v1/admin/clusters").json()["data"] == rows
    assert "CURRENT_DATE BETWEEN valid_from AND valid_to" in db.executed[0][0]


@pytest.mark.parametrize("method,path", [
    ("GET", "/api/v1/host/stations"),
    ("GET", "/api/v1/admin/clusters"),
    ("GET", "/api/v1/admin/stations?status=PENDING"),
    ("POST", "/api/v1/admin/forecast"),
])
def test_user_cannot_access_portal_routes(monkeypatch, method, path):
    db = setup(monkeypatch, admin, "USER", [])
    assert client.request(method, path, json={"cluster_id": 1}).status_code == 403
    assert db.executed == []


def test_host_cannot_read_user_bookings(monkeypatch):
    db = setup(monkeypatch, requests, "HOST", [])
    assert client.get("/api/v1/requests/me").status_code == 403
    assert db.executed == []


def test_forecast_proxies_real_history_and_reports_actual_model(monkeypatch):
    hour = datetime(2026, 11, 20, 2, tzinfo=timezone.utc)
    db = setup(monkeypatch, admin, "ADMIN", [{"hour_start": hour, "arrivals": 3}])
    monkeypatch.setenv("AI_URL", "http://engine:8001/")
    calls = []

    def forecast(url, *, json, timeout):
        calls.append((url, json, timeout))
        return httpx.Response(200, json={
            "cluster_id": "9", "model": "HOURLY_MEAN", "horizon_hours": 1,
            "predictions": [{"hour_start": "2026-11-20T10:00:00+07:00", "pred_arrivals": 3}],
            "warnings": ["Dưới 14 ngày quan sát."],
        })

    monkeypatch.setattr(admin.httpx, "post", forecast)
    result = client.post("/api/v1/admin/forecast", json={"cluster_id": 9, "horizon_hours": 1})
    assert result.status_code == 200
    assert result.json()["model"] == "HOURLY_MEAN"
    assert result.json()["predictions"][0]["pred_arrivals"] == 3
    assert result.json()["warnings"]
    assert db.executed[0][1] == (9,)
    assert "is_simulated IS FALSE" in db.executed[0][0]
    assert calls == [("http://engine:8001/ai/forecast", {
        "cluster_id": "9", "history": [{"hour_start": "2026-11-20T09:00:00+07:00", "arrivals": 3}],
        "horizon_hours": 1, "model": "BEST",
    }, admin.AI_TIMEOUT_SECONDS)]


def test_forecast_without_history_does_not_generate_sample_data(monkeypatch):
    setup(monkeypatch, admin, "ADMIN", [])
    monkeypatch.setenv("AI_URL", "http://engine:8001")
    monkeypatch.setattr(admin.httpx, "post", lambda *args, **kwargs: pytest.fail("unexpected AI call"))
    assert client.post("/api/v1/admin/forecast", json={"cluster_id": 1}).status_code == 409
