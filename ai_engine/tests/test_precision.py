from random import Random

import pytest

from ai_engine.baselines import compute_kpi, solve_llf
from ai_engine.normalizer import normalize
from ai_engine.optimizer_milp import solve
from ai_engine.schemas import OptimizeRequest
from ai_engine.scripts.acceptance_check import instance
from ai_engine.tests.test_acceptance import snapshot
from ai_engine.validator import validate_solution


@pytest.mark.parametrize(("gap", "rate"), [(2e-8, 1.0), (1e-3, 0.5)])
def test_reported_shortfall(gap, rate):
    data = snapshot()
    data["requests"] = data["requests"][:2]
    problem = normalize(OptimizeRequest.model_validate(data))
    sol = solve_llf(problem)
    key = next(k for k in sol.power if k[0] == "A")
    sol.power[key] -= (gap + 1e-8) / problem.dt
    sol.shortfall["A"] = gap
    assert validate_solution(problem, sol).ok
    kpi = compute_kpi(problem, sol)
    assert kpi.on_time_rate == rate
    assert kpi.total_shortfall_kwh == (0 if rate == 1 else gap)


def test_page20_exact_kpi():
    p = normalize(OptimizeRequest.model_validate(snapshot()))
    sol = solve(p)
    kpi = compute_kpi(p, sol)
    assert kpi.on_time_rate == 1.0
    assert kpi.total_cost_vnd == 5500
    assert kpi.total_shortfall_kwh == 0
    assert all(v == 0 for v in sol.shortfall.values())


def test_page20_uses_primary_solver():
    problem = normalize(OptimizeRequest.model_validate(snapshot()))
    solution = solve(problem)
    assert solution.algorithm != "LLF"
    assert solution.status != "FALLBACK"


def test_random_shortfalls_are_snapped():
    from ai_engine.settings import EPS_KWH

    rng = Random(16520)
    for i in range(200):
        data = instance(rng, i)
        for row in data["requests"]:
            row["energy_needed_kwh"] += rng.uniform(0, 5e-8)
        p = normalize(OptimizeRequest.model_validate(data))
        sol = solve(p)
        assert validate_solution(p, sol).ok, i
        assert all(v == 0 or v >= EPS_KWH for v in sol.shortfall.values()), i
