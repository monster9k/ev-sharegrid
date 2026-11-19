import json
from datetime import datetime, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient

from backend.auth import AuthUser, get_current_user
from backend.main import app
from backend.routes import admin


client = TestClient(app)


class AdminCursor:
    def __init__(self, *, station_has_coordinates=True):
        self.station_has_coordinates = station_has_coordinates
        self.one = None
        self.many = []
        self.executed = []

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.executed.append((normalized, params))
        self.one = None
        self.many = []
        if "UPDATE grid_cluster" in normalized:
            self.one = {"cluster_id": 7, "grid_limit_kw": params[0]}
        elif "SELECT station_id, cluster_id, lat, lng FROM charging_station" in normalized:
            self.one = {
                "station_id": 10,
                "cluster_id": 7,
                "lat": 16.05 if self.station_has_coordinates else None,
                "lng": 108.2 if self.station_has_coordinates else None,
            }
        elif "UPDATE charging_station SET verified" in normalized:
            self.one = {"status": params[1]}
        elif "SELECT cluster_id FROM grid_cluster" in normalized:
            self.one = {"cluster_id": 7}
        elif "SELECT benchmark_id" in normalized:
            self.many = [{
                "benchmark_id": 1,
                "scenario_id": 3,
                "run_id": 4,
                "algorithm": "LLF",
                "repeat_no": 1,
                "metrics_json": {"solve_ms": 2.5},
                "measured_at": datetime(2026, 11, 19, tzinfo=timezone.utc),
            }]
        elif "SELECT df.forecast_id" in normalized:
            self.many = [{
                "forecast_id": 5,
                "cluster_id": 7,
                "generated_at": datetime(2026, 11, 19, tzinfo=timezone.utc),
                "hour_start": datetime(2026, 11, 19, 10, tzinfo=timezone.utc),
                "pred_arrivals": 3.5,
                "model_id": 1,
                "model_name": "Hourly Mean",
                "model_version": "1",
                "algorithm": "HOURLY_MEAN",
                "metrics_json": {"mae": 0.5},
            }]
        elif normalized.startswith(("DELETE ", "INSERT ")):
            pass
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


class AdminConnection:
    def __init__(self, **kwargs):
        self.fake_cursor = AdminCursor(**kwargs)
        self.closed = False

    def cursor(self, **kwargs):
        return self.fake_cursor

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def close(self):
        self.closed = True


def setup(monkeypatch, *, station_has_coordinates=True):
    connection = AdminConnection(station_has_coordinates=station_has_coordinates)
    monkeypatch.setattr(admin, "connect", lambda: connection)
    monkeypatch.setattr(admin, "dict_cursor", lambda conn: conn.cursor())
    monkeypatch.setitem(
        app.dependency_overrides,
        get_current_user,
        lambda: AuthUser(1, "ADMIN", "admin@sharegrid.vn", "Admin"),
    )
    return connection


def mock_optimizer(monkeypatch, calls=None):
    if calls is None:
        calls = []
    monkeypatch.setattr(
        admin,
        "trigger_cluster_reoptimize",
        lambda cluster_id, **kwargs: calls.append((cluster_id, kwargs)) or SimpleNamespace(status=SimpleNamespace(value="FEASIBLE")),
    )
    return calls


def test_admin_grid_limit_change_triggers_reoptimization(monkeypatch):
    setup(monkeypatch)
    calls = mock_optimizer(monkeypatch)

    response = client.patch("/api/v1/admin/clusters/7", json={"grid_limit_kw": 400})

    assert response.status_code == 200
    assert response.json()["grid_limit_kw"] == 400
    assert calls == [(7, {"trigger_type": "GRID_LIMIT_CHANGED"})]


def test_admin_cannot_verify_station_without_coordinates(monkeypatch):
    connection = setup(monkeypatch, station_has_coordinates=False)
    calls = mock_optimizer(monkeypatch)

    response = client.patch("/api/v1/admin/stations/10/verify", json={"verified": True})

    assert response.status_code == 409
    assert not any("UPDATE charging_station SET verified" in sql for sql, _ in connection.fake_cursor.executed)
    assert calls == []


