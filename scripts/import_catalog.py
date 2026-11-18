# scripts/import_catalog.py
import psycopg2
from psycopg2.extras import execute_values
import pandas as pd

DB_CONFIG = {
    "dbname": "ev_sharegrid",
    "user": "postgres",
    "password": "password",
    "host": "localhost",
    "port": 5432
}

def seed_catalog_data():
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    print("🚀 Đang nạp dữ liệu 7 bảng Catalog gốc vào PostgreSQL...")

    # 1. app_user (Tạo tài khoản HOST và ADMIN mẫu)
    users = [
        (1, 'ADMIN', 'Quản trị Hệ thống', 'admin@sharegrid.vn', '0901000001', 100.00, 'ACTIVE'),
        (2, 'HOST', 'Nguyễn Văn Chủ Trạm', 'host1@sharegrid.vn', '0901000002', 98.50, 'ACTIVE')
    ]
    cur.executemany("""
        INSERT INTO app_user (user_id, role, full_name, email, phone, reliability_score, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s) ON CONFLICT (user_id) DO NOTHING;
    """, users)

    # 2. vehicle_model (Mẫu xe thực tế)
    models = [
        (1, 'VinFast', 'VF 5 Plus', 'CAR', 'CCS2', 'REAL', 'vinfastauto.com', 37.230, 7.400),
        (2, 'VinFast', 'VF e34', 'CAR', 'CCS2', 'REAL', 'vinfastauto.com', 41.900, 11.000),
        (3, 'VinFast', 'VF 8 Eco', 'CAR', 'CCS2', 'REAL', 'vinfastauto.com', 87.700, 11.000),
        (4, 'VinFast', 'Feliz S', 'MOTORBIKE', 'AC_HOME', 'REAL', 'vinfastauto.com', 3.500, 1.000),
        (5, 'BYD', 'Atto 3', 'CAR', 'Type2', 'REAL', 'byd.com', 60.480, 7.000),
        (6, 'Hyundai', 'Ioniq 5', 'CAR', 'CCS2', 'REAL', 'hyundai.com', 72.600, 11.000)
    ]
    cur.executemany("""
        INSERT INTO vehicle_model (model_id, brand, model_name, vehicle_type, connector_type, source_type, source_ref, battery_kwh, max_kw)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT (model_id) DO NOTHING;
    """, models)

    # 3. charging_station (Trạm sạc mẫu Đà Nẵng & tính tọa độ PostGIS location)
    stations = [
        (10, 1, 2, 'Trạm ShareGrid Bạch Đằng', '120 Bạch Đằng, Hải Châu', 'Đà Nẵng', 'ALL', 'ACTIVE', 16.068100, 108.224500, '06:00', '23:00', False, True, 22.000, 5000.00),
        (11, 1, 2, 'Trạm ShareGrid Nguyễn Văn Linh', '85 Nguyễn Văn Linh, Hải Châu', 'Đà Nẵng', 'CAR', 'ACTIVE', 16.060500, 108.215200, '00:00', '23:59', True, True, 40.000, 10000.00)
    ]
    for st in stations:
        cur.execute("""
            INSERT INTO charging_station (
                station_id, cluster_id, owner_id, name, address, province, supported_vehicle_type,
                status, lat, lng, location, open_time, close_time, is_24h, verified, station_power_kw, service_fee_vnd
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326), %s, %s, %s, %s, %s, %s)
            ON CONFLICT (station_id) DO NOTHING;
        """, (st[0], st[1], st[2], st[3], st[4], st[5], st[6], st[7], st[8], st[9], st[9], st[8], st[10], st[11], st[12], st[13], st[14], st[15]))

    # 4. port (Cổng sạc trong trạm)
    ports = [
        (1001, 10, 'P1', 'CCS2', 'CONTINUOUS', 'ACTIVE', 1.400, 7.400),
        (1002, 10, 'P2', 'CCS2', 'CONTINUOUS', 'ACTIVE', 1.400, 7.400),
        (1003, 10, 'P3', 'AC_HOME', 'ON_OFF_SWITCH', 'ACTIVE', 2.200, 2.200),
        (1004, 11, 'P1', 'CCS2', 'CONTINUOUS', 'ACTIVE', 2.000, 20.000),
        (1005, 11, 'P2', 'CCS2', 'CONTINUOUS', 'ACTIVE', 2.000, 20.000)
    ]
    cur.executemany("""
        INSERT INTO port (port_id, station_id, port_code, connector_type, control_type, status, min_power_kw, max_power_kw)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s) ON CONFLICT (port_id) DO NOTHING;
    """, ports)

    # 5. tariff_window (Biểu giá điện 3 khung giờ EVN)
    tariffs = [
        (1, 1, 'WEEKDAY', 'OFF_PEAK', '00:00', '04:00', 1600.00),
        (2, 1, 'WEEKDAY', 'NORMAL', '04:00', '09:30', 2400.00),
        (3, 1, 'WEEKDAY', 'PEAK', '09:30', '11:30', 4000.00),
        (4, 1, 'WEEKDAY', 'NORMAL', '11:30', '17:00', 2400.00),
        (5, 1, 'WEEKDAY', 'PEAK', '17:00', '20:00', 4000.00),
        (6, 1, 'WEEKDAY', 'NORMAL', '20:00', '22:00', 2400.00),
        (7, 1, 'WEEKDAY', 'OFF_PEAK', '22:00', '24:00', 1600.00)
    ]
    cur.executemany("""
        INSERT INTO tariff_window (tariff_id, cluster_id, day_type, band, start_time, end_time, price_vnd_kwh)
        VALUES (%s, %s, %s, %s, %s, %s, %s) ON CONFLICT (tariff_id) DO NOTHING;
    """, tariffs)

    conn.commit()
    cur.close()
    conn.close()
    print("✅ Đã import thành công dữ liệu Catalog gốc (Model, Station, Port, Tariff)!")

if __name__ == "__main__":
    seed_catalog_data()
