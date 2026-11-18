"""Năm chính sách lập lịch theo slot và các chỉ số so sánh nghiệm."""

from __future__ import annotations

from bisect import bisect_left
from dataclasses import replace
from collections import Counter, defaultdict
from math import fsum, inf
from time import perf_counter
from typing import Callable

from .normalizer import NormProblem, NormRequest, Solution
from .settings import EPS_KW, is_leq, snap
from .schemas import Algorithm, ControlType, KPI, SolverStatus


def _fill(bounds: list[tuple[float, float]], budget: float) -> list[float]:
    """Nâng mực công suất chung giữa các mức sàn và trần đã nhận."""
    maxima = [hi for _, hi in bounds]
    if is_leq(sum(maxima), budget, EPS_KW):
        return maxima
    # Tại mỗi điểm gãy, số xe còn có thể tăng công suất thay đổi.
    events = sorted((level, change) for lo, hi in bounds
                    for level, change in ((lo, 1), (hi, -1)))
    left = max(0.0, budget - sum(lo for lo, _ in bounds))
    level = 0.0
    slope = 0
    for point, change in events:
        step = (point - level) * slope
        if slope and is_leq(left, step, EPS_KW):
            level += min(left, step) / slope
            break
        left -= step
        level = point
        slope += change
    return [min(hi, max(lo, level)) for lo, hi in bounds]