def test_admin_verification_activates_and_triggers_reoptimization(monkeypatch):
    setup(monkeypatch)
    calls = mock_optimizer(monkeypatch)

    response = client.patch("/api/v1/admin/stations/10/verify", json={"verified": True})

    assert response.status_code == 200
    assert response.json()["status"] == "ACTIVE"
    assert calls == [(7, {"trigger_type": "STATION_VERIFIED"})]


def test_admin_tariffs_must_cover_each_day_without_gaps(monkeypatch):
    connection = setup(monkeypatch)
    calls = mock_optimizer(monkeypatch)
    complete = [
        {"day_type": day, "band": band, "start_time": start, "end_time": end, "price_vnd_kwh": 2000}
        for day in ("WEEKDAY", "WEEKEND")
        for band, start, end in (("OFF_PEAK", "00:00", "08:00"), ("NORMAL", "08:00", "24:00"))
    ]

    invalid = [dict(item) for item in complete]
    invalid[0]["end_time"] = "07:00"
    bad = client.put("/api/v1/admin/clusters/7/tariffs", json={"tariffs": invalid})
    good = client.put("/api/v1/admin/clusters/7/tariffs", json={"tariffs": complete})

    assert bad.status_code == 422
    assert good.status_code == 200
    assert good.json()["count"] == 4
    assert calls == [(7, {"trigger_type": "TARIFF_CHANGED"})]
    assert sum("INSERT INTO tariff_window" in sql for sql, _ in connection.fake_cursor.executed) == 4


def test_admin_benchmark_reads_file_then_table(monkeypatch, tmp_path):
    connection = setup(monkeypatch)
    benchmark_file = tmp_path / "custom-report.json"
    benchmark_file.write_text(json.dumps({"seed": 42, "runs": []}), encoding="utf-8")
    monkeypatch.setenv("BENCHMARK_REPORT_PATH", str(benchmark_file))

    from_file = client.get("/api/v1/admin/benchmark")
    benchmark_file.unlink()
    from_table = client.get("/api/v1/admin/benchmark")

    assert from_file.status_code == 200
    assert from_file.json() == {"source": "benchmark_real.json", "data": {"seed": 42, "runs": []}}
    assert from_table.status_code == 200
    assert from_table.json()["source"] == "benchmark_result"
    assert from_table.json()["count"] == 1
    assert connection.closed


def test_admin_benchmark_reports_invalid_configured_file(monkeypatch, tmp_path):
    connection = setup(monkeypatch)
    benchmark_file = tmp_path / "invalid-report.json"
    benchmark_file.write_text("{", encoding="utf-8")
    monkeypatch.setenv("BENCHMARK_REPORT_PATH", str(benchmark_file))

    response = client.get("/api/v1/admin/benchmark")

    assert response.status_code == 503
    assert response.json()["detail"] == "benchmark_real.json could not be read"
    assert not connection.fake_cursor.executed


def test_admin_benchmark_run_proxies_validated_ai_result(monkeypatch):
    setup(monkeypatch)
    monkeypatch.setenv("AI_URL", "http://ai-engine.test")
    calls = []

    class Response:
        status_code = 200

        @staticmethod
        def json():
            return {"scenario_id": "demo", "seed": 42, "repeats": 1, "summary": [], "results": []}

    monkeypatch.setattr(admin.httpx, "post", lambda url, **kwargs: calls.append((url, kwargs)) or Response())
    response = client.post(
        "/api/v1/admin/benchmark/run",
        json={"scenario_id": "demo", "algorithms": ["LLF"], "seed": 42, "repeats": 1},
    )

    assert response.status_code == 200
    assert response.json()["scenario_id"] == "demo"
    assert calls[0][0] == "http://ai-engine.test/ai/benchmark"
    assert calls[0][1]["timeout"] == 120.0


def test_admin_benchmark_requires_a_snapshot_or_real_scenario(monkeypatch):
    setup(monkeypatch)

    response = client.post(
        "/api/v1/admin/benchmark/run",
        json={"scenario_id": "inline", "algorithms": ["LLF"]},
    )

    assert response.status_code == 422


def test_admin_forecast_reads_schema_backed_fields(monkeypatch):
    setup(monkeypatch)

    response = client.get("/api/v1/admin/forecast?cluster_id=7&limit=24")

    assert response.status_code == 200
    assert response.json()["count"] == 1
    assert response.json()["forecasts"][0]["algorithm"] == "HOURLY_MEAN"
