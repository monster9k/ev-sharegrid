# backend/routes/requests.py
import os
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
import pandas as pd

try:
    from backend.db import connect, dict_cursor
except ModuleNotFoundError:  # Support `python backend/main.py` as well as package imports.
    from db import connect, dict_cursor

router = APIRouter(prefix="/api/v1", tags=["User Requests & Stations"])

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA_DIR = os.path.join(BASE_DIR, "data")


class BookingRequestSchema(BaseModel):
    user_id: int
    vehicle_id: int
    station_id: int
    arrival_time: str
    departure_time: str
    soc_now: float
    soc_target: float
    idempotency_key: str


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
def create_booking_request(req: BookingRequestSchema):
    """Xác thực 4 điều kiện logic và tạo yêu cầu + outbox event trong 1 DB Transaction"""
    # 1. Kiểm tra SOC
    if req.soc_now >= req.soc_target or req.soc_target > 100 or req.soc_now < 0:
        raise HTTPException(status_code=400, detail="Mức pin hiện tại (soc_now) phải nhỏ hơn mức pin mục tiêu (soc_target) và nằm trong khoảng [0, 100]")

    # 2. Kiểm tra cửa sổ thời gian
    try:
        arr_dt = datetime.fromisoformat(req.arrival_time)
        dep_dt = datetime.fromisoformat(req.departure_time)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Định dạng thời gian ISO 8601 không hợp lệ: {str(e)}")

    if dep_dt <= arr_dt:
        raise HTTPException(status_code=400, detail="Thời gian rời đi (departure_time) phải sau thời gian đến (arrival_time)")

    conn = connect()
    cur = conn.cursor()
    try:
        # Lấy thông số pin xe snapshot
        cur.execute("""
            SELECT vm.battery_kwh, vm.max_kw, s.cluster_id
            FROM vehicle v
            JOIN vehicle_model vm ON v.model_id = vm.model_id
            JOIN charging_station s ON s.station_id = %s
            WHERE v.vehicle_id = %s;
        """, (req.station_id, req.vehicle_id))
        row = cur.fetchone()
        if not row:
            # Fallback nếu xe chưa có trong bảng vehicle
            cur.execute("SELECT cluster_id FROM charging_station WHERE station_id = %s;", (req.station_id,))
            st_row = cur.fetchone()
            cluster_id = st_row[0] if st_row else 1
            battery_kwh, max_kw = 42.0, 60.0
        else:
            battery_kwh, max_kw, cluster_id = row

        energy_needed = round(((req.soc_target - req.soc_now) / 100.0) * float(battery_kwh) / 0.90, 4)

        # INSERT vào charging_request
        cur.execute("""
            INSERT INTO charging_request (
                user_id, vehicle_id, cluster_id, station_id, idempotency_key,
                arrival_time, departure_time, soc_now, soc_target,
                battery_kwh_snapshot, max_kw_snapshot, energy_needed_kwh, status
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'PENDING')
            RETURNING request_id;
        """, (req.user_id, req.vehicle_id, cluster_id, req.station_id, req.idempotency_key,
              arr_dt, dep_dt, req.soc_now, req.soc_target, battery_kwh, max_kw, energy_needed))

        request_id = cur.fetchone()[0]

        # INSERT vào outbox_event (Phụ lục C - Chống mất sự kiện)
        cur.execute("""
            INSERT INTO outbox_event (cluster_id, aggregate_type, aggregate_id, event_type, payload_json, dedupe_key)
            VALUES (%s, 'CHARGING_REQUEST', %s, 'NEW_BOOKING', %s, %s);
        """, (cluster_id, request_id, f'{{"request_id": {request_id}}}', req.idempotency_key))

        conn.commit()
        cur.close()
        conn.close()
        return {
            "status": "accepted",
            "request_id": request_id,
            "energy_needed_kwh": energy_needed,
            "message": "Yêu cầu đặt sạc đã lưu vào DB và phát ra Outbox Event cho AI Engine!"
        }
    except Exception as e:
        conn.rollback()
        cur.close()
        conn.close()
        raise HTTPException(status_code=500, detail=str(e))
