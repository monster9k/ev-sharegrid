# backend/routes/requests.py
import os
import hashlib
import json
from collections.abc import Mapping
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field, model_validator
import pandas as pd

try:
    from backend.auth import AuthUser, require_roles
    from backend.db import connect, dict_cursor
    from backend.ai_contract import AIUpstreamError, pick_request_result, trigger_cluster_reoptimize
except ModuleNotFoundError:  # Support `python backend/main.py` as well as package imports.
    from auth import AuthUser, require_roles
    from db import connect, dict_cursor
    from ai_contract import AIUpstreamError, pick_request_result, trigger_cluster_reoptimize

router = APIRouter(prefix="/api/v1", tags=["User Requests & Stations"])

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.path.join(BASE_DIR, "data")


class BookingRequestSchema(BaseModel):
    user_id: int
    vehicle_id: int
    station_id: int
    arrival_time: datetime
    departure_time: datetime
    soc_now: float = Field(ge=0, lt=100)
    soc_target: float = Field(gt=0, le=100)
    idempotency_key: str = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def validate_booking(self):
        if self.soc_now >= self.soc_target:
            raise ValueError("soc_now must be less than soc_target")
        if self.arrival_time.tzinfo is None or self.departure_time.tzinfo is None:
            raise ValueError("arrival_time and departure_time must include a timezone")
        if self.departure_time <= self.arrival_time:
            raise ValueError("departure_time must be after arrival_time")
        return self


@router.get("/vehicle-models")
def get_vehicle_models():
    """Lấy danh mục 19 mẫu xe điện thực tế từ khảo sát của Ánh"""
    try:
        conn = connect()
        cur = dict_cursor(conn)
        cur.execute("""
            SELECT model_id, brand, model_name, vehicle_type, connector_type,
                   battery_kwh, max_kw, max_ac_kw, max_dc_kw, standard_charger_kw, source_ref, data_note
            FROM vehicle_model
            ORDER BY model_id ASC;
        """)
        models = cur.fetchall()
        cur.close()
        conn.close()
        return {"status": "success", "count": len(models), "data": models}
    except Exception:
        # Fallback đọc từ file CSV đã làm sạch
        csv_path = os.path.join(DATA_DIR, "vehicle_model_cleaned.csv")
        if os.path.exists(csv_path):
            df = pd.read_csv(csv_path)
            return {"status": "success", "count": len(df), "data": df.to_dict("records")}
        raise HTTPException(status_code=500, detail="Không thể truy vấn danh mục mẫu xe điện")


@router.get("/stations")
def get_stations(
    lat: Optional[float] = None,
    lng: Optional[float] = None,
    radius_km: float = 25.0,
    status: Optional[str] = None
):
    """Tìm trạm sạc gần vị trí người dùng bằng hàm không gian PostGIS ST_DWithin hoặc lấy toàn bộ trạm"""
    try:
        conn = connect()
        cur = dict_cursor(conn)

        if lat is not None and lng is not None:
            # Truy vấn không gian PostGIS
            query = """
                SELECT station_id, cluster_id, name, address, province, area_label,
                       supported_vehicle_type, status, verified, lat, lng,
                       station_power_kw, service_fee_vnd, rating, listed_network, listed_port_count,
                       ST_Distance(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography) / 1000.0 as distance_km
                FROM charging_station
                WHERE location IS NOT NULL
                  AND (%s IS NULL OR status = %s)
                  AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s * 1000)
                ORDER BY distance_km ASC;
            """
            cur.execute(query, (lng, lat, status, status, lng, lat, radius_km))
        else:
            # Lấy danh sách trạm tổng thể
            query = """
                SELECT station_id, cluster_id, name, address, province, area_label,
                       supported_vehicle_type, status, verified, lat, lng,
                       station_power_kw, service_fee_vnd, rating, listed_network, listed_port_count
                FROM charging_station
                WHERE (%s IS NULL OR status = %s)
                ORDER BY verified DESC, station_id ASC;
            """
            cur.execute(query, (status, status))

        stations = cur.fetchall()
        cur.close()
        conn.close()
        return {"status": "success", "count": len(stations), "data": stations}
    except Exception as e:
        # Fallback đọc từ file CSV
        csv_path = os.path.join(DATA_DIR, "charging_station_cleaned.csv")
        if os.path.exists(csv_path):
            df = pd.read_csv(csv_path)
            if status:
                df = df[df["status"] == status]
            return {"status": "success", "count": len(df), "data": df.to_dict("records")}
        raise HTTPException(status_code=500, detail=f"Lỗi truy vấn trạm sạc: {str(e)}")


