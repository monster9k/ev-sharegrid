"""Kiểm tra độc lập giới hạn vật lý, thứ tự ưu tiên và tải ngẫu nhiên."""

from collections import defaultdict
from dataclasses import replace
from datetime import timedelta
import json
from pathlib import Path
from random import Random
from time import perf_counter
from typing import Any

import pytest

from ai_engine.baselines import SOLVERS, compute_kpi, solve_equal_share, solve_llf
from ai_engine.normalizer import NormProblem, Solution, normalize
from ai_engine.schemas import OptimizeRequest


def sample() -> NormProblem:
    """Chuẩn hóa snapshot tích hợp của Backend."""
    path = Path(__file__).resolve().parents[1] / "samples/input_snapshot.json"
    return normalize(OptimizeRequest.model_validate_json(path.read_bytes()))


def verify(p: NormProblem, sol: Solution) -> None:
    """Tái tính tải và năng lượng từ các dòng nghiệm, độc lập với solver."""
    grid: dict[int, float] = defaultdict(float)
    station: dict[tuple[str, int], float] = defaultdict(float)
    energy: dict[str, float] = defaultdict(float)
    occupied = set()
    for (rid, pid, t), kw in sol.power.items():
        r, port = p.requests[rid], p.ports[pid]
        assert pid == sol.assign[rid] and pid in r.candidate_ports
        assert port.status == "ACTIVE" and port.connector_type == r.connector_type
        assert r.station_id == port.station_id
        assert not r.locked_port_id or pid == r.locked_port_id
        assert t >= p.first_mutable_slot and t in r.active_slots
        assert (pid, t) not in occupied
        occupied.add((pid, t))
        assert 0 < kw <= min(port.max_power_kw, r.vehicle_max_kw) + 1e-9
        assert kw >= port.min_power_kw
        if port.control_type == "ON_OFF_SWITCH":
            assert kw == port.max_power_kw
        energy[rid] += kw*p.dt
        grid[t] += kw
        station[r.station_id, t] += kw
    assert all(kwh <= p.requests[rid].remaining_kwh + 1e-9 for rid, kwh in energy.items())
    violations = sum(v > p.grid_limit_kw + 1e-9 for v in grid.values())
    violations += sum(v > p.stations[s].station_power_kw + 1e-9 for (s, _), v in station.items())
    assert compute_kpi(p, sol).cap_violations == violations
    if sol.algorithm != "ASAP":
        assert violations == 0


@pytest.mark.parametrize("name", SOLVERS)
def test_caps_and_locked(name: str) -> None:
    """Siết đồng thời trần trạm và cụm trên mẫu có cổng khóa."""
    p = sample()
    p = replace(p, grid_limit_kw=12, stations={k: replace(v, station_power_kw=9) for k,v in p.stations.items()})
    sol = SOLVERS[name](p)
    verify(p, sol)
    assert sol.assign["R-01"] == "P-01"
    assert (compute_kpi(p, sol).cap_violations > 0) == (name == "ASAP")


@pytest.mark.parametrize("name", SOLVERS)
def test_switch_quantum(name: str) -> None:
    """Xe còn thiếu ít hơn một lần bật cổng phải chờ."""
    p = sample()
    r = replace(p.requests["R-02"], remaining_kwh=1.74)
    p = replace(p, requests={r.request_id:r})
    assert not SOLVERS[name](p).power


def test_overnight() -> None:
    """Cấp điện ở slot sau nửa đêm theo biểu giá ngày mới."""
    path = Path(__file__).resolve().parents[1] / "samples/input_snapshot.json"
    data: dict[str, Any] = json.loads(path.read_bytes())
    data["snapshot_time"] = "2026-11-18T23:45:00+07:00"
    data["requests"] = data["requests"][:1]
    data["requests"][0]["departure_time"] = data["stations"][0]["close_time"] = "2026-11-19T01:00:00+07:00"
    data["tariffs"] = [dict(start_time="00:00", end_time="24:00", price_vnd_kwh=2000)]
    p = normalize(OptimizeRequest.model_validate(data))
    for solver in SOLVERS.values():
        sol = solver(p)
        verify(p, sol)
        assert sol.power == {("R-01","P-01",1):20}
        assert compute_kpi(p, sol).total_cost_vnd == 10000


