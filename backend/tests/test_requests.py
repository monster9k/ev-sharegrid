from datetime import date, datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

import httpx
from fastapi.testclient import TestClient

from backend import ai_contract
from backend.auth import AuthUser, get_current_user
from backend.main import app
from backend.routes import requests as requests_route


TZ = ZoneInfo("Asia/Ho_Chi_Minh")
CLIENT = TestClient(app)


class FakeCursor:
    def __init__(self, request_times):
        self.request_times = request_times
        self.executed = []
        self.one = None
        self.many = []
        self.closed = False

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        self.close()

    def close(self):
        self.closed = True

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.executed.append((normalized, params))
        self.one = None
        self.many = []

        if "SELECT v.vehicle_id" in normalized:
            self.one = {
                "vehicle_id": 5,
                "user_id": 3,
                "battery_kwh": Decimal("60"),
                "max_kw": Decimal("11"),
            }
        elif "SELECT s.station_id, s.cluster_id" in normalized:
            self.one = {"station_id": 10, "cluster_id": 7}
        elif "SELECT request_id FROM charging_request WHERE idempotency_key" in normalized:
            self.one = None
        elif "SELECT request_id FROM charging_request WHERE vehicle_id" in normalized:
            self.one = None
        elif "RETURNING request_id, cluster_id, energy_needed_kwh" in normalized:
            self.one = {
                "request_id": 31,
                "cluster_id": 7,
                "energy_needed_kwh": Decimal("10.000000"),
            }
        elif "RETURNING event_id" in normalized:
            self.one = (801,)
        elif "SELECT pg_advisory_xact_lock" in normalized:
            self.one = None
        elif "SELECT COALESCE(MAX(target_version)" in normalized:
            self.one = (1,)
        elif "RETURNING job_id" in normalized:
            self.one = (501,)
        elif "RETURNING run_id" in normalized:
            self.one = (901,)
        elif "FROM grid_cluster" in normalized:
            self.one = {
                "cluster_id": 7,
                "grid_limit_kw": Decimal("12"),
                "timezone": "Asia/Ho_Chi_Minh",
            }
        elif "SELECT station_id, station_power_kw" in normalized:
            self.many = [{
                "station_id": 10,
                "station_power_kw": Decimal("12"),
                "open_time": time(0),
                "close_time": time(0),
                "is_24h": True,
            }]
        elif "FROM port p" in normalized:
            self.many = [{
                "port_id": 20,
                "station_id": 10,
                "connector_type": "CCS2",
                "control_type": "CONTINUOUS",
                "status": "ACTIVE",
                "min_power_kw": Decimal("0"),
                "max_power_kw": Decimal("11"),
            }]
        elif "SELECT request_id, user_id, shortfall_kwh FROM charging_request" in normalized:
            self.many = [{"request_id": 31, "user_id": 3, "shortfall_kwh": Decimal("0")}]
        elif "FROM charging_request cr" in normalized:
            self.many = [{
                "request_id": 31,
                "station_id": 10,
                "arrival_time": self.request_times[0],
                "departure_time": self.request_times[1],
                "battery_kwh_snapshot": Decimal("60"),
                "max_kw_snapshot": Decimal("11"),
                "energy_needed_kwh": Decimal("10.000000"),
                "priority_weight": Decimal("1"),
                "status": "PENDING",
                "connector_type": "CCS2",
                "energy_delivered_kwh": Decimal("0"),
                "locked_port_id": None,
            }]
        elif "FROM schedule sc" in normalized:
            self.many = []
        elif "FROM run_request rr" in normalized:
            self.many = []
        elif "FROM tariff_window" in normalized:
            self.many = [
                {
                    "day_type": "WEEKDAY",
                    "start_time": time(0),
                    "end_time": time(12),
                    "price_vnd_kwh": Decimal("1600"),
                    "valid_from": date(2025, 1, 1),
                    "valid_to": date(2099, 12, 31),
                },
                {
                    "day_type": "WEEKDAY",
                    "start_time": time(12),
                    "end_time": time(0),
                    "price_vnd_kwh": Decimal("2400"),
                    "valid_from": date(2025, 1, 1),
                    "valid_to": date(2099, 12, 31),
                },
            ]
        elif normalized.startswith(("SAVEPOINT ", "ROLLBACK TO SAVEPOINT ", "UPDATE ", "INSERT ")):
            # Most writes in the optimizer do not return rows. INSERT statements with
            # RETURNING clauses are handled above to mimic psycopg's tuple cursor.
            self.one = None
        else:
            raise AssertionError(f"Unexpected SQL: {normalized}")

    def fetchone(self):
        return self.one

    def fetchall(self):
        return self.many


class FakeConnection:
    def __init__(self, request_times):
        self.fake_cursor = FakeCursor(request_times)
        self.commits = 0
        self.rollbacks = 0
        self.closed = False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        if exc_type is None:
            self.commit()
        else:
            self.rollback()

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1

    def close(self):
        self.closed = True


