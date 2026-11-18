"""Tiêm từng lỗi vào nghiệm và kiểm tra mã chẩn đoán độc lập."""

from dataclasses import replace
from typing import Any

import pytest

from ai_engine import validator
from ai_engine.baselines import SOLVERS, solve_llf
from ai_engine.normalizer import NormProblem, Solution
from ai_engine.tests.test_baselines import sample
from ai_engine.validator import safe_solve, validate_solution


@pytest.mark.parametrize("code", [
    "PORT_COLLISION", "MULTIPLE_PORTS", "PORT_CHANGED", "STATION_CAP", "GRID_CAP",
    "PARKING_WINDOW", "STATION_CLOSED", "HORIZON", "FROZEN_SLOT", "CONNECTOR",
    "WRONG_STATION", "PORT_INACTIVE", "ON_OFF_POWER", "CONTINUOUS_POWER",
    "VEHICLE_MAX", "OVERALLOCATED", "NEGATIVE_POWER", "NONFINITE_POWER",
    "LOCK_CHANGED", "ENERGY_BALANCE", "ASSIGN_MISMATCH", "UNKNOWN_PORT", "UNKNOWN_REQUEST",
])
def test_detect(code: str) -> None:
    """Kiểm tra lỗi với một biến đổi có chủ đích trên lịch hoặc snapshot."""
    p = sample()
    sol = solve_llf(p)
    assert validate_solution(p, sol).ok
    rid, pid = "R-01", "P-01"
    extra = {
        "PORT_COLLISION": ("R-02", pid, 1, 7), "MULTIPLE_PORTS": (rid, "P-02", 1, 7),
        "PORT_CHANGED": (rid, "P-02", 2, 7), "PARKING_WINDOW": ("R-02", "P-02", 0, 7),
        "HORIZON": (rid, pid, p.T, 10), "FROZEN_SLOT": (rid, pid, 0, 10),
        "CONNECTOR": (rid, "P-02", 2, 7), "WRONG_STATION": (rid, "P-03", 2, 10),
        "PORT_INACTIVE": (rid, "P-04", 2, 3.5), "ON_OFF_POWER": ("R-02", "P-02", 1, 4),
        "CONTINUOUS_POWER": (rid, pid, 1, 4), "VEHICLE_MAX": (rid, pid, 1, 21),
        "OVERALLOCATED": (rid, pid, 2, 5), "NEGATIVE_POWER": (rid, pid, 1, -1),
        "NONFINITE_POWER": (rid, pid, 1, float("nan")), "UNKNOWN_PORT": (rid, "?", 1, 7),
        "UNKNOWN_REQUEST": ("?", pid, 1, 7),
    }
    if code in extra:
        car, port, slot, kw = extra[code]
        sol.power[car, port, slot] = kw
    elif code in ("LOCK_CHANGED", "ASSIGN_MISMATCH"):
        sol.assign[rid] = "P-02"
    elif code == "ENERGY_BALANCE":
        sol.shortfall[rid] = 0.01
    elif code == "GRID_CAP":
        p = replace(p, grid_limit_kw=10)
    else:
        s = p.stations["ST-01"]
        station = replace(s, station_power_kw=1) if code == "STATION_CAP" else replace(s, open_slots=range(2,4))
        p = replace(p, stations={**p.stations, s.station_id:station})
    report = validate_solution(p, sol)
    assert not report.ok and code in {v.code for v in report.violations}


def broken(p: NormProblem) -> Solution:
    """Mô phỏng solver ném ngoại lệ."""
    raise RuntimeError("Thử lỗi solver")


@pytest.mark.parametrize("throws", [False, True])
def test_fallback(throws: bool) -> None:
    """Cả vượt trần và ngoại lệ đều phải chuyển sang LLF hợp lệ."""
    p = replace(sample(), grid_limit_kw=9)
    sol, status, report = safe_solve(p, broken if throws else SOLVERS["ASAP"])
    assert status == sol.status == "FALLBACK" and sol.algorithm == "LLF"
    assert report.ok and validate_solution(p, sol).ok


def test_double_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    """Lỗi cả hai lượt trả lịch rỗng cùng báo cáo chẩn đoán."""
    monkeypatch.setattr(validator, "solve_llf", broken)
    sol, status, report = safe_solve(sample(), broken)
    assert status == "ERROR" and not report.ok and not sol.power
    assert len(report.violations) == 2
