"""Kiểm tra ngân sách và đường xử lý theo quy mô snapshot."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from ai_engine.normalizer import normalize
from ai_engine.optimizer_milp import solve, solve_lp, solve_milp
from ai_engine.schemas import OptimizeRequest
from ai_engine.settings import DECOMPOSE_THRESHOLD
from ai_engine.validator import validate_solution


PAGE20 = Path(__file__).resolve().parents[1] / "samples/page20_input.json"


def request_snapshot(count: int) -> dict[str, Any]:
    """Tạo snapshot kiểm thử nhỏ, mỗi xe có một cổng đóng/ngắt riêng."""
    data = json.loads(PAGE20.read_text(encoding="utf-8"))
    data.pop("time_budget_ms", None)
    data["grid_limit_kw"] = count
    data["tariffs"] = [{"start_time": "17:00", "end_time": "18:00", "price_vnd_kwh": 2000}]
    data["stations"] = []
    data["requests"] = []

    for index in range(count):
        station_id = f"S-{index:04d}"
        port_id = f"P-{index:04d}"
        data["stations"].append({
            "station_id": station_id,
            "station_power_kw": 1,
            "open_time": "2026-11-18T00:00:00+07:00",
            "close_time": "2026-11-18T23:59:00+07:00",
            "ports": [{
                "port_id": port_id,
                "connector_type": "CCS2",
                "control_type": "ON_OFF_SWITCH",
                "min_power_kw": 1,
                "max_power_kw": 1,
                "status": "ACTIVE",
            }],
        })
        data["requests"].append({
            "request_id": f"R-{index:04d}",
            "station_id": station_id,
            "connector_type": "CCS2",
            "vehicle_max_kw": 1,
            "arrival_time": "2026-11-18T17:00:00+07:00",
            "departure_time": "2026-11-18T17:30:00+07:00",
            "energy_needed_kwh": 0.25,
            "energy_delivered_kwh": 0,
            "priority_weight": 1,
            "status": "PENDING",
            "locked_port_id": None,
        })
    return data


@pytest.mark.parametrize(("count", "expected_ms"), [(299, 10000), (300, 2000)])
def test_default_time_budget_depends_on_request_count(count: int, expected_ms: int) -> None:
    """Chỉ snapshot dưới 300 request nhận mặc định 10 giây."""
    request = OptimizeRequest.model_validate(request_snapshot(count))
    assert request.time_budget_ms == expected_ms


def test_61_requests_finish_without_fallback() -> None:
    """Bài 61 xe phải trả nghiệm solver trong ngân sách mặc định 10 giây."""
    request = OptimizeRequest.model_validate(request_snapshot(61))
    assert request.time_budget_ms == 10000

    problem = normalize(request)
    solution = solve(problem)

    assert solution.status in {"OPTIMAL", "FEASIBLE"}
    assert solution.status != "FALLBACK"
    assert validate_solution(problem, solution).ok


@pytest.mark.parametrize("solver", [solve, solve_lp, solve_milp])
def test_large_problem_uses_llf_and_validator_accepts(solver) -> None:
    """Trên ngưỡng, LLF giữ trần cụm mà không giải MILP nguyên khối."""
    request = OptimizeRequest.model_validate(request_snapshot(DECOMPOSE_THRESHOLD + 1))
    problem = normalize(request)
    solution = solver(problem)

    assert solution.algorithm == "LLF"
    assert solution.status == "FALLBACK"
    assert solution.fallback_reason == "THRESHOLD_EXCEEDED"
    assert validate_solution(problem, solution).ok
