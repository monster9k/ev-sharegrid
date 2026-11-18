"""Chuẩn hóa dữ liệu theo slot 15 phút cho các bộ lập lịch."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Iterable, Literal

from .schemas import (
    ConnectorType, ControlType, OptimizeRequest, PortStatus, RequestStatus,
    ScheduleItem, Tariff, Algorithm, SolverStatus, ChargingRequestIn,
)

STEP = timedelta(minutes=15)
VN = timezone(timedelta(hours=7))
TERMINAL = {RequestStatus.DONE, RequestStatus.CANCELLED, RequestStatus.NO_SHOW, RequestStatus.FAILED}


def iso_to_slot(value: str | datetime, t0_time: datetime,
                rounding: Literal["floor", "ceil"] = "floor") -> int:
    """Đổi thời điểm thành chỉ số có dấu so với đầu horizon."""
    instant = datetime.fromisoformat(value) if isinstance(value, str) else value
    if instant.utcoffset() != VN.utcoffset(None) or t0_time.utcoffset() != VN.utcoffset(None):
        raise ValueError("Thời điểm phải có múi giờ +07:00")
    delta = instant - t0_time
    if rounding == "ceil":
        return -((-delta) // STEP)
    if rounding != "floor":
        raise ValueError("rounding phải là floor hoặc ceil")
    return delta // STEP


def slot_to_iso(slot: int, t0_time: datetime) -> str:
    """Đổi chỉ số slot về chuỗi thời gian của Backend."""
    return (t0_time + slot * STEP).isoformat()


@dataclass(slots=True)
class Solution:
    """Nghiệm thưa của solver, chỉ ghi công suất dương tại các slot có sạc."""
    assign: dict[str, str]
    power: dict[tuple[str, str, int], float]
    status: SolverStatus
    algorithm: Algorithm
    shortfall: dict[str, float] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class NormPort:
    """Cổng vật lý và miền công suất điều khiển."""
    port_id: str
    station_id: str
    connector_type: ConnectorType
    control_type: ControlType
    min_power_kw: float
    max_power_kw: float
    status: PortStatus


@dataclass(frozen=True, slots=True)
class NormStation:
    """Trạm với khoảng slot mở cửa đầy đủ."""
    station_id: str
    station_power_kw: float
    open_slots: range
    port_ids: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class NormRequest:
    """Yêu cầu sau khi cắt cửa sổ sạc, đơn vị công suất kW."""
    request_id: str
    station_id: str
    connector_type: ConnectorType
    vehicle_max_kw: float
    arrival_time: datetime
    departure_time: datetime
    arrival_slot: int
    departure_slot: int
    active_slots: range
    remaining_kwh: float
    priority_weight: float
    status: RequestStatus
    locked_port_id: str | None
    candidate_ports: tuple[str, ...]
    replacement_ports: tuple[str, ...]
    port_lost: bool
    feasible_max_kw: float


@dataclass(frozen=True, slots=True)
class NormProblem:
    """Dữ liệu chung; requests chỉ chứa xe cần giải, tra cứu bằng ID."""
    t0_time: datetime
    snapshot_time: datetime
    T: int
    dt: float
    price: tuple[float, ...]
    grid_limit_kw: float
    time_budget_ms: int
    stations: dict[str, NormStation]
    ports: dict[str, NormPort]
    requests: dict[str, NormRequest]
    # Hai giá trị là allocated_kwh và shortfall_kwh của xe đã loại.
    skipped_results: dict[str, tuple[float, float]]
    # Slot 0 đã bắt đầu tại snapshot, giữ nguyên cho MPC.
    first_mutable_slot: int = 1
    previous_schedule: dict[tuple[str, str, int], float] = field(default_factory=dict)
    source_requests: dict[str, ChargingRequestIn] = field(default_factory=dict)


def _minutes(clock: str) -> int:
    """Đổi giờ dân dụng, kể cả 24:00, thành phút từ đầu ngày."""
    hour, minute = map(int, clock.split(":"))
    return hour * 60 + minute


def _prices(tariffs: list[Tariff], t0: datetime, count: int) -> tuple[float, ...]:
    """Tính giá bình quân theo thời lượng và phát hiện thiếu hoặc trùng giá."""
    end = t0 + count * STEP
    periods: list[tuple[datetime, datetime, float]] = []
    for tariff in tariffs:
        start, stop = tariff.start_time, tariff.end_time
        if isinstance(start, datetime) and isinstance(stop, datetime):
            periods.append((start, stop, tariff.price_vnd_kwh))
        elif isinstance(start, str) and isinstance(stop, str):
            a, b = _minutes(start), _minutes(stop)
            if b <= a:
                b += 1440
            day = t0.replace(hour=0, minute=0) - timedelta(days=1)
            while day < end:
                periods.append((day + timedelta(minutes=a), day + timedelta(minutes=b), tariff.price_vnd_kwh))
                day += timedelta(days=1)
    periods.sort()
    values: list[float] = []
    cursor = t0
    cost = 0.0
    for start, stop, rate in periods:
        start, stop = max(t0, start), min(end, stop)
        if stop <= start:
            continue
        if start < cursor:
            raise ValueError(f"Giá chồng lấn tại {start.isoformat()}")
        if start > cursor:
            raise ValueError(f"Thiếu giá tại slot {len(values)} ({cursor.isoformat()})")
        while cursor < stop:
            boundary = t0 + (len(values) + 1) * STEP
            until = min(stop, boundary)
            cost += rate * ((until - cursor) / STEP)
            cursor = until
            if cursor == boundary:
                values.append(cost)
                cost = 0.0
    if cursor < end:
        raise ValueError(f"Thiếu giá tại slot {len(values)} ({cursor.isoformat()})")
    return tuple(values)


def normalize(req: OptimizeRequest) -> NormProblem:
    """Lập chỉ mục theo trạm và chuẩn đầu nối, chia sẻ danh sách cổng giữa các xe."""
    now = req.snapshot_time
    t0 = now.replace(minute=now.minute // 15 * 15, second=0, microsecond=0)
    count = req.horizon_slots

    def clipped(value: datetime, rounding: Literal["floor", "ceil"]) -> int:
        """Cắt biên vào horizon, cho phép biên phải bằng T."""
        return max(0, min(count, iso_to_slot(value, t0, rounding)))

    stations: dict[str, NormStation] = {}
    ports: dict[str, NormPort] = {}
    groups: dict[tuple[str, ConnectorType], list[str]] = {}
    for station in req.stations:
        sid = station.station_id
        stations[sid] = NormStation(sid, station.station_power_kw,
            range(clipped(station.open_time, "ceil"), clipped(station.close_time, "floor")),
            tuple(p.port_id for p in station.ports))
        for p in station.ports:
            ports[p.port_id] = NormPort(p.port_id, sid, p.connector_type, p.control_type,
                                        p.min_power_kw, p.max_power_kw, p.status)
            if p.status == PortStatus.ACTIVE:
                groups.setdefault((sid, p.connector_type), []).append(p.port_id)
    candidates = {key: tuple(ids) for key, ids in groups.items()}
    maxima = {key: max(ports[i].max_power_kw for i in ids) for key, ids in candidates.items()}
    requests: dict[str, NormRequest] = {}
    skipped: dict[str, tuple[float, float]] = {}
    for r in sorted(req.requests,key=lambda item:item.request_id):
        remaining = max(0.0, r.energy_needed_kwh - r.energy_delivered_kwh)
        if not remaining or r.status in TERMINAL:
            skipped[r.request_id] = (0.0, 0.0)
            continue
        key = (r.station_id, r.connector_type)
        ids = candidates.get(key, ())
        maximum = maxima.get(key, 0.0)
        lost = False
        replacements: tuple[str, ...] = ()
        if r.locked_port_id is not None:
            locked = ports[r.locked_port_id]
            lost = locked.status != PortStatus.ACTIVE
            replacements = ids if lost else ()
            ids = () if lost else (locked.port_id,)
            maximum = 0.0 if lost else locked.max_power_kw
        arrival = clipped(r.arrival_time, "ceil")
        departure = clipped(r.departure_time, "floor")
        opened = stations[r.station_id].open_slots
        requests[r.request_id] = NormRequest(
            r.request_id, r.station_id, r.connector_type, r.vehicle_max_kw, r.arrival_time,
            r.departure_time, arrival, departure, range(max(arrival, opened.start), min(departure, opened.stop)),
            remaining, r.priority_weight, r.status, r.locked_port_id, ids, replacements,
            lost, min(r.vehicle_max_kw, maximum))
    previous: dict[tuple[str, str, int], float] = {}
    for row in req.previous_schedule:
        t = iso_to_slot(row.slot_start, t0)
        if 0 <= t < count:
            key = (row.request_id, row.port_id, t)
            if key in previous:
                raise ValueError("Lịch MPC cũ trùng dòng")
            previous[key] = row.power_kw
    return NormProblem(t0, now, count, 0.25, _prices(req.tariffs, t0, count), req.grid_limit_kw,
                       req.time_budget_ms, stations, ports, requests, skipped,
                       first_mutable_slot=int(now != t0 or bool(previous) or any(r.status == "CHARGING" for r in requests.values())),
                       previous_schedule=previous, source_requests={r.request_id: r for r in req.requests})


def to_response_slots(problem: NormProblem,
                      allocations: Iterable[tuple[str, str, int, float]]) -> list[ScheduleItem]:
    """Đổi các dòng (request_id, port_id, slot, power_kw) thành lịch JSON."""
    result: list[ScheduleItem] = []
    for request_id, port_id, slot, power_kw in allocations:
        if not 0 <= slot < problem.T:
            raise ValueError(f"Slot {slot} ngoài horizon")
        result.append(ScheduleItem(request_id=request_id, port_id=port_id,
                                   slot_start=slot_to_iso(slot, problem.t0_time), power_kw=power_kw))
    return result
