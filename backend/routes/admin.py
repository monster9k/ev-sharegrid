"""Administrative cluster, tariff, benchmark, and forecast endpoints."""

from __future__ import annotations

import json
import os
import re
from collections import defaultdict
from datetime import timedelta, timezone
from pathlib import Path
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator

from ai_engine.schemas import (
    Algorithm, BenchmarkRequest, BenchmarkResponse, ForecastModel, ForecastRequest, ForecastResponse,
)
from backend.ai_contract import AI_TIMEOUT_SECONDS, AIUpstreamError, trigger_cluster_reoptimize
from backend.auth import AuthUser, require_roles
from backend.db import connect, dict_cursor


router = APIRouter(prefix="/api/v1/admin", tags=["Admin Portal"])
DEFAULT_BENCHMARK_REPORT_PATH = "/app/ai_engine/benchmark_real.json"
CLOCK_PATTERN = re.compile(r"^(?:(?:[01]\d|2[0-3]):[0-5]\d|24:00)$")


class ClusterGridLimitPatch(BaseModel):
    grid_limit_kw: float = Field(gt=0, le=1_000_000)


class StationVerifyPatch(BaseModel):
    verified: bool


class AdminForecastRun(BaseModel):
    cluster_id: int = Field(gt=0)
    horizon_hours: int = Field(default=24, ge=1, le=168)
    model: ForecastModel = ForecastModel.BEST


class AdminBenchmarkRequest(BenchmarkRequest):
    algorithms: list[Algorithm] = Field(min_length=1, max_length=11)
    repeats: int = Field(default=1, ge=1, le=5)


class TariffWindowInput(BaseModel):
    day_type: Literal["WEEKDAY", "WEEKEND"]
    band: Literal["OFF_PEAK", "NORMAL", "PEAK"]
    start_time: str
    end_time: str
    price_vnd_kwh: float = Field(ge=0, le=10_000_000)

    @field_validator("start_time", "end_time")
    @classmethod
    def validate_clock(cls, value: str) -> str:
        if not CLOCK_PATTERN.fullmatch(value):
            raise ValueError("time must use HH:MM from 00:00 through 24:00")
        return value


class TariffSet(BaseModel):
    tariffs: list[TariffWindowInput] = Field(min_length=2, max_length=100)

    @model_validator(mode="after")
    def validate_full_daily_coverage(self):
        grouped = defaultdict(list)
        for item in self.tariffs:
            grouped[item.day_type].append(item)
        if set(grouped) != {"WEEKDAY", "WEEKEND"}:
            raise ValueError("tariffs must cover both WEEKDAY and WEEKEND")
        for day_type, windows in grouped.items():
            cursor = "00:00"
            for window in sorted(windows, key=lambda item: item.start_time):
                if window.end_time <= window.start_time:
                    raise ValueError(f"{day_type} tariff end_time must be later than start_time")
                if window.start_time != cursor:
                    issue = "overlap" if window.start_time < cursor else "gap"
                    raise ValueError(f"{day_type} tariffs contain a {issue} at {cursor}")
                cursor = window.end_time
            if cursor != "24:00":
                raise ValueError(f"{day_type} tariffs must cover through 24:00")
        return self


def _admin_rows(sql, params=()):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Admin database is unavailable") from exc
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(sql, params)
            return cursor.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not load admin data") from exc
    finally:
        connection.close()


@router.get("/clusters")
def get_clusters(_admin: AuthUser = Depends(require_roles("ADMIN"))):
    rows = _admin_rows("""
        SELECT c.cluster_id, c.name, c.province, c.timezone, c.status, c.grid_limit_kw,
               COALESCE(t.tariffs, '[]') AS tariffs
        FROM grid_cluster c
        LEFT JOIN LATERAL (
            SELECT jsonb_agg(jsonb_build_object(
                'day_type', day_type, 'band', band, 'source_ref', source_ref,
                'start_time', left(start_time::text, 5), 'end_time', left(end_time::text, 5),
                'price_vnd_kwh', price_vnd_kwh
            ) ORDER BY day_type, start_time) AS tariffs
            FROM tariff_window
            WHERE cluster_id = c.cluster_id AND CURRENT_DATE BETWEEN valid_from AND valid_to
        ) t ON TRUE
        ORDER BY c.cluster_id
    """)
    return {"count": len(rows), "data": rows}


