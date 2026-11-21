"""Regression tests for contiguous, single-port charging."""

import pytest

from ai_engine.baselines import solve_asap, solve_llf
from ai_engine.normalizer import Solution, normalize
from ai_engine.optimizer_milp import solve_lp, solve_milp
from ai_engine.schemas import Algorithm, OptimizeRequest, SolverStatus
from ai_engine.tests.test_acceptance import snapshot
from ai_engine.validator import validate_solution


def charging_case(control="CONTINUOUS", minimum=1.4):
    data = snapshot()
    data.update(horizon_slots=3, grid_limit_kw=2)
    data["stations"] = data["stations"][:1]
    for port in data["stations"][0]["ports"]:
        port.update(control_type=control, min_power_kw=minimum, max_power_kw=2)
    data["requests"] = data["requests"][:1]
    data["requests"][0].update(arrival_time=data["snapshot_time"],
        departure_time="2026-11-18T17:45:00+07:00", status="PENDING",
        energy_needed_kwh=1.0, energy_delivered_kwh=0)
    data["tariffs"] = [
        {"start_time": start, "end_time": end, "price_vnd_kwh": price}
        for start, end, price in [
            ("17:00", "17:15", 1000), ("17:15", "17:30", 4000), ("17:30", "17:45", 1000)
        ]
    ]
    return data


def problem(data):
    return normalize(OptimizeRequest.model_validate(data))


@pytest.mark.parametrize("control,minimum", [("CONTINUOUS", 1.4), ("ON_OFF_SWITCH", 2)])
def test_milp_cannot_skip_expensive_slot_or_switch_ports(control, minimum):
    p = problem(charging_case(control, minimum))
    sol = solve_milp(p)
    assert sol.algorithm == Algorithm.MILP_MPC
    assert sol.shortfall["A"] == pytest.approx(0)
    assert sorted(t for _, _, t in sol.power) in ([0, 1], [1, 2])
    assert len({pid for _, pid, _ in sol.power}) == 1
    assert all(minimum <= kw <= 2 for kw in sol.power.values())
    report = validate_solution(p, sol)
    assert report.ok and report.interruptions == 0


def test_lp_dispatch_keeps_continuity_when_continuous_minimum_is_zero():
    data = charging_case(minimum=0)
    data["stations"][0]["ports"] = data["stations"][0]["ports"][:1]
    p = problem(data)
    sol = solve_lp(p)
    assert sol.algorithm == Algorithm.MILP_MPC
    assert sol.shortfall["A"] == pytest.approx(0)
    slots = sorted(t for _, _, t in sol.power)
    assert slots == list(range(slots[0], slots[-1] + 1))
    assert validate_solution(p, sol).ok


def with_confirmed_history(data, timestamp=None):
    row = data["requests"][0]
    row.update(status="CHARGING", locked_port_id=102, arrival_time="2026-11-18T16:45:00+07:00")
    data["previous_schedule"] = [
        {"request_id": "A", "port_id": 102, "slot_start": row["arrival_time"], "power_kw": 2}
    ]
    if timestamp is not None:
        data["snapshot_time"] = timestamp
    return problem(data)


@pytest.mark.parametrize("solver", [solve_milp, solve_llf, solve_asap])
@pytest.mark.parametrize("snapshot_time,first", [(None, 0), ("2026-11-18T17:01:00+07:00", 1)])
def test_known_mpc_session_resumes_on_locked_port_at_first_eligible_slot(solver, snapshot_time, first):
    p = with_confirmed_history(charging_case(), snapshot_time)
    assert p.first_mutable_slot == first
    sol = solver(p)
    assert sorted(sol.power) == [("A", "102", first), ("A", "102", first + 1)]
    assert sol.shortfall["A"] == pytest.approx(0)
    report = validate_solution(p, sol)
    assert report.ok and report.interruptions == 0


def test_mpc_without_previous_power_does_not_claim_continuation():
    data = charging_case()
    data["requests"][0].update(status="CHARGING", locked_port_id=102)
    p = problem(data)
    assert p.first_mutable_slot == 1
    assert not p.prior_on_slot


def test_validator_counts_gaps_and_resumption_after_known_mpc_slot():
    p = problem(charging_case())
    gap = Solution({"A": "101"}, {("A", "101", 0): 2, ("A", "101", 2): 2},
                   SolverStatus.FEASIBLE, Algorithm.MILP_MPC, {"A": 0})
    report = validate_solution(p, gap)
    assert not report.ok and report.interruptions == 1
    assert [v.code for v in report.violations] == ["CHARGING_INTERRUPTED"]

    p = with_confirmed_history(charging_case())
    late = Solution({"A": "102"}, {("A", "102", 1): 2, ("A", "102", 2): 2},
                    SolverStatus.FEASIBLE, Algorithm.MILP_MPC, {"A": 0})
    assert validate_solution(p, late).interruptions == 1


def test_llf_gives_running_vehicle_priority_over_tighter_new_request():
    data = charging_case()
    first = data["requests"][0]
    first["energy_needed_kwh"] = 1.5
    data["requests"].append(dict(first, request_id="B", energy_needed_kwh=0.5,
        arrival_time="2026-11-18T17:15:00+07:00", departure_time="2026-11-18T17:30:00+07:00"))
    p = problem(data)
    sol = solve_llf(p)
    assert sorted(t for _, _, t in sol.power) == [0, 1, 2]
    assert {rid for rid, _, _ in sol.power} == {"A"}
    assert len({pid for _, pid, _ in sol.power}) == 1
    assert sol.shortfall == {"A": 0, "B": 0.5}
    report = validate_solution(p, sol)
    assert report.ok and report.interruptions == 0


def test_llf_reserves_minimum_power_for_each_running_vehicle():
    data = charging_case()
    data["grid_limit_kw"] = 3
    first = data["requests"][0]
    first.update(status="CHARGING", locked_port_id=101, arrival_time="2026-11-18T16:45:00+07:00")
    data["requests"].append(dict(first, request_id="B", locked_port_id=102))
    data["previous_schedule"] = [
        {"request_id": rid, "port_id": pid, "slot_start": first["arrival_time"], "power_kw": 1.5}
        for rid, pid in [("A", 101), ("B", 102)]
    ]
    p = problem(data)
    sol = solve_llf(p)
    assert sol.power["A", "101", 0] == pytest.approx(1.6)
    assert sol.power["B", "102", 0] == pytest.approx(1.4)
    assert validate_solution(p, sol).ok


@pytest.mark.parametrize("solver", [solve_milp, solve_llf])
def test_inadequate_remaining_energy_for_minimum_power_leaves_shortfall(solver):
    data = charging_case()
    data["requests"][0]["energy_needed_kwh"] = 0.1
    p = with_confirmed_history(data)
    sol = solver(p)
    assert sol.status in {SolverStatus.OPTIMAL, SolverStatus.FEASIBLE}
    assert not sol.power
    assert sol.shortfall == {"A": 0.1}
    assert validate_solution(p, sol).ok
