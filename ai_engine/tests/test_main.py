"""Kiểm thử HTTP bằng TestClient và một worker lỗi có thể tái hiện."""

import json
from pathlib import Path
from time import sleep

from fastapi.testclient import TestClient
from ai_engine import main
from ai_engine.normalizer import NormProblem, Solution

client=TestClient(main.app)


def fail_solver(problem: NormProblem) -> Solution:
    """Giả lập lỗi solver trong tiến trình con."""
    raise RuntimeError("Lỗi chủ động")


def slow_solver(problem: NormProblem) -> Solution:
    """Giả lập solver bỏ qua deadline."""
    sleep(10)
    return fail_solver(problem)


def snapshot() -> dict:
    """Đọc đúng dữ liệu tích hợp của backend."""
    data=json.loads((Path(__file__).resolve().parents[1]/"samples/input_snapshot.json").read_bytes())
    data["time_budget_ms"]=5000
    return data


def test_optimize_and_health() -> None:
    """Kiểm tra đường HTTP chính và phiên bản."""
    health = client.get("/health").json()
    assert "LLF" in health["algorithms"]
    assert health["default_time_budget_ms"] == 10000
    assert health["large_scenario_time_budget_ms"] == 2000
    assert health["small_scenario_request_limit"] == 300
    assert health["decompose_threshold"] == 250
    resp=client.post("/ai/optimize",json=snapshot())
    assert resp.status_code==200 and resp.json()["schedules"]
    assert resp.json()["kpi"]["cap_violations"]==0 and resp.headers["x-request-id"]


def test_schema_error() -> None:
    """Sai schema phải trả 422."""
    assert client.post("/ai/optimize",json={"cluster_id":"C"}).status_code==422


def test_solver_error(monkeypatch) -> None:
    """Worker lỗi phải trả lịch LLF có thể sử dụng."""
    monkeypatch.setattr(main,"SOLVER_ENTRY",__name__+":fail_solver")
    body=client.post("/ai/optimize",json=snapshot()).json()
    assert (body["status"],body["algorithm"])==("FALLBACK","LLF")
    assert body["schedules"]


def test_deadline(monkeypatch) -> None:
    """Solver bị treo phải bị chấm dứt và trả HTTP 200."""
    monkeypatch.setattr(main,"SOLVER_ENTRY",__name__+":slow_solver")
    data=snapshot()
    data["time_budget_ms"]=20
    response=client.post("/ai/optimize",json=data)
    assert response.status_code==200 and response.json()["status"]=="ERROR"


def test_benchmark() -> None:
    """Kịch bản file và inline đều trả bảng KPI."""
    for args in ({"scenario_id":"demo"},{"snapshot":snapshot()}):
        body=client.post("/ai/benchmark",json=dict(**args,algorithms=["LLF","ASAP","NSGA_II"],repeats=2)).json()
        assert len(body["results"])==4 and body["summary"][2]["status"]=="NOT_IMPLEMENTED"
        assert body["summary"][0]["kpi"]["cap_violations"]==0
        assert body["summary"][0]["solve_ms_std"]>=0


def test_forecast() -> None:
    """Một giờ lịch sử vẫn trả đủ 24 điểm với cảnh báo."""
    payload={"cluster_id":snapshot()["cluster_id"],"model":"XGBOOST",
             "history":[{"hour_start":"2026-11-18T08:00:00+07:00","arrivals":3}]}
    data=client.post("/ai/forecast",json=payload).json()
    assert data["model"]=="HOURLY_MEAN" and data["warnings"] and data["metrics"] is None
    assert len(data["predictions"])==24 and data["predictions"][0]["pred_arrivals"]==3