@router.get("/stations/{station_id}")
def get_station_detail(station_id: int):
    """Lấy chi tiết trạm sạc và danh sách cổng sạc (port)"""
    try:
        conn = connect()
        cur = dict_cursor(conn)
        cur.execute("SELECT * FROM charging_station WHERE station_id = %s;", (station_id,))
        station = cur.fetchone()
        if not station:
            cur.close()
            conn.close()
            raise HTTPException(status_code=404, detail=f"Không tìm thấy trạm sạc ID {station_id}")

        cur.execute("SELECT * FROM port WHERE station_id = %s ORDER BY port_id ASC;", (station_id,))
        ports = cur.fetchall()
        cur.close()
        conn.close()
        station["ports"] = ports
        return {"status": "success", "data": station}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/requests")
def create_booking_request(
    req: BookingRequestSchema,
    user: AuthUser = Depends(require_roles("USER")),
):
    """Persist a pending request, publish its outbox event, then optimize its cluster."""
    if req.user_id != user.user_id:
        raise HTTPException(status_code=403, detail="A user can only create requests for their own account")
    connection = connect()
    request_id: int
    cluster_id: int
    outbox_event_id: int
    energy_needed_kwh: Decimal
    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT v.vehicle_id, v.user_id, vm.battery_kwh, vm.max_kw
                    FROM vehicle v
                    JOIN vehicle_model vm ON vm.model_id = v.model_id
                    WHERE v.vehicle_id = %s AND v.user_id = %s
                    FOR UPDATE OF v
                    """,
                    (req.vehicle_id, req.user_id),
                )
                vehicle = cursor.fetchone()
                if vehicle is None:
                    raise HTTPException(status_code=404, detail="Vehicle not found for this user")
                battery_kwh = vehicle["battery_kwh"] if isinstance(vehicle, Mapping) else vehicle[2]
                max_kw = vehicle["max_kw"] if isinstance(vehicle, Mapping) else vehicle[3]

                cursor.execute(
                    """
                    SELECT s.station_id, s.cluster_id
                    FROM charging_station s
                    JOIN grid_cluster gc ON gc.cluster_id = s.cluster_id
                    WHERE s.station_id = %s AND s.status = 'ACTIVE' AND gc.status = 'ACTIVE'
                    """,
                    (req.station_id,),
                )
                station = cursor.fetchone()
                if station is None:
                    raise HTTPException(status_code=404, detail="Active charging station not found")
                cluster_id = int(station["cluster_id"] if isinstance(station, Mapping) else station[1])

                cursor.execute(
                    "SELECT request_id FROM charging_request WHERE idempotency_key = %s",
                    (req.idempotency_key,),
                )
                if cursor.fetchone() is not None:
                    raise HTTPException(status_code=409, detail="idempotency_key already exists")

                cursor.execute(
                    """
                    SELECT request_id
                    FROM charging_request
                    WHERE vehicle_id = %s
                      AND status NOT IN ('DONE', 'CANCELLED', 'NO_SHOW', 'FAILED')
                      AND arrival_time < %s
                      AND departure_time > %s
                    LIMIT 1
                    """,
                    (req.vehicle_id, req.departure_time, req.arrival_time),
                )
                if cursor.fetchone() is not None:
                    raise HTTPException(
                        status_code=409,
                        detail="This vehicle already has a charging request overlapping that time window",
                    )

                soc_now = Decimal(str(req.soc_now))
                soc_target = Decimal(str(req.soc_target))
                eta = Decimal("0.90")
                cursor.execute(
                    """
                    INSERT INTO charging_request (
                        user_id, vehicle_id, cluster_id, station_id, idempotency_key,
                        arrival_time, departure_time, soc_now, soc_target,
                        battery_kwh_snapshot, max_kw_snapshot, eta, energy_needed_kwh, status
                    ) VALUES (
                        %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                        ((%s::numeric - %s::numeric) / 100 * %s::numeric) / %s::numeric,
                        'PENDING'
                    )
                    RETURNING request_id, cluster_id, energy_needed_kwh
                    """,
                    (
                        req.user_id,
                        req.vehicle_id,
                        cluster_id,
                        req.station_id,
                        req.idempotency_key,
                        req.arrival_time,
                        req.departure_time,
                        soc_now,
                        soc_target,
                        battery_kwh,
                        max_kw,
                        eta,
                        soc_target,
                        soc_now,
                        battery_kwh,
                        eta,
                    ),
                )
                inserted = cursor.fetchone()
                if isinstance(inserted, Mapping):
                    request_id = int(inserted["request_id"])
                    cluster_id = int(inserted["cluster_id"])
                    energy_needed_kwh = inserted["energy_needed_kwh"]
                else:
                    request_id, cluster_id, energy_needed_kwh = inserted
                    request_id, cluster_id = int(request_id), int(cluster_id)

                dedupe = "booking:" + hashlib.sha256(req.idempotency_key.encode("utf-8")).hexdigest()
                cursor.execute(
                    """
                    INSERT INTO outbox_event (
                        cluster_id, aggregate_type, aggregate_id, event_type, payload_json, dedupe_key
                    ) VALUES (%s, 'CHARGING_REQUEST', %s, 'NEW_BOOKING', %s::jsonb, %s)
                    RETURNING event_id
                    """,
                    (
                        cluster_id,
                        request_id,
                        json.dumps({"request_id": request_id}),
                        dedupe,
                    ),
                )
                event_row = cursor.fetchone()
                outbox_event_id = int(event_row[0] if not isinstance(event_row, Mapping) else event_row["event_id"])
    except HTTPException:
        raise
    except Exception as exc:
        if getattr(exc, "pgcode", None) == "23505":
            raise HTTPException(status_code=409, detail="A request with this idempotency key already exists") from exc
        raise HTTPException(status_code=500, detail="Could not create charging request") from exc
    finally:
        connection.close()

    try:
        result = trigger_cluster_reoptimize(
            cluster_id,
            new_request_ids={request_id},
            trigger_event_id=outbox_event_id,
        )
        picked = pick_request_result(result, request_id)
    except AIUpstreamError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail) from exc
    except LookupError as exc:
        raise HTTPException(
            status_code=502,
            detail=f"AI Engine omitted the new request result; request {request_id} remains PENDING",
        ) from exc
    return {
        **picked,
        "request_id": request_id,
        "energy_needed_kwh": float(energy_needed_kwh),
        "status": "accepted",
    }


@router.get("/requests/{request_id}/schedule")
def get_request_schedule(
    request_id: int,
    user: AuthUser = Depends(require_roles("USER")),
):
    """Return the request's active 15-minute Gantt slots."""
    connection = connect()
    try:
        with dict_cursor(connection) as cursor:
            cursor.execute(
                """
                SELECT cr.request_id, cr.status, cr.energy_needed_kwh, cr.shortfall_kwh,
                       sc.port_id, sc.slot_start, sc.power_kw, sc.version
                FROM charging_request cr
                LEFT JOIN schedule sc
                  ON sc.request_id = cr.request_id AND sc.is_active = TRUE
                WHERE cr.request_id = %s AND cr.user_id = %s
                ORDER BY sc.slot_start, sc.schedule_id
                """,
                (request_id, user.user_id),
            )
            rows = cursor.fetchall()
            if not rows:
                raise HTTPException(status_code=404, detail="Charging request not found")
            first = rows[0]
            slots = []
            for row in rows:
                if row["slot_start"] is None:
                    continue
                slot_start = row["slot_start"]
                slots.append({
                    "slot_start": slot_start.isoformat(),
                    "slot_end": (slot_start + timedelta(minutes=15)).isoformat(),
                    "port_id": int(row["port_id"]),
                    "power_kw": float(row["power_kw"]),
                    "version": int(row["version"]),
                })
            return {
                "request_id": int(first["request_id"]),
                "status": first["status"],
                "slot_minutes": 15,
                "energy_needed_kwh": float(first["energy_needed_kwh"]),
                "shortfall_kwh": float(first["shortfall_kwh"] or 0),
                "slots": slots,
            }
    finally:
        connection.close()