@router.get("/stations")
def get_admin_stations(
    status: Literal["PENDING", "ACTIVE", "MAINTENANCE", "OFFLINE"] | None = None,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    rows = _admin_rows("""
        SELECT station_id, cluster_id, name, address, province, lat, lng,
               status, verified, station_power_kw
        FROM charging_station
        WHERE (%s IS NULL OR status = %s)
        ORDER BY station_id
    """, (status, status))
    return {"count": len(rows), "data": rows}


@router.patch("/clusters/{cluster_id}")
def update_cluster_grid_limit(
    cluster_id: int,
    body: ClusterGridLimitPatch,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Admin database is unavailable") from exc
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "UPDATE grid_cluster SET grid_limit_kw = %s WHERE cluster_id = %s AND status = 'ACTIVE' RETURNING cluster_id, grid_limit_kw",
                    (body.grid_limit_kw, cluster_id),
                )
                row = cursor.fetchone()
                if row is None:
                    raise HTTPException(status_code=404, detail="Active grid cluster not found")
                result = {"cluster_id": int(row["cluster_id"]), "grid_limit_kw": float(row["grid_limit_kw"])}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not update grid cluster") from exc
    finally:
        connection.close()
    try:
        run = trigger_cluster_reoptimize(cluster_id, trigger_type="GRID_LIMIT_CHANGED")
    except AIUpstreamError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    result["optimization_status"] = run.status.value
    return result


@router.patch("/stations/{station_id}/verify")
def verify_station(
    station_id: int,
    body: StationVerifyPatch,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Admin database is unavailable") from exc
    cluster_id = None
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT station_id, cluster_id, lat, lng FROM charging_station WHERE station_id = %s FOR UPDATE",
                    (station_id,),
                )
                station = cursor.fetchone()
                if station is None:
                    raise HTTPException(status_code=404, detail="Charging station not found")
                if body.verified and (station["lat"] is None or station["lng"] is None):
                    raise HTTPException(status_code=409, detail="A station needs both latitude and longitude before verification")
                cursor.execute(
                    "UPDATE charging_station SET verified = %s, status = %s WHERE station_id = %s RETURNING status",
                    (body.verified, "ACTIVE" if body.verified else "PENDING", station_id),
                )
                row = cursor.fetchone()
                cluster_id = int(station["cluster_id"])
                status = row["status"]
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not update station verification") from exc
    finally:
        connection.close()
    try:
        run = trigger_cluster_reoptimize(cluster_id, trigger_type="STATION_VERIFIED" if body.verified else "STATION_UNVERIFIED")
    except AIUpstreamError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return {"station_id": station_id, "verified": body.verified, "status": status, "optimization_status": run.status.value}


@router.put("/clusters/{cluster_id}/tariffs")
def replace_cluster_tariffs(
    cluster_id: int,
    body: TariffSet,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Admin database is unavailable") from exc
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute("SELECT cluster_id FROM grid_cluster WHERE cluster_id = %s FOR UPDATE", (cluster_id,))
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=404, detail="Grid cluster not found")
                cursor.execute(
                    "DELETE FROM tariff_window WHERE cluster_id = %s AND valid_to >= CURRENT_DATE",
                    (cluster_id,),
                )
                for tariff in body.tariffs:
                    cursor.execute(
                        """
                        INSERT INTO tariff_window (
                            cluster_id, day_type, band, source_ref, start_time, end_time,
                            price_vnd_kwh, valid_from, valid_to
                        ) VALUES (%s, %s, %s, 'ADMIN_CONFIGURED', %s, %s, %s, CURRENT_DATE, DATE '2099-12-31')
                        """,
                        (cluster_id, tariff.day_type, tariff.band, tariff.start_time, tariff.end_time, tariff.price_vnd_kwh),
                    )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not replace cluster tariffs") from exc
    finally:
        connection.close()
    try:
        run = trigger_cluster_reoptimize(cluster_id, trigger_type="TARIFF_CHANGED")
    except AIUpstreamError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return {"cluster_id": cluster_id, "count": len(body.tariffs), "optimization_status": run.status.value}


@router.get("/benchmark")
def get_benchmark(_admin: AuthUser = Depends(require_roles("ADMIN"))):
    report_path = Path(os.getenv("BENCHMARK_REPORT_PATH") or DEFAULT_BENCHMARK_REPORT_PATH)
    if report_path.is_file():
        try:
            payload = json.loads(report_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise HTTPException(status_code=503, detail="benchmark_real.json could not be read") from exc
        return {"source": "benchmark_real.json", "data": payload}

    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Admin database is unavailable") from exc
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                """
                SELECT benchmark_id, scenario_id, run_id, algorithm, repeat_no,
                       metrics_json, measured_at
                FROM benchmark_result
                ORDER BY measured_at DESC, benchmark_id DESC
                LIMIT 1000
                """
            )
            rows = cursor.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not load benchmark results") from exc
    finally:
        connection.close()
    return {"source": "benchmark_result", "count": len(rows), "results": rows}


@router.post("/benchmark/run")
def run_benchmark(
    body: AdminBenchmarkRequest,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    if body.snapshot is None and body.scenario_id == "inline":
        raise HTTPException(status_code=422, detail="Provide a benchmark snapshot or an existing scenario_id")
    ai_url = os.getenv("AI_URL", "").strip().rstrip("/")
    if not ai_url:
        raise HTTPException(status_code=503, detail="AI_URL is not configured")
    try:
        response = httpx.post(f"{ai_url}/ai/benchmark", json=body.model_dump(mode="json"), timeout=120.0)
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=503, detail="AI Engine benchmark timed out") from exc
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="AI Engine is unavailable") from exc
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"AI Engine benchmark returned HTTP {response.status_code}")
    try:
        result = BenchmarkResponse.model_validate(response.json())
    except Exception as exc:
        raise HTTPException(status_code=502, detail="AI Engine returned an invalid benchmark response") from exc
    return result


