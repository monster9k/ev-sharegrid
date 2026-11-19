"""Database-to-AI contract, serialized cluster optimization, and schedule writes."""

from __future__ import annotations

import json
import os
from collections.abc import Iterable, Mapping
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from pydantic import ValidationError

from ai_engine.schemas import OptimizeRequest, OptimizeResponse
from backend.db import connect


AI_TIMEOUT_SECONDS = 15.0
DEFAULT_HORIZON_SLOTS = 96
SLOT_MINUTES = 15
TERMINAL_REQUEST_STATUSES = ("DONE", "CANCELLED", "NO_SHOW", "FAILED")

CONNECTOR_MAP = {
    "CCS2_DC": "CCS2",
    "CCS2": "CCS2",
    "AC_HOME_VINFAST_ADAPTER": "AC_HOME",
    "AC_HOME": "AC_HOME",
    "Type2": "Type2",
    "CHAdeMO": "CHAdeMO",
}


class AIUpstreamError(RuntimeError):
    """An AI Engine failure that should be returned to the API client."""

    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def to_ai_connector(connector_type: str) -> str:
    """Normalize connector catalog names to the four values accepted by AI."""
    try:
        return CONNECTOR_MAP[connector_type]
    except KeyError as exc:
        allowed = ", ".join(sorted({"CCS2", "Type2", "CHAdeMO", "AC_HOME"}))
        raise ValueError(
            f"Unsupported connector_type {connector_type!r}; expected one of {allowed}"
        ) from exc


def _as_dict(cursor: Any, row: Any) -> dict[str, Any]:
    if isinstance(row, Mapping):
        return dict(row)
    description = getattr(cursor, "description", None)
    if not description:
        raise ValueError("Database cursor must expose column names for tuple rows")
    names = [column.name if hasattr(column, "name") else column[0] for column in description]
    return dict(zip(names, row, strict=True))


def _fetchone(cursor: Any, query: str, params: tuple[Any, ...]) -> dict[str, Any] | None:
    cursor.execute(query, params)
    row = cursor.fetchone()
    return _as_dict(cursor, row) if row is not None else None


def _fetchall(cursor: Any, query: str, params: tuple[Any, ...]) -> list[dict[str, Any]]:
    cursor.execute(query, params)
    return [_as_dict(cursor, row) for row in cursor.fetchall()]


def _cluster_timezone(name: str | None) -> ZoneInfo | timezone:
    timezone_name = name or "Asia/Ho_Chi_Minh"
    try:
        return ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError as exc:
        if timezone_name == "Asia/Ho_Chi_Minh":
            return timezone(timedelta(hours=7))
        raise ValueError(f"Unknown grid_cluster.timezone {timezone_name!r}") from exc


def _as_time(value: time | str) -> time:
    if isinstance(value, time):
        return value.replace(tzinfo=None)
    text = value.strip()
    if text == "24:00":
        return time.min
    return time.fromisoformat(text)


def _time_interval(day: date, start: time | str, end: time | str, tz: Any) -> tuple[datetime, datetime]:
    start_time = _as_time(start)
    end_time = _as_time(end)
    interval_start = datetime.combine(day, start_time, tz)
    interval_end = datetime.combine(day, end_time, tz)
    if interval_end <= interval_start:
        interval_end += timedelta(days=1)
    return interval_start, interval_end


def _station_interval(station: Mapping[str, Any], start: datetime, end: datetime) -> tuple[datetime, datetime]:
    if station["is_24h"]:
        return start, end
    opening, closing = _time_interval(
        start.date(), station["open_time"], station["close_time"], start.tzinfo
    )
    while closing <= start:
        opening += timedelta(days=1)
        closing += timedelta(days=1)
    if end > closing:
        raise ValueError(
            f"Station {station['station_id']} is not 24h and the AI snapshot schema cannot represent recurring opening hours across this horizon"
        )
    return opening, closing