def _solve(p: NormProblem, algorithm: Algorithm) -> Solution:
    """Giữ cổng đến hết khoảng đỗ, phân bổ điện theo chính sách đã chọn."""
    end = perf_counter() + p.time_budget_ms / 1000
    sol = Solution({}, {}, SolverStatus.FEASIBLE, algorithm)

    def check() -> None:
        """Dừng tại điểm an toàn và giữ mọi dòng lịch đã ghi."""
        if perf_counter() >= end:
            raise TimeoutError

    remaining: dict[str, float] = {}
    try:
        equal = algorithm == Algorithm.EQUAL_SHARE
        asap = algorithm == Algorithm.ASAP
        groups: dict[int, tuple[str, ...]] = {}
        counts: Counter[int] = Counter()
        locks: dict[str, list[tuple[int, int, str]]] = defaultdict(list)
        available: list[NormRequest] = []
        deadlines: dict[str, float] = {}
        for r in p.requests.values():
            check()
            if not r.active_slots or not r.candidate_ports or r.port_lost:
                continue
            begin = max(p.first_mutable_slot, r.active_slots.start)
            if begin >= r.active_slots.stop:
                continue
            available.append(r)
            remaining[r.request_id] = r.remaining_kwh
            deadlines[r.request_id] = (r.departure_time - p.t0_time).total_seconds() / 3600
            group = id(r.candidate_ports)
            groups[group] = r.candidate_ports
            counts[group] += 1
            if r.locked_port_id:
                locks[r.locked_port_id].append((begin, r.departure_slot, r.request_id))

        # Chặn cả các khóa tương lai trước khi chọn cổng cho xe mới.
        lock_starts: dict[str, list[int]] = defaultdict(list)
        lock_ends: dict[str, list[int]] = defaultdict(list)
        blocked: set[str] = set()
        for port, intervals in locks.items():
            last = -1
            for begin, stop, rid in sorted(intervals):
                check()
                if begin < last:
                    blocked.add(rid)
                    # Hai khóa vật lý xung đột: giữ vùng tranh chấp cho xe đã khóa.
                else:
                    sol.assign[rid] = port
                last = max(last, stop)
                lock_starts[port].append(begin)
                lock_ends[port].append(last)

        demand: Counter[str] = Counter()
        for group, ids in groups.items():
            for port in ids:
                check()
                demand[port] += counts[group]
        ranked = {g: sorted(ids, key=lambda port: (demand[port], port)) for g, ids in groups.items()}
        busy_until: dict[str, int] = {}
        if algorithm == Algorithm.FCFS:
            available.sort(key=lambda r: (r.arrival_time, r.request_id))
        elif algorithm == Algorithm.EDF:
            available.sort(key=lambda r: (r.departure_time, r.request_id))
        else:
            available.sort(key=lambda r: r.request_id)

        def record(r: NormRequest, port: str, t: int, kw: float) -> None:
            """Ghi một lần cấp điện và khóa cổng đến lúc xe rời đi."""
            rid = r.request_id
            sol.assign[rid] = port
            busy_until[port] = r.departure_slot
            sol.power[rid, port, t] = kw
            remaining[rid] = max(0.0, remaining[rid] - kw * p.dt)

        for t in range(p.first_mutable_slot, p.T):
            check()
            active = []
            for r in available:
                check()
                if t in r.active_slots and r.request_id not in blocked and not is_leq(remaining[r.request_id], 0):
                    active.append(r)
            if algorithm == Algorithm.LLF:
                # Trừ t*dt giống nhau cho mọi xe nên thứ tự slack được bảo toàn.
                active.sort(key=lambda r: (deadlines[r.request_id] -
                            remaining[r.request_id] / r.feasible_max_kw, r.request_id))
            grid = inf if asap else p.grid_limit_kw
            station_left: dict[str, float] = {}
            pending: dict[str, list[tuple[NormRequest, str, float, float]]] = defaultdict(list)
            taken: set[str] = set()
            # Các xe cùng nhóm chia sẻ danh sách cổng còn rảnh tại slot này.
            free: dict[int, dict[str, None]] = {}
            for r in active:
                check()
                sid, rid = r.station_id, r.request_id
                local = station_left.get(sid, inf if asap else p.stations[sid].station_power_kw)
                cap = min(local, grid, remaining[rid] / p.dt, r.vehicle_max_kw)
                if is_leq(cap, 0, EPS_KW):
                    continue
                fixed = sol.assign.get(rid)
                group = id(r.candidate_ports)
                if fixed:
                    options = (fixed,)
                else:
                    if group not in free:
                        free[group] = {port: None for port in ranked[group]
                                       if busy_until.get(port, 0) <= t and port not in taken}
                    options = free[group]
                for port in options:
                    check()
                    if port in taken:
                        continue
                    if not fixed:
                        if busy_until.get(port, 0) > t:
                            continue
                        if port in locks:
                            j = bisect_left(lock_starts[port], r.departure_slot) - 1
                            if j >= 0 and lock_ends[port][j] > t:
                                continue
                    spec = p.ports[port]
                    hi = min(cap, spec.max_power_kw)
                    lo = spec.max_power_kw if spec.control_type == ControlType.ON_OFF_SWITCH else spec.min_power_kw
                    if not is_leq(lo, hi, EPS_KW):
                        continue
                    hi = max(lo, hi)
                    used = lo if equal else hi
                    if equal:
                        pending[sid].append((r, port, lo, hi))
                    else:
                        record(r, port, t, hi)
                    grid -= used
                    station_left[sid] = local - used
                    taken.add(port)
                    break
                else:
                    continue
                if group in free:
                    free[group].pop(port, None)
            if equal:
                rows = []
                bounds = []
                for sid, entries in pending.items():
                    check()
                    local_bounds = [(lo, hi) for _, _, lo, hi in entries]
                    limits = _fill(local_bounds, p.stations[sid].station_power_kw)
                    rows.extend(entries)
                    bounds.extend((entry[2], limit) for entry, limit in zip(entries, limits))
                for (r, port, _, _), kw in zip(rows, _fill(bounds, p.grid_limit_kw)):
                    check()
                    if not is_leq(kw, 0, EPS_KW):
                        record(r, port, t, kw)
        check()
    except TimeoutError:
        sol.status = SolverStatus.FALLBACK
    sol.shortfall = {rid: snap(remaining.get(rid, r.remaining_kwh)) for rid, r in p.requests.items()}
    return sol


