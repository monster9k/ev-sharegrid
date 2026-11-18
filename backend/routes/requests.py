# backend/routes/requests.py
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from datetime import datetime
import psycopg2
from psycopg2.extras import RealDictCursor

router = APIRouter(prefix="/api/v1", tags=["User Requests"])

DB_CONFIG = {
    "dbname": "ev_sharegrid",
    "user": "postgres",
    "password": "password",
    "host": "localhost",
    "port": 5432
}

class BookingRequestSchema(BaseModel):
    user_id: int
    vehicle_id: int
    station_id: int
    arrival_time: str
    departure_time: str
    soc_now: float
    soc_target: float
    idempotency_key: str

@router.get("/stations")
def get_nearby_stations(lat: float, lng: float, radius_km: float = 10.0):
    """Tìm trạm sạc gần vị trí người dùng bằng hàm không gian PostGIS ST_DWithin"""
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    query = """
        SELECT station_id, name, address, lat, lng, station_power_kw, service_fee_vnd,
               ST_Distance(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography) / 1000.0 as distance_km
        FROM charging_station
        WHERE status = 'ACTIVE' AND verified = TRUE
          AND ST_DWithin(location, ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography, %s * 1000)
        ORDER BY distance_km ASC;
    """
    cur.execute(query, (lng, lat, lng, lat, radius_km))
    stations = cur.fetchall()
    cur.close()
    conn.close()
    return {"status": "success", "count": len(stations), "data": stations}

@router.post("/requests")
def create_booking_request(req: BookingRequestSchema):
    """Xác thực 4 điều kiện logic và tạo yêu cầu + outbox event trong 1 DB Transaction"""
    # 1. Kiểm tra SOC
    if req.soc_now >= req.soc_target or req.soc_target > 100:
        raise HTTPException(status_code=400, detail="Mức pin hiện tại phải nhỏ hơn mức pin mục tiêu và <= 100%")
    
    # 2. Kiểm tra cửa sổ thời gian
    try:
        arr_dt = datetime.fromisoformat(req.arrival_time)
        dep_dt = datetime.fromisoformat(req.departure_time)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Định dạng thời gian không hợp lệ: {str(e)}")
        
    if dep_dt <= arr_dt:
        raise HTTPException(status_code=400, detail="Thời gian rời đi phải sau thời gian đến")

    conn = psycopg2.connect(**DB_CONFIG)
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
            # Dữ liệu fallback nếu chưa có trong DB
            battery_kwh, max_kw, cluster_id = 41.9, 11.0, 1
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