def response_body():
    return {
        "status": "FEASIBLE",
        "algorithm": "MILP_MPC",
        "solve_ms": 5.5,
        "kpi": {
            "total_shortfall_kwh": 2,
            "total_cost_vnd": 16000,
            "peak_power_kw": 8,
            "on_time_rate": 0,
            "fairness": 0.8,
            "cap_violations": 0,
        },
        "request_results": [{
            "request_id": "31",
            "allocated_kwh": 8,
            "shortfall_kwh": 2,
            "expected_soc": 33.333333,
            "estimated_cost_vnd": 16000,
            "explanation": "Phân bổ theo thời gian đỗ xe.",
        }],
        "schedules": [],
    }


def install_fake_services(monkeypatch, *, timeout=False):
    now = datetime.now(TZ).replace(second=0, microsecond=0)
    arrival = now + timedelta(hours=1)
    departure = arrival + timedelta(hours=2)
    booking_db = FakeConnection((arrival, departure))
    optimization_db = FakeConnection((arrival, departure))
    connections = iter((booking_db, optimization_db))
    monkeypatch.setattr(requests_route, "connect", lambda: next(connections))
    monkeypatch.setattr(ai_contract, "connect", lambda: optimization_db)
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(3, "USER", "user1@sharegrid.vn", "Test User"),
    )
    monkeypatch.setenv("AI_URL", "http://ai-engine.test")

    calls = []

    def fake_post(url, *, json, timeout):
        calls.append((url, json, timeout))
        if timeout and should_timeout:
            raise httpx.TimeoutException("test timeout")

        class Response:
            status_code = 200
            text = ""

            @staticmethod
            def json():
                return response_body()

        return Response()

    should_timeout = timeout
    monkeypatch.setattr(ai_contract.httpx, "post", fake_post)
    payload = {
        "user_id": 3,
        "vehicle_id": 5,
        "station_id": 10,
        "arrival_time": arrival.isoformat(),
        "departure_time": departure.isoformat(),
        "soc_now": 20,
        "soc_target": 35,
        "idempotency_key": "test-booking-31",
    }
    return booking_db, optimization_db, calls, payload


def test_booking_calls_ai_and_returns_selected_request_result(monkeypatch):
    booking_db, optimization_db, calls, payload = install_fake_services(monkeypatch)

    response = CLIENT.post("/api/v1/requests", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["request_id"] == 31
    assert body["energy_needed_kwh"] == 10
    assert body["allocated_kwh"] == 8
    assert body["shortfall_kwh"] == 2
    assert booking_db.commits == 1
    assert calls[0][0] == "http://ai-engine.test/ai/optimize"
    assert calls[0][2] == 15.0
    request = calls[0][1]["requests"][0]
    assert request["energy_needed_kwh"] == 10
    assert request["connector_type"] == "CCS2"
    assert optimization_db.fake_cursor.executed[0][0].startswith("SELECT pg_advisory_xact_lock")
    assert "COALESCE(MAX(target_version)" in optimization_db.fake_cursor.executed[1][0]
    assert any("UPDATE schedule sc SET is_active = FALSE" in sql for sql, _ in optimization_db.fake_cursor.executed)
    assert not any("INSERT INTO notification" in sql for sql, _ in optimization_db.fake_cursor.executed)
    assert any("status = 'COMPLETED'" in sql for sql, _ in optimization_db.fake_cursor.executed)


def test_ai_timeout_keeps_committed_request_pending(monkeypatch):
    booking_db, optimization_db, calls, payload = install_fake_services(monkeypatch, timeout=True)

    response = CLIENT.post("/api/v1/requests", json=payload)

    assert response.status_code == 503
    assert "request 31 remains PENDING" in response.json()["detail"]
    assert booking_db.commits == 1
    assert calls[0][2] == 15.0
    executed_sql = [sql for sql, _ in optimization_db.fake_cursor.executed]
    assert any("status = 'FAILED'" in sql for sql in executed_sql)
    assert not any("UPDATE charging_request SET shortfall_kwh" in sql for sql in executed_sql)


def test_overlapping_vehicle_request_returns_409(monkeypatch):
    now = datetime.now(TZ).replace(second=0, microsecond=0)
    booking_db = FakeConnection((now + timedelta(hours=1), now + timedelta(hours=2)))
    connections = iter((booking_db,))
    monkeypatch.setattr(requests_route, "connect", lambda: next(connections))

    class OverlapCursor(FakeCursor):
        def execute(self, query, params=()):
            super().execute(query, params)
            if "SELECT request_id FROM charging_request WHERE vehicle_id" in " ".join(query.split()):
                self.one = {"request_id": 99}

    booking_db.fake_cursor = OverlapCursor((now + timedelta(hours=1), now + timedelta(hours=2)))
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(3, "USER", "user1@sharegrid.vn", "Test User"),
    )
    payload = {
        "user_id": 3,
        "vehicle_id": 5,
        "station_id": 10,
        "arrival_time": (now + timedelta(hours=1)).isoformat(),
        "departure_time": (now + timedelta(hours=2)).isoformat(),
        "soc_now": 20,
        "soc_target": 35,
        "idempotency_key": "overlap-booking",
    }

    response = CLIENT.post("/api/v1/requests", json=payload)

    assert response.status_code == 409
    assert "overlapping" in response.json()["detail"]
    assert booking_db.commits == 0
