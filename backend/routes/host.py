"""Host station and port management with owner-scoped queries."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import time, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator

from backend.ai_contract import AIUpstreamError, trigger_cluster_reoptimize
from backend.auth import AuthUser, require_roles
from backend.db import connect, dict_cursor


router = APIRouter(prefix="/api/v1/host", tags=["Host Portal"])
Connector = Literal["CCS2", "Type2", "CHAdeMO", "AC_HOME"]
ControlType = Literal["CONTINUOUS", "ON_OFF_SWITCH"]


def _value(row, name: str, index: int):
    return row[name] if isinstance(row, Mapping) else row[index]


class HostStationCreate(BaseModel):
    cluster_id: int = Field(gt=0)
    name: str = Field(min_length=1, max_length=100)
    address: str = Field(min_length=1)
    province: str = Field(min_length=1, max_length=50)
    area_label: str | None = Field(default=None, max_length=50)
    supported_vehicle_type: Literal["ALL", "CAR", "MOTORBIKE"] = "ALL"
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    open_time: time = time(0)
    close_time: time = time(0)
    is_24h: bool = True
    station_power_kw: float = Field(gt=0, le=100_000)
    service_fee_vnd: float = Field(default=0, ge=0, le=10_000_000)

    @model_validator(mode="after")
    def validate_station_hours_and_location(self):
        if (self.lat is None) != (self.lng is None):
            raise ValueError("lat and lng must be supplied together")
        if not self.is_24h and self.open_time == self.close_time:
            raise ValueError("non-24h station open_time and close_time must differ")
        return self


class HostPortCreate(BaseModel):
    port_code: str = Field(min_length=1, max_length=20)
    connector_type: Connector
    control_type: ControlType
    min_power_kw: float = Field(default=0, ge=0, le=100_000)
    max_power_kw: float = Field(gt=0, le=100_000)

    @model_validator(mode="after")
    def validate_power(self):
        if self.min_power_kw > self.max_power_kw:
            raise ValueError("min_power_kw must be <= max_power_kw")
        if self.control_type == "ON_OFF_SWITCH" and self.min_power_kw != self.max_power_kw:
            raise ValueError("ON_OFF_SWITCH requires min_power_kw == max_power_kw")
        return self


class PortStatusPatch(BaseModel):
    status: Literal["MAINTENANCE", "OFFLINE"]


@router.post("/stations", status_code=201)
def create_host_station(
    body: HostStationCreate,
    user: AuthUser = Depends(require_roles("HOST")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Station database is unavailable") from exc
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT cluster_id FROM grid_cluster WHERE cluster_id = %s AND status = 'ACTIVE' FOR SHARE",
                    (body.cluster_id,),
                )
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=404, detail="Active grid cluster not found")
                cursor.execute(
                    """
                    INSERT INTO charging_station (
                        cluster_id, owner_id, name, address, province, area_label,
                        supported_vehicle_type, status, lat, lng, location,
                        open_time, close_time, is_24h, verified,
                        station_power_kw, service_fee_vnd
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, 'PENDING', %s, %s,
                        CASE WHEN %s IS NULL THEN NULL
                             ELSE ST_SetSRID(ST_MakePoint(%s, %s), 4326) END,
                        %s, %s, %s, FALSE, %s, %s
                    )
                    RETURNING station_id, status, verified
                    """,
                    (
                        body.cluster_id, user.user_id, body.name.strip(), body.address.strip(),
                        body.province.strip(), body.area_label, body.supported_vehicle_type,
                        body.lat, body.lng, body.lat, body.lng, body.lat, body.lng,
                        body.open_time, body.close_time, body.is_24h,
                        body.station_power_kw, body.service_fee_vnd,
                    ),
                )
                row = cursor.fetchone()
                return {
                    "station_id": int(_value(row, "station_id", 0)),
                    "status": _value(row, "status", 1),
                    "verified": bool(_value(row, "verified", 2)),
                }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not create station") from exc
    finally:
        connection.close()


@router.post("/stations/{station_id}/ports", status_code=201)
def add_host_port(
    station_id: int,
    body: HostPortCreate,
    user: AuthUser = Depends(require_roles("HOST")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Station database is unavailable") from exc
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    "SELECT station_id FROM charging_station WHERE station_id = %s AND owner_id = %s FOR UPDATE",
                    (station_id, user.user_id),
                )
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=404, detail="Station not found")
                cursor.execute(
                    """
                    INSERT INTO port (station_id, port_code, connector_type, control_type, status, min_power_kw, max_power_kw)
                    VALUES (%s, %s, %s, %s, 'ACTIVE', %s, %s)
                    RETURNING port_id, status
                    """,
                    (
                        station_id, body.port_code.strip(), body.connector_type,
                        body.control_type, body.min_power_kw, body.max_power_kw,
                    ),
                )
                row = cursor.fetchone()
                return {"port_id": int(_value(row, "port_id", 0)), "status": _value(row, "status", 1)}
    except HTTPException:
        raise
    except Exception as exc:
        if getattr(exc, "pgcode", None) == "23505":
            raise HTTPException(status_code=409, detail="port_code already exists at this station") from exc
        raise HTTPException(status_code=503, detail="Could not add station port") from exc
    finally:
        connection.close()


@router.patch("/ports/{port_id}/status")
def update_host_port_status(
    port_id: int,
    body: PortStatusPatch,
    user: AuthUser = Depends(require_roles("HOST")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Station database is unavailable") from exc
    cluster_id = None
    try:
        with connection:
            with dict_cursor(connection) as cursor:
                cursor.execute(
                    """
                    UPDATE port p SET status = %s
                    FROM charging_station s
                    WHERE p.port_id = %s AND p.station_id = s.station_id AND s.owner_id = %s
                    RETURNING p.port_id, p.status, s.cluster_id
                    """,
                    (body.status, port_id, user.user_id),
                )
                row = cursor.fetchone()
                if row is None:
                    raise HTTPException(status_code=404, detail="Port not found")
                cluster_id = int(_value(row, "cluster_id", 2))
                status = _value(row, "status", 1)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not update port status") from exc
    finally:
        connection.close()
    try:
        result = trigger_cluster_reoptimize(cluster_id, trigger_type="PORT_FAULT")
    except AIUpstreamError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    return {"port_id": port_id, "status": status, "optimization_status": result.status.value}


@router.get("/stations/{station_id}/schedule")
def get_host_station_schedule(
    station_id: int,
    user: AuthUser = Depends(require_roles("HOST")),
):
    try:
        connection = connect()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Station database is unavailable") from exc
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                "SELECT station_id FROM charging_station WHERE station_id = %s AND owner_id = %s",
                (station_id, user.user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Station not found")
            cursor.execute(
                """
                SELECT sc.schedule_id, sc.request_id, sc.port_id, sc.slot_start,
                       sc.power_kw, sc.version
                FROM schedule sc
                JOIN port p ON p.port_id = sc.port_id
                WHERE p.station_id = %s AND sc.is_active = TRUE
                ORDER BY sc.slot_start, sc.port_id, sc.request_id
                """,
                (station_id,),
            )
            rows = cursor.fetchall()
            slots = [
                {
                    "schedule_id": int(row["schedule_id"]),
                    "request_id": int(row["request_id"]),
                    "port_id": int(row["port_id"]),
                    "slot_start": row["slot_start"].isoformat(),
                    "slot_end": (row["slot_start"] + timedelta(minutes=15)).isoformat(),
                    "power_kw": float(row["power_kw"]),
                    "version": int(row["version"]),
                }
                for row in rows
            ]
            return {"station_id": station_id, "slot_minutes": 15, "slots": slots}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Could not load station schedule") from exc
    finally:
        connection.close()