def test_equal_and_kpi() -> None:
    """Hai xe khác trạm cùng chia 16 kW ở slot đầu tiên có thể đổi."""
    p = sample()
    p = replace(p, T=2, grid_limit_kw=16, requests={k:r for k,r in p.requests.items() if k != "R-02"})
    sol = solve_equal_share(p)
    verify(p, sol)
    assert list(sol.power.values()) == [8, 8]
    k = compute_kpi(p, sol)
    assert k.total_shortfall_kwh == 3.75 and k.on_time_rate == 0 and k.peak_power_kw == 16
    a, b = 2/5, 2/2.75
    assert k.fairness == pytest.approx((a+b)**2 / (2*(a*a+b*b)))


def test_future_lock() -> None:
    """Xe đến trước không chiếm cổng mà xe đã khóa sắp cần."""
    p = sample()
    r = p.requests["R-01"]
    waiting = replace(r, request_id="A", locked_port_id=None)
    locked = replace(r, active_slots=range(2,4), arrival_slot=2)
    p = replace(p, requests={"A": waiting, "R-01": locked})
    for solver in SOLVERS.values():
        sol = solver(p)
        verify(p, sol)
        assert set(sol.assign) == {"R-01"}


def workload(n: int) -> NormProblem:
    """Sinh tải có seed cố định, 24 cổng liên tục, 32 slot."""
    rng = Random(923)
    p = sample()
    base = p.requests["R-01"]
    ports = {str(i):replace(p.ports["P-01"], port_id=str(i)) for i in range(24)}
    ids = tuple(ports)
    requests = {}
    for i in range(n):
        a = rng.randrange(16)
        d = rng.randint(a+2,32)
        r = replace(base, request_id=str(i), locked_port_id=None, candidate_ports=ids,
                    arrival_time=p.t0_time + timedelta(minutes=15*a),
                    departure_time=p.t0_time + timedelta(minutes=15*d), arrival_slot=a,
                    departure_slot=d, active_slots=range(a,d), remaining_kwh=rng.uniform(2,40))
        requests[r.request_id] = r
    station = replace(p.stations["ST-01"], open_slots=range(32), port_ids=ids, station_power_kw=350)
    return replace(p,T=32,price=(2000,)*32,grid_limit_kw=300,ports=ports,
                   stations={"ST-01":station}, requests=requests,time_budget_ms=2000)


@pytest.mark.parametrize("name", SOLVERS)
def test_seeded_load(name: str) -> None:
    """Chạy một nghìn xe, kiểm giới hạn thời gian và mọi dòng lịch."""
    p = workload(1000)
    start = perf_counter()
    sol = SOLVERS[name](p)
    assert perf_counter()-start < 2 and sol.status == "FEASIBLE" and sol.power
    verify(p,sol)


def test_priority_orders() -> None:
    """Ba chính sách chọn ba xe khác nhau khi tranh cùng một cổng."""
    p = sample()
    r = replace(p.requests["R-01"], locked_port_id=None)
    a = replace(r, request_id="A", remaining_kwh=1.5)
    b = replace(r, request_id="B", arrival_time=r.arrival_time+timedelta(minutes=1),
                departure_time=r.departure_time-timedelta(minutes=15), remaining_kwh=2)
    c = replace(r, request_id="C", arrival_time=b.arrival_time, remaining_kwh=30)
    p = replace(p,requests={x.request_id:x for x in (c,b,a)})
    for name, winner in [("FCFS","A"), ("EDF","B"), ("LLF","C")]:
        assert set(SOLVERS[name](p).assign) == {winner}


def test_timeout_partial() -> None:
    """Nghiệm hết ngân sách vẫn hợp lệ và có trạng thái fallback."""
    p = replace(workload(10000), time_budget_ms=1)
    sol = solve_llf(p)
    assert sol.status == "FALLBACK"
    verify(p,sol)
