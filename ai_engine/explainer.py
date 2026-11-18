"""Diễn giải lịch đã kiểm tra bằng số liệu của từng xe và từng slot."""

from collections import defaultdict
from dataclasses import dataclass, field
from itertools import groupby

from .normalizer import STEP, NormProblem, NormRequest, Solution
from .schemas import RequestResult
from .settings import EPS_KW, is_leq, is_zero, snap


@dataclass(slots=True)
class _Usage:
    """Các tổng dùng chung để chỉ quét lịch một lần khi dựng toàn bộ kết quả."""
    rows: dict[str, dict[int, float]] = field(default_factory=lambda: defaultdict(dict))
    occupied: set[tuple[str, int]] = field(default_factory=set)
    grid: dict[int, float] = field(default_factory=lambda: defaultdict(float))
    station: dict[tuple[str, int], float] = field(default_factory=lambda: defaultdict(float))


def _index(problem: NormProblem, solution: Solution) -> _Usage:
    """Lập chỉ mục lịch thưa đã qua validator."""
    usage = _Usage()
    for (rid, pid, t), kw in solution.power.items():
        if not is_leq(kw, 0, EPS_KW):
            usage.rows[rid][t] = kw
            usage.occupied.add((pid, t))
            usage.grid[t] += kw
            usage.station[problem.ports[pid].station_id, t] += kw
    return usage


def _number(value: float) -> str:
    """Định dạng số theo cách ghi phần nghìn và phần lẻ tiếng Việt."""
    return f"{value:,.3f}".rstrip("0").rstrip(".").translate(str.maketrans(",.", ".,"))


def _intervals(problem: NormProblem, slots: list[int]) -> str:
    """Gộp các slot liền nhau, hiện ngày khi lịch đi qua nửa đêm."""
    fmt = "%H:%M" if (problem.t0_time + (slots[-1]+1)*STEP).date() == problem.t0_time.date() else "%d/%m %H:%M"
    spans = []
    for _, group in groupby(enumerate(slots), key=lambda pair: pair[1]-pair[0]):
        times = [t for _, t in group]
        start = problem.t0_time + times[0]*STEP
        stop = problem.t0_time + (times[-1]+1)*STEP
        spans.append(f"{start:{fmt}}-{stop:{fmt}}")
    return ", ".join(spans)


def _reason(p: NormProblem, r: NormRequest, use: _Usage, slots: range, pid: str | None) -> str:
    """Nêu giới hạn quan sát được trong cửa sổ xe có thể sạc."""
    if r.port_lost and not pid:
        return f"cổng khóa {r.locked_port_id} không hoạt động"
    if not r.candidate_ports:
        return "không có cổng hoạt động tương thích tại trạm"
    if not slots:
        return "không còn slot 15 phút trọn vẹn trong giờ đỗ và giờ mở cửa của kỳ lập lịch"
    limit = min(r.vehicle_max_kw, p.ports[pid].max_power_kw) if pid else r.feasible_max_kw
    candidates = (pid,) if pid else r.candidate_ports
    compatible = [p.ports[port] for port in candidates if is_leq(p.ports[port].min_power_kw, r.vehicle_max_kw, EPS_KW)]
    if not compatible:
        return f"công suất tối thiểu của cổng vượt mức xe nhận được ({_number(r.vehicle_max_kw)} kW)"
    quantum = min(port.min_power_kw for port in compatible) * p.dt
    gap = r.remaining_kwh - sum(use.rows[r.request_id].values()) * p.dt
    if not use.rows[r.request_id] and not is_leq(quantum, gap):
        return f"một slot cần ít nhất {_number(quantum)} kWh, vượt nhu cầu còn lại"
    if not use.rows[r.request_id] and all((port.port_id,t) in use.occupied for port in compatible for t in slots):
        return "các cổng tương thích đều đang cấp điện cho xe khác trong toàn bộ thời gian khả dụng"
    local = p.stations[r.station_id].station_power_kw
    for label, cap, loads in (("cụm", p.grid_limit_kw, use.grid), ("trạm", local, None)):
        for t in slots:
            if is_leq(limit, use.rows[r.request_id].get(t, 0), EPS_KW):
                continue
            load = loads.get(t, 0) if loads is not None else use.station.get((r.station_id, t), 0)
            if is_leq(cap, load, EPS_KW):
                at = p.t0_time + t*STEP
                return f"{label} chạm trần {_number(cap)} kW lúc {at:%H:%M} trước giờ rời"
    if not is_leq(r.remaining_kwh, len(slots)*p.dt*limit):
        return f"chỉ có {len(slots)} slot có thể sạc trong kỳ với công suất tối đa {_number(limit)} kW"
    return "lịch hiện tại chưa phân bổ đủ điện trong các slot khả dụng"