def _build_tariffs(
    cursor: Any,
    cluster_id: int,
    start: datetime,
    end: datetime,
) -> list[dict[str, Any]]:
    rows = _fetchall(
        cursor,
        """
        SELECT day_type, start_time, end_time, price_vnd_kwh, valid_from, valid_to
        FROM tariff_window
        WHERE cluster_id = %s
          AND day_type IN ('WEEKDAY', 'WEEKEND')
          AND valid_from <= %s::date
          AND valid_to >= %s::date
        ORDER BY valid_from, start_time, tariff_id
        """,
        (cluster_id, end.date(), start.date()),
    )
    result: list[dict[str, Any]] = []
    day = start.date()
    while datetime.combine(day, time.min, start.tzinfo) < end:
        day_type = "WEEKDAY" if day.weekday() < 5 else "WEEKEND"
        date_rows = [
            row for row in rows
            if row["day_type"] == day_type
            and row["valid_from"] <= day <= row["valid_to"]
        ]
        selected: dict[tuple[time, time], dict[str, Any]] = {}
        for row in date_rows:
            interval_key = (_as_time(row["start_time"]), _as_time(row["end_time"]))
            previous = selected.get(interval_key)
            if previous is None or row["valid_from"] > previous["valid_from"]:
                selected[interval_key] = row
            elif row["valid_from"] == previous["valid_from"]:
                raise ValueError(f"Overlapping tariff_window rows for cluster {cluster_id} on {day}")
        for row in sorted(selected.values(), key=lambda item: _as_time(item["start_time"])):
            interval_start, interval_end = _time_interval(
                day, row["start_time"], row["end_time"], start.tzinfo
            )
            clipped_start, clipped_end = max(start, interval_start), min(end, interval_end)
            if clipped_start < clipped_end:
                result.append({
                    "start_time": clipped_start.isoformat(timespec="seconds"),
                    "end_time": clipped_end.isoformat(timespec="seconds"),
                    "price_vnd_kwh": float(row["price_vnd_kwh"]),
                })
        day += timedelta(days=1)

    result.sort(key=lambda item: item["start_time"])
    cursor_time = start
    for tariff in result:
        interval_start = datetime.fromisoformat(tariff["start_time"])
        interval_end = datetime.fromisoformat(tariff["end_time"])
        if interval_start != cursor_time:
            raise ValueError(f"Tariff window gap or overlap at {cursor_time.isoformat()}")
        cursor_time = interval_end
    if cursor_time != end:
        raise ValueError(f"Tariffs do not cover snapshot horizon ending {end.isoformat()}")
    return result


