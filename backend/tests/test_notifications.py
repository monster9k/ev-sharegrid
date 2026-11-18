from datetime import datetime, timezone

from fastapi.testclient import TestClient

from backend.auth import AuthUser, get_current_user
from backend.main import app
from backend.routes import notifications


client = TestClient(app)


class NotificationCursor:
    def __init__(self, *, found=True):
        self.found = found
        self.one = None
        self.many = []
        self.executed = []

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.executed.append((normalized, params))
        self.one = None
        self.many = []
        if "FROM notification" in normalized:
            self.many = [{
                "notif_id": 5,
                "request_id": 31,
                "type": "SCHEDULE_CHANGED",
                "title": "Schedule changed",
                "body": "A slot changed.",
                "channel": "APP_PUSH",
                "created_at": datetime(2026, 11, 19, tzinfo=timezone.utc),
                "sent_at": None,
                "read_at": None,
            }]
        elif normalized.startswith("UPDATE notification"):
            if self.found:
                self.one = {"notif_id": 5, "read_at": datetime(2026, 11, 19, tzinfo=timezone.utc)}
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


class NotificationConnection:
    def __init__(self, *, found=True):
        self.fake_cursor = NotificationCursor(found=found)
        self.closed = False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def close(self):
        self.closed = True


def setup(monkeypatch, *, found=True):
    connection = NotificationConnection(found=found)
    monkeypatch.setattr(notifications, "connect", lambda: connection)
    monkeypatch.setattr(notifications, "dict_cursor", lambda conn: conn.cursor())
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(3, "USER", "user1@sharegrid.vn", "Test User"),
    )
    return connection


def test_notification_list_is_scoped_to_authenticated_user(monkeypatch):
    connection = setup(monkeypatch)

    response = client.get("/api/v1/notifications?limit=12")

    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert connection.fake_cursor.executed[0][1] == (3, 12)
    assert "WHERE user_id = %s" in connection.fake_cursor.executed[0][0]


def test_mark_read_updates_only_own_notification(monkeypatch):
    connection = setup(monkeypatch)

    response = client.patch("/api/v1/notifications/5/read")

    assert response.status_code == 200
    assert response.json()["notification_id"] == 5
    assert connection.fake_cursor.executed[0][1] == (5, 3)
    assert "WHERE notif_id = %s AND user_id = %s" in connection.fake_cursor.executed[0][0]


def test_mark_read_hides_notifications_of_other_users(monkeypatch):
    setup(monkeypatch, found=False)

    response = client.patch("/api/v1/notifications/999/read")

    assert response.status_code == 404
    assert response.json()["detail"] == "Notification not found"
