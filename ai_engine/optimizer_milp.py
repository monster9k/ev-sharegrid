"""Bộ giải MPC dùng SCIP cho công suất thực và GLOP cho trường hợp tuyến tính."""

from __future__ import annotations

import logging
import sys
from collections import defaultdict
from contextvars import ContextVar
from dataclasses import replace
from threading import Timer
from time import perf_counter

from .baselines import solve_llf
from .normalizer import NormProblem, Solution
from .schemas import Algorithm, SolverStatus
from .settings import DECOMPOSE_THRESHOLD, EPS_KW, is_leq, is_zero, snap
from .validator import validate_solution


BENCHMARK_SEED: ContextVar[int] = ContextVar("benchmark_seed", default=42)


def _optimize(p: NormProblem, prefer_lp: bool) -> Solution:
    """Tối ưu lần lượt thiếu điện, công bằng theo nhóm, giá và độ ổn định."""
    from ortools.linear_solver import pywraplp

    end = perf_counter()+p.time_budget_ms/1000
    old = p.previous_schedule
    fixed = {k:v for k,v in old.items() if k[2]<p.first_mutable_slot and not is_zero(v, EPS_KW)}
    seed = solve_llf(replace(p,time_budget_ms=p.time_budget_ms//5))
    seed.status = SolverStatus.FALLBACK
    if not validate_solution(p,seed).ok:
        raise ValueError("Lịch khóa không khả thi")
    occupied = set()
    lp = prefer_lp
    if lp:
        for r in p.requests.values():
            if len(r.candidate_ports)>1:
                lp=False
                break
            for pid in r.candidate_ports:
                port = p.ports[pid]
                times = {(pid,t) for t in r.active_slots}
                if not is_zero(port.min_power_kw, EPS_KW) or port.control_type!="CONTINUOUS" or occupied & times:
                    lp=False
                    break
                occupied.update(times)
    m = pywraplp.Solver.CreateSolver("GLOP" if lp else "SCIP")
    if m is None:
        raise RuntimeError("Thiếu backend OR-Tools")
    if not lp:
        m.SetNumThreads(1)
        parameters = f"randomization/randomseedshift = {BENCHMARK_SEED.get() % 2147483647}"
        if sys.platform == "win32":
            # SCIP's Windows wall clock can report a whole second during presolve.
            parameters += "\ntiming/clocktype = 1"
        m.SetSolverSpecificParametersAsString(parameters)
    ps, xs, gaps, floors = {}, {}, {}, {}
    ports, stations, grid = defaultdict(list),defaultdict(list),defaultdict(list)
    peak = m.NumVar(0,p.grid_limit_kw,"")
    costs, penalties, hints = [], [], []
    for rid,r in p.requests.items():
        energy, picks = [], []
        gap = gaps[rid] = m.NumVar(0,r.remaining_kwh,"")
        if r.priority_weight not in floors:
            floors[r.priority_weight] = m.NumVar(0,1,"")
        m.Add(r.remaining_kwh*floors[r.priority_weight]<=r.remaining_kwh-gap)
        for pid in r.candidate_ports:
            port = p.ports[pid]
            if not lp:
                y = m.BoolVar("")
                picks.append(y)
                if r.locked_port_id==pid:
                    m.Add(y==1)
                hints.append((y,int(seed.assign.get(rid)==pid)))
            for t in r.active_slots:
                if perf_counter()>=end:
                    return seed
                k=rid,pid,t
                if t<p.first_mutable_slot and k not in fixed:
                    continue
                hi=min(r.vehicle_max_kw,port.max_power_kw)
                v=ps[k]=m.NumVar(0,hi,"")
                # m.Add overloads these operators to create exact symbolic MILP constraints.
                # EPS_KW is for checks on concrete floating-point solver results, never to relax caps.
                if k in fixed:
                    m.Add(v==fixed[k])
                if not lp:
                    x=xs[k]=m.BoolVar("")
                    m.Add(x<=y)
                    ports[pid,t].append(x)
                    m.Add(v<=hi*x)
                    m.Add(v>=port.min_power_kw*x)
                    if port.control_type=="ON_OFF_SWITCH":
                        m.Add(v==port.max_power_kw*x)
                    hints.extend([(x,int(k in seed.power)),(v,seed.power.get(k,0))])
                grid[t].append(v)
                stations[r.station_id,t].append(v)
                energy.append(v*p.dt)
                costs.append(v*(p.dt*p.price[t]))
                if old and t>=p.first_mutable_slot:
                    d=m.NumVar(0,m.infinity(),"")
                    m.Add(d>=v-old.get(k,0))
                    m.Add(d>=old.get(k,0)-v)
                    penalties.append(d)
        if picks:
            m.Add(m.Sum(picks)<=1)
        m.Add(m.Sum(energy)+gap==r.remaining_kwh)
    switches={}
    for (pid,t),vs in ports.items():
        total=m.Sum(vs)
        m.Add(total<=1)
        if p.ports[pid].control_type=="ON_OFF_SWITCH":
            switches[pid,t]=total
    for pid,t in sorted(switches.keys()|{(pid,t+1) for pid,t in switches if t+1<p.T}):
        delta=switches.get((pid,t),0)-switches.get((pid,t-1),0)
        d=m.NumVar(0,1,"")
        m.Add(d>=delta)
        m.Add(d>=-delta)
        penalties.append(d)
    for (sid,t),vs in stations.items():
        m.Add(m.Sum(vs)<=p.stations[sid].station_power_kw)
    for vs in grid.values():
        m.Add(m.Sum(vs)<=peak)
    if hints:
        m.SetHint(*zip(*hints))
    objectives=[m.Sum([p.requests[r].priority_weight*g for r,g in gaps.items()]),
                *[-floors[w] for w in sorted(floors,reverse=True)],m.Sum(costs),peak+m.Sum(penalties)]
    # Bound cumulative rounding error for a whole slot and for a long session.
    rounding_error = EPS_KW / max(1, len(p.requests), p.T * p.dt)
    best=seed
    for i,obj in enumerate(objectives):
        ms=int((end-perf_counter())*1000)
        if ms<=0:
            return best
        m.Minimize(obj)
        stage_ms = max(1, ms // (len(objectives) - i))
        m.SetTimeLimit(stage_ms)
        if not lp and sys.platform == "win32":
            # Enforce the same wall-time budget even when CPU time advances slowly.
            timeout = Timer(stage_ms / 1000, m.InterruptSolve)
            timeout.start()
            try:
                status = m.Solve()
            finally:
                timeout.cancel()
                timeout.join()
        else:
            status = m.Solve()
        if status not in (m.OPTIMAL,m.FEASIBLE):
            return best
        sol=Solution({}, {},SolverStatus.FEASIBLE,Algorithm.LP_MPC if lp else Algorithm.MILP_MPC,
                     {rid:snap(max(0,g.solution_value())) for rid,g in gaps.items()})
        for rid,r in p.requests.items():
            if r.locked_port_id in r.candidate_ports:
                sol.assign[rid]=r.locked_port_id
        for k,v in ps.items():
            rid, pid, _ = k
            port = p.ports[pid]
            kw = snap(v.solution_value(), EPS_KW)
            if port.control_type == "ON_OFF_SWITCH":
                kw = port.max_power_kw if xs[k].solution_value() > 0.5 else 0.0
            elif k in fixed:
                kw = fixed[k]
            else:
                rounded = round(kw, 6)
                if is_zero(kw - rounded, rounding_error):
                    kw = rounded
            if not is_zero(kw, EPS_KW):
                sol.assign[rid] = pid
                sol.power[k] = kw
        if not validate_solution(p,sol).ok:
            return best
        if status==m.FEASIBLE and i==0:
            improvement = sum(p.requests[r].priority_weight * (seed.shortfall[r] - sol.shortfall[r]) for r in gaps)
            if is_leq(improvement, 0):
                return seed
        best=sol
        if status!=m.OPTIMAL:
            return best
        if i==len(objectives)-1:
            best.status=SolverStatus.OPTIMAL
        else:
            # Slack for lexicographic objective locking (also applies to price and fairness).
            m.Add(obj<=m.Objective().Value()+1e-8)
    return best


def solve_milp(problem: NormProblem, time_budget_ms: int | None = None) -> Solution:
    """Giải MILP bằng SCIP trong ngân sách được cấp."""
    p = problem if time_budget_ms is None else replace(problem,time_budget_ms=time_budget_ms)
    if len(p.requests) > DECOMPOSE_THRESHOLD:
        return _large_problem_llf(p)
    return _optimize(p,False)


def solve_lp(problem: NormProblem, time_budget_ms: int | None = None) -> Solution:
    """Dùng GLOP khi không còn lựa chọn rời rạc, dùng SCIP khi cần."""
    p = problem if time_budget_ms is None else replace(problem,time_budget_ms=time_budget_ms)
    if len(p.requests) > DECOMPOSE_THRESHOLD:
        return _large_problem_llf(p)
    return _optimize(p,True)


def _large_problem_llf(problem: NormProblem) -> Solution:
    """Dùng LLF trên toàn cụm khi MILP vượt ngưỡng.

    Tách theo trạm sẽ làm mất ràng buộc công suất cụm giữa các phần; một lượt LLF
    giữ nguyên trần toàn cục và ổn định hơn cho tải lớn.
    """
    logging.getLogger(__name__).info(
        "Có %d request, vượt DECOMPOSE_THRESHOLD=%d; chuyển sang LLF để giữ trần cụm",
        len(problem.requests), DECOMPOSE_THRESHOLD,
    )
    return replace(solve_llf(problem), status=SolverStatus.FALLBACK, algorithm=Algorithm.LLF)


def solve(problem: NormProblem) -> Solution:
    """Chọn GLOP hoặc SCIP theo cấu trúc bài toán."""
    # Khi cổng khóa hỏng, chỉ lập lại những slot tương lai trên cổng dự phòng.
    changed = {}
    for rid,r in problem.requests.items():
        if r.port_lost and r.replacement_ports and not any(
            k[0]==rid and k[2]<problem.first_mutable_slot and not is_leq(v, 0, EPS_KW)
            for k,v in problem.previous_schedule.items()
        ):
            changed[rid] = replace(r,locked_port_id=None,port_lost=False,
                candidate_ports=r.replacement_ports,
                feasible_max_kw=min(r.vehicle_max_kw,max(problem.ports[j].max_power_kw for j in r.replacement_ports)))
    p = replace(problem,requests=problem.requests | changed) if changed else problem
    start = perf_counter()
    try:
        if len(p.requests) > DECOMPOSE_THRESHOLD:
            return _large_problem_llf(p)
        if p.time_budget_ms <= 1:
            raise TimeoutError("Ngân sách quá nhỏ để khởi tạo solver")
        return solve_lp(p)
    except Exception as exc:
        logging.getLogger(__name__).info("Dùng LLF: %s",exc)
        left = max(0,int(p.time_budget_ms-1000*(perf_counter()-start)))
        return replace(solve_llf(replace(p,time_budget_ms=left)),status=SolverStatus.FALLBACK)
