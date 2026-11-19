"""Regression checks for the lexicographic MILP time budget."""

import json
from pathlib import Path

from ai_engine import optimizer_milp
from ai_engine.baselines import compute_kpi, solve_llf
from ai_engine.normalizer import normalize
from ai_engine.schemas import OptimizeRequest
from ai_engine.settings import EPS_KW, EPS_KWH
from ai_engine.validator import validate_solution


def _page20():
    path = Path(__file__).resolve().parents[1] / "samples" / "page20_input.json"
    return normalize(OptimizeRequest.model_validate(json.loads(path.read_text(encoding="utf-8"))))


def test_feasible_shortfall_tie_still_optimizes_cost_and_peak(monkeypatch):
    problem = _page20()
    seed = compute_kpi(problem, solve_llf(problem))
    assert seed.total_shortfall_kwh <= EPS_KWH
    solve_stage = optimizer_milp._solve_stage
    stages = []

    def first_stage_without_proof(model, budget, lp):
        result = solve_stage(model, budget, lp)
        stages.append(result)
        if len(stages) == 1:
            assert result == model.OPTIMAL
            return model.FEASIBLE
        return result

    monkeypatch.setattr(optimizer_milp, "_solve_stage", first_stage_without_proof)
    result = optimizer_milp.solve_milp(problem)
    kpi = compute_kpi(problem, result)
    assert len(stages) == 4
    assert result.algorithm == "MILP_MPC"
    assert result.status == "FEASIBLE"
    assert result.fallback_reason == "NONE"
    assert validate_solution(problem, result).ok
    assert kpi.total_shortfall_kwh <= seed.total_shortfall_kwh + EPS_KWH
    assert kpi.total_cost_vnd <= seed.total_cost_vnd + EPS_KWH
    assert kpi.peak_power_kw <= seed.peak_power_kw + EPS_KW


def test_budget_exhausted_after_first_stage_keeps_milp_incumbent(monkeypatch):
    problem = _page20()
    solve_stage, clock = optimizer_milp._solve_stage, optimizer_milp.perf_counter
    stages = []

    def finish_first_stage(model, budget, lp):
        result = solve_stage(model, budget, lp)
        assert result == model.OPTIMAL
        stages.append(result)
        return result

    monkeypatch.setattr(optimizer_milp, "_solve_stage", finish_first_stage)
    monkeypatch.setattr(optimizer_milp, "perf_counter", lambda: clock() + (60 if stages else 0))
    result = optimizer_milp.solve_milp(problem)
    assert len(stages) == 1
    assert result.algorithm == "MILP_MPC"
    assert result.status == "FEASIBLE"
    assert result.fallback_reason == "NONE"
    assert validate_solution(problem, result).ok
    seed = solve_llf(problem)
    assert sum(result.shortfall.values()) <= sum(seed.shortfall.values()) + EPS_KWH