def _result(p: NormProblem, sol: Solution, rid: str, use: _Usage) -> RequestResult:
    """Dựng kết quả một xe từ chỉ mục lịch và dữ liệu snapshot."""
    src = p.source_requests.get(rid)
    delivered = src.energy_delivered_kwh if src else 0.0
    rows = use.rows.get(rid, {})
    allocated = snap(sum(rows.values())*p.dt)
    cost = sum(kw*p.dt*p.price[t] for t, kw in rows.items())
    if rid in p.skipped_results:
        allocated, missing = p.skipped_results[rid]
        text = (f"Xe đã nạp {_number(delivered)} kWh và không cần sạc thêm."
                if src and is_leq(src.energy_needed_kwh, delivered) else
                f"Phiên {src.status.value if src else rid} đã đóng, lịch cấp thêm 0 kWh.")
    else:
        r = p.requests[rid]
        missing = snap(sol.shortfall.get(rid, max(0.0, r.remaining_kwh - allocated)))
        pid = sol.assign.get(rid)
        slots = range(max(r.active_slots.start, p.first_mutable_slot), min(p.T, r.active_slots.stop))
        if rows:
            ts = sorted(rows)
            text = f"Cổng {pid} cấp {_number(allocated)} kWh trong {_intervals(p, ts)}"
            if r.port_lost and pid in r.replacement_ports:
                text += f", thay cổng {r.locked_port_id} không hoạt động"
            if src and src.previous_port_id and src.previous_port_id != pid:
                old = p.ports.get(src.previous_port_id)
                if old and old.status == "MAINTENANCE":
                    text += f", thay cổng {old.port_id} đang bảo trì"
            cheapest = min((p.price[t] for t in slots), default=None)
            if cheapest is not None and all(p.price[t] == cheapest for t in ts):
                variable = any(p.price[t] > cheapest for t in slots)
                text += f", giá {'thấp nhất ' if variable else ''}{_number(cheapest)}đ/kWh"
        else:
            text = "Xe được cấp 0 kWh trong kỳ này"
        if not is_zero(delivered):
            text += f", giữ nguyên {_number(delivered)} kWh đã nạp"
        if not is_zero(missing):
            text += f". Còn thiếu {_number(missing)} kWh; {_reason(p, r, use, slots, pid)}."
        else:
            text += f", đủ nhu cầu trước giờ rời {r.departure_time:%H:%M}."
    if src and src.current_soc_pct is not None and src.battery_capacity_kwh is not None:
        soc = min(100.0, src.current_soc_pct + 100 * (allocated/src.battery_capacity_kwh))
    else:
        need = src.energy_needed_kwh if src else (p.requests[rid].remaining_kwh if rid in p.requests else 0)
        soc = min(100.0, 100*((allocated + delivered)/need)) if not is_zero(need) else 100.0
    return RequestResult(request_id=rid, allocated_kwh=allocated, shortfall_kwh=missing,
                         expected_soc=soc, estimated_cost_vnd=cost, explanation=text)


def build_explanation(problem: NormProblem, solution: Solution, request_id: str) -> str:
    """Giải thích bằng tiếng Việt cho một yêu cầu trong snapshot."""
    return _result(problem, solution, request_id, _index(problem, solution)).explanation


def build_all_results(problem: NormProblem, solution: Solution) -> list[RequestResult]:
    """SOC dùng mức pin tại snapshot và điện cấp thêm, giả định hiệu suất 100%.

    Khi thiếu dữ liệu pin, expected_soc là phần trăm đáp ứng nhu cầu toàn phiên:
    (đã nạp + cấp thêm) / nhu cầu, tối đa 100%; nhu cầu bằng 0 coi là 100%.
    """
    use = _index(problem, solution)
    return [_result(problem, solution, rid, use)
            for group in (problem.requests, problem.skipped_results) for rid in group]