@router.post("/forecast", response_model=ForecastResponse)
def run_forecast(
    body: AdminForecastRun,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    ai_url = os.getenv("AI_URL", "").strip().rstrip("/")
    if not ai_url:
        raise HTTPException(status_code=503, detail="AI_URL is not configured")
    history = _admin_rows("""
        SELECT date_trunc('hour', s.start_time) AS hour_start, count(*) AS arrivals
        FROM charging_session s JOIN charging_request r ON r.request_id = s.request_id
        WHERE r.cluster_id = %s AND s.is_simulated IS FALSE AND s.start_time <= CURRENT_TIMESTAMP
        GROUP BY 1
        ORDER BY 1 DESC
        LIMIT 672
    """, (body.cluster_id,))
    if not history:
        raise HTTPException(status_code=409, detail="Cụm chưa có lịch sử check-in để dự báo.")
    vietnam = timezone(timedelta(hours=7))
    request = ForecastRequest(
        cluster_id=str(body.cluster_id),
        history=[
            {"hour_start": row["hour_start"].astimezone(vietnam), "arrivals": row["arrivals"]}
            for row in reversed(history)
        ],
        horizon_hours=body.horizon_hours,
        model=body.model,
    )
    try:
        response = httpx.post(
            f"{ai_url}/ai/forecast", json=request.model_dump(mode="json"),
            timeout=AI_TIMEOUT_SECONDS,
        )
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=503, detail="AI Engine forecast timed out") from exc
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="AI Engine is unavailable") from exc
    if response.status_code >= 500 or response.status_code == 429:
        raise HTTPException(status_code=503, detail=f"AI Engine returned HTTP {response.status_code}")
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"AI Engine forecast returned HTTP {response.status_code}")
    try:
        return ForecastResponse.model_validate(response.json())
    except ValueError as exc:
        raise HTTPException(status_code=502, detail="AI Engine returned an invalid forecast response") from exc


@router.get("/forecast")
def get_forecast(
    cluster_id: int | None = None,
    limit: int = 168,
    _admin: AuthUser = Depends(require_roles("ADMIN")),
):
    if not 1 <= limit <= 1000:
        raise HTTPException(status_code=422, detail="limit must be between 1 and 1000")
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Admin database is unavailable") from exc
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                """
                SELECT df.forecast_id, df.cluster_id, df.generated_at, df.hour_start,
                       df.pred_arrivals, fm.model_id, fm.name AS model_name,
                       fm.version AS model_version, fm.algorithm, fm.metrics_json
                FROM demand_forecast df
                LEFT JOIN forecast_model fm ON fm.model_id = df.model_id
                WHERE (%s IS NULL OR df.cluster_id = %s)
                ORDER BY df.hour_start DESC, df.forecast_id DESC
                LIMIT %s
                """,
                (cluster_id, cluster_id, limit),
            )
            rows = cursor.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not load forecast data") from exc
    finally:
        connection.close()
    return {"count": len(rows), "forecasts": rows}