def solve_llf(problem: NormProblem) -> Solution:
    """Ưu tiên xe có thời gian dự phòng nhỏ nhất tại từng slot."""
    frozen = {k:v for k,v in problem.previous_schedule.items()
              if k[2] < problem.first_mutable_slot and not is_leq(v, 0, EPS_KW)}
    if not frozen:
        return _solve(problem, Algorithm.LLF)
    reqs = problem.requests.copy()
    for (rid,pid,_), kw in frozen.items():
        r = reqs[rid]
        if pid not in r.candidate_ports or (r.locked_port_id and r.locked_port_id != pid):
            raise ValueError("Dòng freeze không tương thích cổng của xe")
        reqs[rid] = replace(r, locked_port_id=pid, candidate_ports=(pid,),
                            remaining_kwh=max(0, r.remaining_kwh-kw*problem.dt))
    sol = _solve(replace(problem,requests=reqs),Algorithm.LLF)
    for (rid,pid,t), kw in frozen.items():
        sol.assign[rid] = pid
        sol.power[rid,pid,t] = kw
    return sol


def solve_fcfs(problem: NormProblem) -> Solution:
    """Ưu tiên xe đến sớm, phá hòa bằng mã yêu cầu."""
    return _solve(problem, Algorithm.FCFS)


def solve_edf(problem: NormProblem) -> Solution:
    """Ưu tiên xe rời đi sớm, phá hòa bằng mã yêu cầu."""
    return _solve(problem, Algorithm.EDF)


def solve_equal_share(problem: NormProblem) -> Solution:
    """Nhận mức sàn theo mã xe rồi chia đều phần công suất khả dụng."""
    return _solve(problem, Algorithm.EQUAL_SHARE)


def solve_asap(problem: NormProblem) -> Solution:
    """Cấp tối đa ngay khi có cổng, bỏ trần trạm và cụm để đối chứng."""
    return _solve(problem, Algorithm.ASAP)


SOLVERS: dict[str, Callable[[NormProblem], Solution]] = {
    "LLF": solve_llf, "FCFS": solve_fcfs, "EDF": solve_edf,
    "EQUAL_SHARE": solve_equal_share, "ASAP": solve_asap,
}


def compute_kpi(problem: NormProblem, solution: Solution) -> KPI:
    """Đánh giá xe cần giải; mỗi lần vượt trần trạm hoặc cụm trong một slot tính một lỗi."""
    allocated: dict[str, float] = defaultdict(float)
    stations: dict[tuple[str, int], float] = defaultdict(float)
    grid: dict[int, float] = defaultdict(float)
    cost = 0.0
    for (rid, port, t), kw in solution.power.items():
        kw = snap(kw, EPS_KW)
        energy = kw * problem.dt
        allocated[rid] += energy
        cost += energy * problem.price[t]
        stations[problem.ports[port].station_id, t] += kw
        grid[t] += kw
    fractions = []
    missing = []
    for rid, r in problem.requests.items():
        fractions.append(min(1.0, allocated[rid] / r.remaining_kwh))
        missing.append(snap(solution.shortfall.get(rid, max(0.0, r.remaining_kwh - allocated[rid]))))
    n = len(fractions)
    squares = fsum(x*x for x in fractions)
    fairness = min(1.0, fsum(fractions)**2 / (n*squares)) if squares else float(not n)
    violations = sum(not is_leq(v, problem.grid_limit_kw, EPS_KW) for v in grid.values())
    violations += sum(not is_leq(v, problem.stations[s].station_power_kw, EPS_KW) for (s, _), v in stations.items())
    return KPI(total_shortfall_kwh=fsum(missing), total_cost_vnd=cost,
               peak_power_kw=max(grid.values(), default=0.0), fairness=fairness,
               on_time_rate=sum(is_leq(x, 0) for x in missing) / n if n else 1.0,
               cap_violations=violations)