def build_cluster_snapshot(
    cursor: Any,
    cluster_id: int,
    input_version: int,
    *,
    snapshot_time: datetime | None = None,
    horizon_slots: int = DEFAULT_HORIZON_SLOTS,
) -> dict[str, Any]:
    """Build the AI JSON body from schema-backed columns in one locked transaction.

    The caller must acquire pg_advisory_xact_lock(cluster_id) before this function
    and allocate input_version from optimization_job.target_version after the lock.
    """
    cluster = _fetchone(
        cursor,
        "SELECT cluster_id, grid_limit_kw, timezone FROM grid_cluster WHERE cluster_id = %s AND status = 'ACTIVE'",
        (cluster_id,),
    )
    if cluster is None:
        raise ValueError(f"Active grid_cluster {cluster_id} was not found")
    tz = _cluster_timezone(cluster["timezone"])
    now = snapshot_time or datetime.now(tz)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("snapshot_time must include a timezone")
    # Anchor all snapshot data to the same quarter-hour boundary. The AI solver
    # aligns its first slot down to 15 minutes, so tariffs and station windows
    # must start at that exact boundary too (including when the API call arrives
    # during a slot or just before midnight).
    now = now.astimezone(tz)
    now = now.replace(second=0, microsecond=0) - timedelta(minutes=now.minute % SLOT_MINUTES)
    if now.utcoffset() != timedelta(hours=7):
        raise ValueError("AI Engine contract requires the cluster timezone to use +07:00")
    horizon_end = now + timedelta(minutes=horizon_slots * SLOT_MINUTES)

    station_rows = _fetchall(
        cursor,
        """
        SELECT station_id, station_power_kw, open_time, close_time, is_24h
        FROM charging_station
        WHERE cluster_id = %s AND status = 'ACTIVE'
        ORDER BY station_id
        """,
        (cluster_id,),
    )
    if not station_rows:
        raise ValueError(f"Active stations were not found in cluster {cluster_id}")

    port_rows = _fetchall(
        cursor,
        """
        SELECT p.port_id, p.station_id, p.connector_type, p.control_type,
               p.status, p.min_power_kw, p.max_power_kw
        FROM port p
        JOIN charging_station s ON s.station_id = p.station_id
        WHERE s.cluster_id = %s AND s.status = 'ACTIVE'
        ORDER BY p.station_id, p.port_id
        """,
        (cluster_id,),
    )

    request_rows = _fetchall(
        cursor,
        """
        SELECT cr.request_id, cr.station_id, cr.arrival_time, cr.departure_time,
               cr.battery_kwh_snapshot, cr.max_kw_snapshot, cr.energy_needed_kwh,
               cr.priority_weight, cr.status, vm.connector_type,
               COALESCE(delivered.energy_delivered_kwh, 0) AS energy_delivered_kwh,
               active_session.port_id AS locked_port_id
        FROM charging_request cr
        JOIN charging_station s ON s.station_id = cr.station_id
        JOIN vehicle v ON v.vehicle_id = cr.vehicle_id
        JOIN vehicle_model vm ON vm.model_id = v.model_id
        LEFT JOIN LATERAL (
            SELECT SUM(COALESCE(cs.energy_kwh, 0)) AS energy_delivered_kwh
            FROM charging_session cs
            WHERE cs.request_id = cr.request_id
        ) delivered ON TRUE
        LEFT JOIN LATERAL (
            SELECT cs.port_id
            FROM charging_session cs
            WHERE cs.request_id = cr.request_id
              AND cs.end_time IS NULL
              AND cs.status = 'IN_PROGRESS'
            ORDER BY cs.start_time DESC
            LIMIT 1
        ) active_session ON TRUE
        WHERE cr.cluster_id = %s
          AND s.status = 'ACTIVE'
          AND cr.status IN ('PENDING', 'SCHEDULED', 'CONFIRMED', 'CHARGING')
          AND cr.departure_time > %s
          AND cr.arrival_time < %s
        ORDER BY cr.request_id
        """,
        (cluster_id, now, horizon_end),
    )
    request_ids = {int(row["request_id"]) for row in request_rows}
    locked_ports = {
        int(row["locked_port_id"])
        for row in request_rows
        if row["locked_port_id"] is not None
    }
    request_payloads = []
    for row in request_rows:
        status = str(row["status"])
        if status in TERMINAL_REQUEST_STATUSES:
            continue
        locked_port = row["locked_port_id"]
        if status == "CHARGING" and locked_port is None:
            raise ValueError(
                f"CHARGING request {row['request_id']} has no IN_PROGRESS charging_session to lock its port"
            )
        request_payloads.append({
            "request_id": int(row["request_id"]),
            "station_id": int(row["station_id"]),
            "connector_type": to_ai_connector(str(row["connector_type"])),
            "battery_capacity_kwh": float(row["battery_kwh_snapshot"]),
            "vehicle_max_kw": float(row["max_kw_snapshot"]),
            "arrival_time": row["arrival_time"].astimezone(tz).isoformat(timespec="seconds"),
            "departure_time": row["departure_time"].astimezone(tz).isoformat(timespec="seconds"),
            "energy_needed_kwh": float(row["energy_needed_kwh"]),
            "energy_delivered_kwh": float(row["energy_delivered_kwh"] or 0),
            "priority_weight": float(row["priority_weight"]),
            "status": status,
            "locked_port_id": int(locked_port) if locked_port is not None else None,
        })

    station_payloads = []
    for station in station_rows:
        station_id = int(station["station_id"])
        opens, closes = _station_interval(station, now, horizon_end)
        if closes <= opens:
            raise ValueError(f"Invalid opening interval for station {station_id}")
        station_ports = []
        for port in port_rows:
            if int(port["station_id"]) != station_id:
                continue
            raw_status = str(port["status"])
            if int(port["port_id"]) in locked_ports:
                port_status = "ACTIVE"
            elif raw_status in {"ACTIVE", "AVAILABLE"}:
                port_status = "ACTIVE"
            elif raw_status == "OCCUPIED":
                port_status = "ACTIVE" if int(port["port_id"]) in locked_ports else "OFFLINE"
            elif raw_status in {"MAINTENANCE", "OFFLINE"}:
                port_status = raw_status
            else:
                raise ValueError(f"Unsupported port.status {raw_status!r} for port {port['port_id']}")
            control = str(port["control_type"])
            if control == "SMART_CONTINUOUS":
                control = "CONTINUOUS"
            if control not in {"CONTINUOUS", "ON_OFF_SWITCH"}:
                raise ValueError(f"Unsupported port.control_type {control!r} for port {port['port_id']}")
            minimum = float(port["min_power_kw"] or 0)
            maximum = float(port["max_power_kw"])
            if control == "ON_OFF_SWITCH":
                minimum = maximum
            station_ports.append({
                "port_id": int(port["port_id"]),
                "connector_type": to_ai_connector(str(port["connector_type"])),
                "control_type": control,
                "min_power_kw": minimum,
                "max_power_kw": maximum,
                "status": port_status,
            })
        station_payloads.append({
            "station_id": station_id,
            "station_power_kw": float(station["station_power_kw"]),
            "open_time": opens.isoformat(timespec="seconds"),
            "close_time": closes.isoformat(timespec="seconds"),
            "ports": station_ports,
        })

    previous_rows = _fetchall(
        cursor,
        """
        SELECT sc.request_id, sc.port_id, sc.slot_start, sc.power_kw
        FROM schedule sc
        JOIN charging_request cr ON cr.request_id = sc.request_id
        WHERE cr.cluster_id = %s
          AND sc.is_active = TRUE
          AND sc.slot_start + INTERVAL '15 minutes' <= %s
        ORDER BY sc.slot_start, sc.request_id, sc.port_id
        """,
        (cluster_id, now),
    )
    previous_schedule = [
        {
            "request_id": int(row["request_id"]),
            "port_id": int(row["port_id"]),
            "slot_start": row["slot_start"].astimezone(tz).isoformat(timespec="seconds"),
            "power_kw": float(row["power_kw"]),
        }
        for row in previous_rows
        if int(row["request_id"]) in request_ids
        and row["slot_start"] + timedelta(minutes=SLOT_MINUTES) <= now
    ]

    tariffs = _build_tariffs(cursor, cluster_id, now, horizon_end)
    body = {
        "cluster_id": int(cluster_id),
        "input_version": int(input_version),
        "snapshot_time": now.isoformat(timespec="seconds"),
        "slot_minutes": SLOT_MINUTES,
        "horizon_slots": int(horizon_slots),
        "previous_schedule": previous_schedule,
        "grid_limit_kw": float(cluster["grid_limit_kw"]),
        "stations": station_payloads,
        "tariffs": tariffs,
        "requests": request_payloads,
    }
    try:
        validated = OptimizeRequest.model_validate(body)
    except ValidationError as exc:
        raise ValueError(f"Snapshot does not match AI Engine contract: {exc}") from exc
    payload = validated.model_dump(mode="json")
    payload["input_version"] = int(input_version)
    return payload


