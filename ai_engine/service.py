"""Thực thi một snapshot trong tiến trình có thể dừng khi hết hạn HTTP."""

import importlib
import json
import logging
import sys
from time import perf_counter
from typing import Callable

from .baselines import SOLVERS, compute_kpi
from .explainer import build_all_results
from .normalizer import NormProblem, Solution, normalize, to_response_slots
from .optimizer_milp import solve, solve_lp, solve_milp
from .schemas import Algorithm, FallbackReason, KPI, OptimizeRequest, OptimizeResponse, SolverStatus
from .validator import safe_solve, validate_solution

Solver = Callable[[NormProblem], Solution]
ENGINES: dict[str, Solver] = dict(SOLVERS, MILP=solve_milp, MILP_MPC=solve_milp, LP_MPC=solve_lp)


def failure(ms: float, reason: FallbackReason = FallbackReason.SOLVER_ERROR) -> OptimizeResponse:
    """Trả trạng thái lỗi, không công bố kết quả hoặc lịch chưa kiểm tra."""
    return OptimizeResponse(status="ERROR",algorithm=None,solve_ms=ms,fallback_reason=reason,
        kpi=KPI(total_shortfall_kwh=0,total_cost_vnd=0,peak_power_kw=0,on_time_rate=0,
                cap_violations=0,fairness=None),request_results=[],schedules=[])


def evaluate(req: OptimizeRequest, solver: Solver = solve, asap: bool = False) -> OptimizeResponse:
    """Chuẩn hóa, giải, kiểm tra và chuyển nghiệm về JSON."""
    start=perf_counter()
    p=normalize(req)
    if asap:
        sol=solver(p)
        violations=validate_solution(p,sol).violations
        if any(v.code not in {"STATION_CAP","GRID_CAP"} for v in violations):
            return failure((perf_counter()-start)*1000)
    else:
        sol,status,report=safe_solve(p,solver)
        if not report.ok or status==SolverStatus.ERROR or not validate_solution(p,sol).ok:
            return failure((perf_counter()-start)*1000,sol.fallback_reason)
    ms=(perf_counter()-start)*1000
    return OptimizeResponse(status=sol.status,algorithm=sol.algorithm,solve_ms=ms,
        fallback_reason=sol.fallback_reason,
        kpi=compute_kpi(p,sol),request_results=build_all_results(p,sol),
        schedules=to_response_slots(p,((*key,kw) for key,kw in sol.power.items())))


if __name__ == "__main__":
    from .console import configure_console

    configure_console()
    start=perf_counter()
    try:
        body=json.load(sys.stdin.buffer)
        req=OptimizeRequest.model_validate(body["snapshot"])
        module, name = sys.argv[1].split(":")
        solver=getattr(importlib.import_module(module),name)
        response=evaluate(req,solver)
    except Exception:
        logging.exception("Lỗi tác vụ optimize")
        response=failure((perf_counter()-start)*1000)
    sys.stdout.buffer.write(response.model_dump_json().encode("utf8"))
