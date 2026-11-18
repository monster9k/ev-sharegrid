from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient

from backend.auth import AuthUser, get_current_user
from backend.ai_contract import AIUpstreamError
from backend.main import app
from backend.routes import request_actions


client = TestClient(app)


class ActionCursor:
    def __init__(self, *, status="SCHEDULED", late=True, found=True):
        now = datetime.now(timezone.utc)
        self.checked_at = now
        self.arrival_time = now - timedelta(hours=1) if late else now
        self.departure_time = now + timedelta(hours=2)
        self.status = status
        self.found = found
        self.one = None
        self.executed = []

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.executed.append((normalized, params))
        self.one = None
        if "SELECT status FROM charging_request" in normalized:
            if self.found:
                self.one = {"status": self.status}
        elif "SELECT cluster_id, status, arrival_time" in normalized:
            if self.found:
                self.one = {
                    "cluster_id": 7,
                    "status": self.status,
                    "arrival_time": self.arrival_time,
                    "departure_time": self.departure_time,
                    "soc_now": 20,
                    "checked_at": self.checked_at,
                }
        elif "SELECT cluster_id, status FROM charging_request" in normalized:
            if self.found:
                self.one = {"cluster_id": 7, "status": self.status}
        elif "SELECT session_id FROM charging_session" in normalized:
            self.one = None
        elif "SELECT port_id FROM schedule" in normalized:
            self.one = {"port_id": 42}
        elif "RETURNING session_id" in normalized:
            self.one = (501,)
        elif normalized.startswith("UPDATE "):
            self.one = None
        else:
            raise AssertionError(f"Unexpected SQL: {normalized}")

    def fetchone(self):
        return self.one

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False


class ActionConnection:
    def __init__(self, **kwargs):
        self.fake_cursor = ActionCursor(**kwargs)
        self.closed = False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def close(self):
        self.closed = True


def setup(monkeypatch, *, status="SCHEDULED", late=True, found=True):
    connection = ActionConnection(status=status, late=late, found=found)
    monkeypatch.setattr(request_actions, "connect", lambda: connection)
    monkeypatch.setattr(request_actions, "dict_cursor", lambda conn: conn.cursor())
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(3, "USER", "user1@sharegrid.vn", "Test User"),
    )
    return connection


def test_confirm_checks_owner_and_status(monkeypatch):
    connection = setup(monkeypatch)

    response = client.post("/api/v1/requests/31/confirm")

    assert response.status_code == 200
    assert response.json() == {"request_id": 31, "status": "CONFIRMED"}
    assert connection.fake_cursor.executed[0][1] == (31, 3)
    assert any("SET status = 'CONFIRMED'" in sql for sql, _ in connection.fake_cursor.executed)
    assert connection.closed


def test_cancel_deactivates_future_schedule_and_reoptimizes(monkeypatch):
    connection = setup(monkeypatch)
    calls = []
    monkeypatch.setattr(
        request_actions,
        "trigger_cluster_reoptimize",
        lambda cluster_id, **kwargs: calls.append((cluster_id, kwargs)) or SimpleNamespace(status=SimpleNamespace(value="FEASIBLE")),
    )

    response = client.post("/api/v1/requests/31/cancel")

    assert response.status_code == 200
    assert response.json()["status"] == "CANCELLED"
    assert calls == [(7, {"trigger_type": "USER_CANCEL"})]
    assert any("slot_start >= CURRENT_TIMESTAMP" in sql for sql, _ in connection.fake_cursor.executed)


def test_cancel_ai_failure_does_not_claim_request_is_pending(monkeypatch):
    setup(monkeypatch)
    monkeypatch.setattr(
        request_actions,
        "trigger_cluster_reoptimize",
        lambda *args, **kwargs: (_ for _ in ()).throw(AIUpstreamError(503, "AI Engine unavailable")),
    )

    response = client.post("/api/v1/requests/31/cancel")

    assert response.status_code == 503
    assert "CANCELLED" not in response.json()["detail"]
    assert "PENDING" not in response.json()["detail"]


def test_late_checkin_creates_in_progress_session_and_reoptimizes(monkeypatch):
    connection = setup(monkeypatch, status="CONFIRMED", late=True)
    calls = []
    monkeypatch.setattr(
        request_actions,
        "trigger_cluster_reoptimize",
        lambda cluster_id, **kwargs: calls.append((cluster_id, kwargs)) or SimpleNamespace(status=SimpleNamespace(value="FEASIBLE")),
    )

    response = client.post("/api/v1/requests/31/checkin")

    assert response.status_code == 200
    assert response.json()["session_id"] == 501
    assert response.json()["port_id"] == 42
    assert calls == [(7, {"trigger_type": "LATE_CHECKIN"})]
    insert_sql, insert_params = next(item for item in connection.fake_cursor.executed if "INSERT INTO charging_session" in item[0])
    assert "'IN_PROGRESS', FALSE" in insert_sql
    assert insert_params == (31, 42, 20)


def test_request_actions_do_not_reveal_other_users_requests(monkeypatch):
    setup(monkeypatch, found=False)

    response = client.post("/api/v1/requests/99/confirm")

    assert response.status_code == 404
    assert response.json()["detail"] == "Charging request not found"