def pick_request_result(ai_response: Mapping[str, Any] | OptimizeResponse, request_id: int | str) -> dict[str, Any]:
    """Return one AI request result using the BIGINT/string ID contract."""
    response = (
        ai_response.model_dump(mode="json")
        if isinstance(ai_response, OptimizeResponse)
        else ai_response
    )
    requested_id = str(request_id)
    for result in response.get("request_results", []):
        if str(result.get("request_id")) == requested_id:
            return dict(result)
    raise LookupError(f"AI response has no request_result for request_id={requested_id}")


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _decimal(value: Any) -> Decimal:
    return Decimal(str(value))


def _schedule_signature(items: Iterable[Mapping[str, Any]]) -> tuple[tuple[int, str], ...]:
    return tuple(sorted(
        (int(item["port_id"]), datetime.fromisoformat(str(item["slot_start"])).isoformat())
        for item in items
    ))


def save_schedule_version(
    cursor: Any,
    *,
    cluster_id: int,
    job_id: int,
    input_version: int,
    snapshot: Mapping[str, Any],
    ai_response: Mapping[str, Any] | OptimizeResponse,
    snapshot_time: datetime,
    trigger_type: str = "NEW_BOOKING",
    new_request_ids: Iterable[int] = (),
) -> int:
    """Persist one AI run, its request KPIs, and only future schedule slots."""
    response = (
        ai_response.model_dump(mode="json")
        if isinstance(ai_response, OptimizeResponse)
        else dict(ai_response)
    )
    status = str(response["status"])
    algorithm = response.get("algorithm")
    if status == "ERROR" or not algorithm:
        raise AIUpstreamError(502, "AI Engine returned no usable optimization result")
    allowed_statuses = {"OPTIMAL", "FEASIBLE", "FALLBACK", "INFEASIBLE"}
    if status not in allowed_statuses:
        raise AIUpstreamError(502, f"AI Engine returned unsupported status {status!r}")

    request_results = response.get("request_results", [])
    schedules = response.get("schedules", [])
    result_by_id = {int(item["request_id"]): item for item in request_results}
    if len(result_by_id) != len(request_results):
        raise AIUpstreamError(502, "AI Engine returned duplicate request_result IDs")
    expected_request_ids = {int(item["request_id"]) for item in snapshot["requests"]}
    if not expected_request_ids.issubset(result_by_id):
        missing = sorted(expected_request_ids - result_by_id.keys())
        raise AIUpstreamError(502, f"AI Engine omitted request results: {missing[:10]}")
    extras = sorted(result_by_id.keys() - expected_request_ids)
    if extras:
        raise AIUpstreamError(502, f"AI Engine returned results outside the snapshot: {extras[:10]}")
    allowed_ports = {
        int(port["port_id"])
        for station in snapshot["stations"]
        for port in station["ports"]
    }
    for item in schedules:
        if int(item["request_id"]) not in expected_request_ids or int(item["port_id"]) not in allowed_ports:
            raise AIUpstreamError(502, "AI Engine returned a schedule outside the snapshot")
    for item in request_results:
        if item.get("expected_soc") is None:
            raise AIUpstreamError(502, f"AI Engine returned null expected_soc for request {item['request_id']}")

    old_request_rows = _fetchall(
        cursor,
        "SELECT request_id, user_id, shortfall_kwh FROM charging_request WHERE cluster_id = %s",
        (cluster_id,),
    )
    old_requests = {int(row["request_id"]): row for row in old_request_rows}
    prior_schedules = _fetchall(
        cursor,
        """
        SELECT sc.request_id, sc.port_id, sc.slot_start
        FROM schedule sc
        JOIN charging_request cr ON cr.request_id = sc.request_id
        WHERE cr.cluster_id = %s AND sc.is_active = TRUE AND sc.slot_start >= %s
        ORDER BY sc.request_id, sc.slot_start, sc.port_id
        """,
        (cluster_id, snapshot_time),
    )
    old_schedule_by_request: dict[int, list[dict[str, Any]]] = {}
    for row in prior_schedules:
        old_schedule_by_request.setdefault(int(row["request_id"]), []).append({
            "port_id": int(row["port_id"]),
            "slot_start": row["slot_start"].isoformat(),
        })
    prior_results = _fetchall(
        cursor,
        """
        SELECT DISTINCT ON (rr.request_id) rr.request_id, rr.shortfall_kwh
        FROM run_request rr
        JOIN optimization_run run ON run.run_id = rr.run_id
        JOIN charging_request cr ON cr.request_id = rr.request_id
        WHERE cr.cluster_id = %s
        ORDER BY rr.request_id, run.started_at DESC, run.run_id DESC
        """,
        (cluster_id,),
    )
    old_shortfall = {
        int(row["request_id"]): _decimal(row["shortfall_kwh"])
        for row in prior_results
    }
    for request_id, row in old_requests.items():
        old_shortfall.setdefault(request_id, _decimal(row["shortfall_kwh"] or 0))

    # Retire only future rows in this cluster. Completed/current slots remain active.
    cursor.execute(
        """
        UPDATE schedule sc
        SET is_active = FALSE
        FROM charging_request cr
        WHERE sc.request_id = cr.request_id
          AND cr.cluster_id = %s
          AND sc.is_active = TRUE
          AND sc.slot_start >= %s
        """,
        (cluster_id, snapshot_time),
    )

    kpi = response["kpi"]
    cursor.execute(
        """
        INSERT INTO optimization_run (
            cluster_id, job_id, algorithm, trigger_type, status, solve_ms,
            seed, slot_minutes, n_requests, input_json, kpi_json
        ) VALUES (%s, %s, %s, %s, %s, %s, 42, 15, %s, %s::jsonb, %s::jsonb)
        RETURNING run_id
        """,
        (
            cluster_id,
            job_id,
            str(algorithm),
            trigger_type,
            status,
            int(_decimal(response["solve_ms"]).quantize(Decimal("1"), rounding=ROUND_HALF_UP)),
            len(snapshot["requests"]),
            _json({**dict(snapshot), "input_version": input_version}),
            _json(kpi),
        ),
    )
    run_id_row = cursor.fetchone()
    run_id = int(run_id_row[0] if not isinstance(run_id_row, Mapping) else run_id_row["run_id"])

    for request_id, result in result_by_id.items():
        cursor.execute(
            """
            INSERT INTO run_request (
                run_id, request_id, allocated_kwh, shortfall_kwh,
                expected_soc, estimated_cost_vnd, explanation
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (
                run_id,
                request_id,
                result["allocated_kwh"],
                result["shortfall_kwh"],
                result["expected_soc"],
                result["estimated_cost_vnd"],
                result["explanation"],
            ),
        )

    future_schedules = []
    for item in schedules:
        slot_start = datetime.fromisoformat(str(item["slot_start"]))
        if slot_start < snapshot_time or float(item["power_kw"]) <= 0:
            continue
        future_schedules.append(item)
        cursor.execute(
            """
            INSERT INTO schedule (run_id, request_id, port_id, slot_start, power_kw, version, is_active)
            VALUES (%s, %s, %s, %s, %s, %s, TRUE)
            """,
            (
                run_id,
                int(item["request_id"]),
                int(item["port_id"]),
                slot_start,
                item["power_kw"],
                input_version,
            ),
        )

    new_schedule_by_request: dict[int, list[dict[str, Any]]] = {}
    for item in future_schedules:
        new_schedule_by_request.setdefault(int(item["request_id"]), []).append({
            "port_id": int(item["port_id"]),
            "slot_start": item["slot_start"],
        })
    new_ids = {int(request_id) for request_id in new_request_ids}
    for request_id, old in old_requests.items():
        if request_id in new_ids or request_id not in result_by_id:
            continue
        new_result = result_by_id[request_id]
        old_signature = _schedule_signature(old_schedule_by_request.get(request_id, []))
        new_signature = _schedule_signature(new_schedule_by_request.get(request_id, []))
        new_missing = _decimal(new_result["shortfall_kwh"]).quantize(Decimal("0.000001"))
        old_missing = old_shortfall.get(request_id, Decimal(0)).quantize(Decimal("0.000001"))
        if old_signature != new_signature or old_missing != new_missing:
            cursor.execute(
                """
                INSERT INTO notification (user_id, request_id, type, title, body)
                VALUES (%s, %s, 'SCHEDULE_CHANGED', %s, %s)
                """,
                (
                    old["user_id"],
                    request_id,
                    "Lịch sạc đã thay đổi",
                    "Cổng, khung giờ hoặc lượng điện còn thiếu trong lịch sạc đã thay đổi.",
                ),
            )

    for request_id, result in result_by_id.items():
        cursor.execute(
            """
            UPDATE charging_request
            SET shortfall_kwh = %s,
                status = CASE WHEN status = 'PENDING' AND %s THEN 'SCHEDULED' ELSE status END
            WHERE request_id = %s AND cluster_id = %s
            """,
            (
                result["shortfall_kwh"],
                status in {"OPTIMAL", "FEASIBLE", "FALLBACK"},
                request_id,
                cluster_id,
            ),
        )
    return run_id


def _call_ai(snapshot: Mapping[str, Any]) -> OptimizeResponse:
    ai_url = os.getenv("AI_URL", "").strip().rstrip("/")
    if not ai_url:
        raise AIUpstreamError(503, "AI_URL is not configured")
    try:
        response = httpx.post(
            f"{ai_url}/ai/optimize",
            json=dict(snapshot),
            timeout=AI_TIMEOUT_SECONDS,
        )
    except httpx.TimeoutException as exc:
        raise AIUpstreamError(503, "AI Engine timed out after 15 seconds") from exc
    except httpx.RequestError as exc:
        raise AIUpstreamError(503, "AI Engine is unavailable") from exc
    if response.status_code >= 500 or response.status_code == 429:
        raise AIUpstreamError(503, f"AI Engine returned HTTP {response.status_code}")
    if response.status_code >= 400:
        raise AIUpstreamError(502, f"AI Engine rejected the snapshot (HTTP {response.status_code})")
    try:
        result = OptimizeResponse.model_validate(response.json())
    except (ValueError, ValidationError) as exc:
        raise AIUpstreamError(502, "AI Engine returned an invalid OptimizeResponse") from exc
    if result.status.value == "ERROR" or result.algorithm is None:
        raise AIUpstreamError(502, "AI Engine returned status ERROR without a usable schedule")
    return result


def trigger_cluster_reoptimize(
    cluster_id: int,
    *,
    new_request_ids: Iterable[int] = (),
    trigger_event_id: int | None = None,
    snapshot_time: datetime | None = None,
    trigger_type: str = "NEW_BOOKING",
) -> OptimizeResponse:
    """Serialize one cluster run and persist job/outbox failures for retry."""
    connection = connect()
    failure: Exception | None = None
    result: OptimizeResponse | None = None
    try:
        cursor = connection.cursor()
        try:
            # This must be the first SQL statement in the transaction, before target_version/input_version.
            cursor.execute("SELECT pg_advisory_xact_lock(%s)", (int(cluster_id),))
            cursor.execute(
                "SELECT COALESCE(MAX(target_version), 0) + 1 FROM optimization_job WHERE cluster_id = %s",
                (int(cluster_id),),
            )
            input_version = int(cursor.fetchone()[0])
            cursor.execute(
                """
                INSERT INTO optimization_job (cluster_id, target_version, status, events_count, started_at)
                VALUES (%s, %s, 'RUNNING', 1, CURRENT_TIMESTAMP)
                RETURNING job_id
                """,
                (int(cluster_id), input_version),
            )
            job_id = int(cursor.fetchone()[0])
            cursor.execute(
                """
                INSERT INTO outbox_event (
                    cluster_id, aggregate_type, aggregate_id, event_type, payload_json, dedupe_key
                ) VALUES (%s, 'OPTIMIZATION_JOB', %s, 'OPTIMIZATION_REQUESTED', %s::jsonb, %s)
                RETURNING event_id
                """,
                (
                    int(cluster_id),
                    job_id,
                    _json({
                        "job_id": job_id,
                        "cluster_id": int(cluster_id),
                        "input_version": input_version,
                        "trigger_type": trigger_type,
                    }),
                    f"optimization:{cluster_id}:{input_version}",
                ),
            )
            job_event_id = int(cursor.fetchone()[0])
            cursor.execute("SAVEPOINT optimization_attempt")
            try:
                now = snapshot_time or datetime.now(_cluster_timezone("Asia/Ho_Chi_Minh"))
                snapshot = build_cluster_snapshot(
                    cursor,
                    int(cluster_id),
                    input_version,
                    snapshot_time=now,
                )
                result = _call_ai(snapshot)
                run_id = save_schedule_version(
                    cursor,
                    cluster_id=int(cluster_id),
                    job_id=job_id,
                    input_version=input_version,
                    snapshot=snapshot,
                    ai_response=result,
                    snapshot_time=now,
                    trigger_type=trigger_type,
                    new_request_ids=new_request_ids,
                )
                cursor.execute(
                    "UPDATE optimization_job SET status = 'COMPLETED', finished_at = CURRENT_TIMESTAMP WHERE job_id = %s",
                    (job_id,),
                )
                cursor.execute(
                    "UPDATE outbox_event SET status = 'PUBLISHED', published_at = CURRENT_TIMESTAMP WHERE event_id = %s",
                    (job_event_id,),
                )
                if trigger_event_id is not None:
                    cursor.execute(
                        "UPDATE outbox_event SET status = 'PUBLISHED', published_at = CURRENT_TIMESTAMP WHERE event_id = %s",
                        (int(trigger_event_id),),
                    )
                cursor.execute(
                    "UPDATE optimization_run SET input_json = input_json || %s::jsonb WHERE run_id = %s",
                    (_json({"job_id": job_id, "input_version": input_version}), run_id),
                )
            except Exception as exc:
                cursor.execute("ROLLBACK TO SAVEPOINT optimization_attempt")
                cursor.execute(
                    "UPDATE optimization_job SET status = 'FAILED', finished_at = CURRENT_TIMESTAMP, attempt_count = attempt_count + 1 WHERE job_id = %s",
                    (job_id,),
                )
                cursor.execute(
                    "UPDATE outbox_event SET status = 'FAILED', attempts = attempts + 1 WHERE event_id = %s",
                    (job_event_id,),
                )
                failure = exc
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            cursor.close()
    finally:
        connection.close()

    if failure is not None:
        if isinstance(failure, AIUpstreamError):
            raise failure
        if isinstance(failure, (ValueError, ValidationError)):
            raise AIUpstreamError(502, f"Could not build or save the AI schedule: {failure}") from failure
        raise AIUpstreamError(503, f"Optimization failed: {type(failure).__name__}") from failure
    if result is None:
        raise AIUpstreamError(503, "Optimization did not produce a result")
    return result
