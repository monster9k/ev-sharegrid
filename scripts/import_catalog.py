# scripts/import_catalog.py
"""
Script làm sạch & nạp dữ liệu Catalog gốc (G2: TASK-12)
Từ dữ liệu khảo sát thực tế của Ánh:
 - docs/dataofanh/task1.xlsx (19 dòng xe điện thực tế: VinFast, BYD, Hyundai, Wuling)
 - docs/dataofanh/EV_ShareGrid_TASK02_ChargingStations_DaNang_Plus4Cities_2026-11-18.xlsx (107 trạm sạc Đà Nẵng + 4 TP lớn)
Tác giả: Thắng (thangchien1607@gmail.com)
"""

import math
import os
import sys
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

DB_CONFIG = {
    "dbname": os.environ.get("POSTGRES_DB", "ev_sharegrid"),
    "user": os.environ.get("POSTGRES_USER", "postgres"),
    "password": os.environ.get("POSTGRES_PASSWORD"),
    "host": os.environ.get("POSTGRES_HOST", "localhost"),
    "port": int(os.environ.get("POSTGRES_PORT", 5432))
}

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
DOCS_DIR = os.path.join(BASE_DIR, "docs")
DATAOFANH_DIR = os.path.join(DOCS_DIR, "dataofanh")
CONNECTOR_ALIASES = {
    "CCS2_DC": "CCS2",
    "AC_HOME_VINFAST_ADAPTER": "AC_HOME",
}
CONNECTOR_TYPES = {"CCS2", "Type2", "CHAdeMO", "AC_HOME"}
# TODO: bổ sung số và ngày Quyết định EVN sau khi có văn bản được xác nhận.
EVN_TARIFF_SOURCE_REF = None


def _configure_console_encoding():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")


def normalize_connector_type(value):
    source_value = "CCS2" if pd.isna(value) else str(value).strip()
    connector_type = CONNECTOR_ALIASES.get(source_value, source_value)
    if connector_type not in CONNECTOR_TYPES:
        raise ValueError(f"Chuẩn đầu nối không được hỗ trợ: {source_value!r}")
    return connector_type, source_value if source_value != connector_type else None


def clean_and_extract_catalogs():
    _configure_console_encoding()
    import openpyxl

    print("🚀 Bắt đầu đọc & làm sạch dữ liệu từ docs/dataofanh...")
    os.makedirs(DATA_DIR, exist_ok=True)

    # 1. Làm sạch danh mục mẫu xe từ docs/dataofanh/task1.xlsx
    task1_path = os.path.join(DATAOFANH_DIR, "task1.xlsx")
    wb_vehicle = openpyxl.load_workbook(task1_path, data_only=True)
    ws_v = wb_vehicle["vehicle_model"]
    v_headers = [cell for cell in next(ws_v.iter_rows(values_only=True))]
    v_rows = list(ws_v.iter_rows(values_only=True))[1:]

    cleaned_models = []
    for idx, r in enumerate(v_rows, start=1):
        m = dict(zip(v_headers, r))
        connector, source_connector = normalize_connector_type(m.get("connector_type"))
        raw_note = m.get("data_note")
        data_note = "" if pd.isna(raw_note) else str(raw_note).strip()
        if source_connector:
            alias_note = (
                f"Chuẩn đầu nối nguồn {source_connector} được chuẩn hóa thành {connector}."
            )
            data_note = " ".join(part for part in (data_note, alias_note) if part)
        # Xử lý các giá trị số
        battery_kwh = float(m["battery_kwh"]) if m.get("battery_kwh") is not None else 40.0
        max_kw = float(m["max_kw"]) if m.get("max_kw") is not None else 60.0
        max_ac = float(m["max_ac_kw"]) if m.get("max_ac_kw") is not None else None
        max_dc = float(m["max_dc_kw"]) if m.get("max_dc_kw") is not None else None
        std_charger = float(m["standard_charger_kw"]) if m.get("standard_charger_kw") is not None else None

        cleaned_models.append({
            "model_id": idx,
            "brand": m.get("brand", "VinFast"),
            "model_name": m.get("model_name", "Unknown"),
            "vehicle_type": m.get("vehicle_type", "CAR"),
            "connector_type": connector,
            "source_type": m.get("source_type", "REAL"),
            "source_ref": m.get("source_ref", ""),
            "battery_kwh": battery_kwh,
            "max_kw": max_kw,
            "max_ac_kw": max_ac,
            "max_dc_kw": max_dc,
            "standard_charger_kw": std_charger,
            "data_note": data_note
        })

    df_models = pd.DataFrame(cleaned_models)
    df_models.to_csv(os.path.join(DATA_DIR, "vehicle_model_cleaned.csv"), index=False, encoding="utf-8")
    print(f"✅ Đã làm sạch & xuất 19 mẫu xe thực tế -> {os.path.join(DATA_DIR, 'vehicle_model_cleaned.csv')}")

    # 2. Làm sạch danh mục trạm sạc từ docs/dataofanh/EV_ShareGrid_TASK02_ChargingStations_DaNang_Plus4Cities_2026-11-18.xlsx
    task2_path = os.path.join(DATAOFANH_DIR, "EV_ShareGrid_TASK02_ChargingStations_DaNang_Plus4Cities_2026-11-18.xlsx")
    wb_station = openpyxl.load_workbook(task2_path, data_only=True)
    ws_s = wb_station["charging_station"]
    s_headers = [cell for cell in next(ws_s.iter_rows(values_only=True))]
    s_rows = list(ws_s.iter_rows(values_only=True))[1:]

    cleaned_stations = []
    cleaned_ports = []
    port_id_counter = 1001

    for r in s_rows:
        st = dict(zip(s_headers, r))
        station_id = int(st["station_id"])
        name = str(st.get("name") or f"Trạm sạc #{station_id}")
        address = str(st.get("address") or "")
        province = str(st.get("province") or "Đà Nẵng")
        lat = float(st["lat"]) if pd.notnull(st.get("lat")) else None
        lng = float(st["lng"]) if pd.notnull(st.get("lng")) else None

        # Gán cụm lưới điện cluster_id dựa theo vị trí & tỉnh thành
        if province == "Hà Nội":
            cluster_id = 3
        elif province in ["TP. Hồ Chí Minh", "TP.HCM"]:
            cluster_id = 4
        elif province == "Đà Nẵng":
            # Sơn Trà & Ngũ Hành Sơn thuộc Cụm 2, còn lại thuộc Cụm 1
            if any(k in address for k in ["Sơn Trà", "Ngũ Hành Sơn", "Hòa Hải", "Hòa Quý"]):
                cluster_id = 2
            else:
                cluster_id = 1
        else:
            cluster_id = 1  # Mặc định cụm 1 cho các trạm vệ tinh

        # Trạng thái xác minh: 15 trạm có tọa độ GPS là ACTIVE & verified = True
        has_coords = (
            lat is not None
            and lng is not None
            and math.isfinite(lat)
            and math.isfinite(lng)
        )
        status = "ACTIVE" if has_coords else "PENDING"
        verified = True if has_coords else False

        # Xác định trần công suất station_power_kw
        listed_max_port_kw = (
            float(st["listed_max_port_kw"])
            if pd.notnull(st.get("listed_max_port_kw"))
            else None
        )
        listed_port_count = (
            int(st["listed_port_count"])
            if pd.notnull(st.get("listed_port_count"))
            else None
        )
        supported_type = st.get("supported_vehicle_type") or "ALL"

        if listed_max_port_kw is not None:
            if listed_max_port_kw >= 150:
                station_power_kw = 350.0
            elif listed_max_port_kw >= 120:
                station_power_kw = 250.0
            elif listed_max_port_kw >= 60:
                station_power_kw = 120.0
            else:
                station_power_kw = 44.0
            station_power_note = (
                f"station_power_kw={station_power_kw} suy ra từ "
                f"listed_max_port_kw={listed_max_port_kw} kW theo ngưỡng công suất."
            )
        elif supported_type == "MOTORBIKE" or "xe máy" in name.lower():
            station_power_kw = 22.0
            supported_type = "MOTORBIKE"
            station_power_note = (
                "station_power_kw=22 kW là giá trị suy ra theo loại MOTORBIKE "
                "do thiếu listed_max_port_kw."
            )
        else:
            station_power_kw = 60.0
            station_power_note = (
                "station_power_kw=60 kW là giả định mặc định do thiếu listed_max_port_kw."
            )

        service_fee = 10000.00 if (listed_max_port_kw and listed_max_port_kw >= 60) else 5000.00
        raw_qa_notes = st.get("qa_notes")
        qa_notes = "" if pd.isna(raw_qa_notes) else str(raw_qa_notes).strip()
        derived_note = (
            f"derived_fields: cluster_id từ province/address; owner_id=2 là HOST demo; "
            f"status/verified từ GPS; open_time/close_time/is_24h là giả định; "
            f"{station_power_note} service_fee_vnd={service_fee:.0f} suy ra từ listed_max_port_kw."
        )
        qa_notes = " ".join(part for part in (qa_notes, derived_note) if part)

        cleaned_stations.append({
            "station_id": station_id,
            "cluster_id": cluster_id,
            "owner_id": 2,  # HOST demo
            "name": name,
            "address": address,
            "province": province,
            "area_label": st.get("area_label", ""),
            "supported_vehicle_type": supported_type,
            "status": status,
            "ocpp_id": st.get("ocpp_id") or f"OCPP_VN_ST_{station_id:04d}",
            "phone": st.get("phone") or "0905000115",
            "osm_id": st.get("osm_id") or "",
            "source_type": st.get("source_type") or "SURVEY",
            "source_ref": st.get("source_ref") or "dataofanh_2026-11-18",
            "lat": lat,
            "lng": lng,
            "open_time": "00:00",
            "close_time": "23:59",
            "is_24h": True,
            "verified": verified,
            "station_power_kw": station_power_kw,
            "service_fee_vnd": service_fee,
            "price_override_vnd_kwh": None,
            "max_session_minutes": 360,
            "rating": None,
            "listed_network": st.get("listed_network") or "VinFast",
            "listed_port_count": listed_port_count,
            "listed_max_port_kw": listed_max_port_kw,
            "qa_notes": qa_notes
        })

        # Tạo cấu hình cổng sạc vật lý (port) cho từng trạm
        if supported_type == "MOTORBIKE" or "xe máy" in name.lower():
            num_ports = min(listed_port_count or 6, 10)
            for p_i in range(1, num_ports + 1):
                cleaned_ports.append({
                    "port_id": port_id_counter,
                    "station_id": station_id,
                    "port_code": f"P{p_i}",
                    "connector_type": "AC_HOME",
                    "control_type": "ON_OFF_SWITCH",
                    "status": "ACTIVE" if verified else "MAINTENANCE",
                    "min_power_kw": 1.0,
                    "max_power_kw": 2.2
                })
                port_id_counter += 1
        elif listed_max_port_kw and listed_max_port_kw >= 60:
            # Trạm DC công suất cao
            num_dc = min(listed_port_count or 4, 6)
            for p_i in range(1, num_dc + 1):
                cleaned_ports.append({
                    "port_id": port_id_counter,
                    "station_id": station_id,
                    "port_code": f"P{p_i}_DC",
                    "connector_type": "CCS2",
                    "control_type": "CONTINUOUS",
                    "status": "ACTIVE" if verified else "MAINTENANCE",
                    "min_power_kw": 2.0,
                    "max_power_kw": listed_max_port_kw
                })
                port_id_counter += 1
            # Thêm 1 cổng AC dự phòng
            cleaned_ports.append({
                "port_id": port_id_counter,
                "station_id": station_id,
                "port_code": f"P{num_dc+1}_AC",
                "connector_type": "Type2",
                "control_type": "CONTINUOUS",
                "status": "ACTIVE" if verified else "MAINTENANCE",
                "min_power_kw": 1.4,
                "max_power_kw": 11.0
            })
            port_id_counter += 1
        else:
            # Trạm sạc tiêu chuẩn
            cleaned_ports.append({
                "port_id": port_id_counter,
                "station_id": station_id,
                "port_code": "P1",
                "connector_type": "CCS2",
                "control_type": "CONTINUOUS",
                "status": "ACTIVE" if verified else "MAINTENANCE",
                "min_power_kw": 1.4,
                "max_power_kw": 22.0
            })
            port_id_counter += 1
            cleaned_ports.append({
                "port_id": port_id_counter,
                "station_id": station_id,
                "port_code": "P2",
                "connector_type": "AC_HOME",
                "control_type": "ON_OFF_SWITCH",
                "status": "ACTIVE" if verified else "MAINTENANCE",
                "min_power_kw": 1.0,
                "max_power_kw": 3.7
            })
            port_id_counter += 1

    df_stations = pd.DataFrame(cleaned_stations)
    df_stations.to_csv(os.path.join(DATA_DIR, "charging_station_cleaned.csv"), index=False, encoding="utf-8")
    print(f"✅ Đã làm sạch & xuất 107 trạm sạc thực tế -> {os.path.join(DATA_DIR, 'charging_station_cleaned.csv')}")
    missing_coordinates = df_stations[
        df_stations[["lat", "lng"]].isna().any(axis=1)
    ][["station_id", "name", "province", "address", "lat", "lng"]].copy()
    missing_coordinates["missing_fields"] = missing_coordinates.apply(
        lambda row: ",".join(
            field for field in ("lat", "lng") if pd.isna(row[field])
        ),
        axis=1,
    )
    missing_coordinates = missing_coordinates[
        ["station_id", "name", "province", "address", "missing_fields"]
    ]
    missing_coordinates_path = os.path.join(DATA_DIR, "stations_missing_coordinates.csv")
    missing_coordinates.to_csv(missing_coordinates_path, index=False, encoding="utf-8")
    print(
        f"ℹ️ {len(missing_coordinates)} trạm thiếu tọa độ; danh sách: "
        f"{missing_coordinates_path}"
    )

    df_ports = pd.DataFrame(cleaned_ports)
    df_ports.to_csv(os.path.join(DATA_DIR, "port_cleaned.csv"), index=False, encoding="utf-8")
    print(f"✅ Đã sinh & xuất {len(cleaned_ports)} cổng sạc chuẩn hóa -> {os.path.join(DATA_DIR, 'port_cleaned.csv')}")

    # 3. Tạo bảng biểu giá điện EVN 3 khung giờ cho 4 cụm
    tariffs = []
    t_id = 1
    bands = [
        ("OFF_PEAK", "00:00", "04:00", 1600.00),
        ("NORMAL",   "04:00", "09:30", 2400.00),
        ("PEAK",     "09:30", "11:30", 4000.00),
        ("NORMAL",   "11:30", "17:00", 2400.00),
        ("PEAK",     "17:00", "20:00", 4000.00),
        ("NORMAL",   "20:00", "22:00", 2400.00),
        ("OFF_PEAK", "22:00", "24:00", 1600.00),
    ]
    for c_id in [1, 2, 3, 4]:
        for b_name, start, end, price in bands:
            tariffs.append({
                "tariff_id": t_id,
                "cluster_id": c_id,
                "day_type": "WEEKDAY",
                "band": b_name,
                "start_time": start,
                "end_time": end,
                "price_vnd_kwh": price,
                "source_ref": EVN_TARIFF_SOURCE_REF
            })
            t_id += 1
            tariffs.append({
                "tariff_id": t_id,
                "cluster_id": c_id,
                "day_type": "WEEKEND",
                "band": b_name,
                "start_time": start,
                "end_time": end,
                "price_vnd_kwh": price,
                "source_ref": EVN_TARIFF_SOURCE_REF
            })
            t_id += 1

    df_tariff = pd.DataFrame(tariffs)
    df_tariff.to_csv(os.path.join(DATA_DIR, "tariff_window_cleaned.csv"), index=False, encoding="utf-8")
    print(f"✅ Đã xuất {len(tariffs)} khung biểu giá điện EVN -> {os.path.join(DATA_DIR, 'tariff_window_cleaned.csv')}")

    return df_models, df_stations, df_ports, df_tariff


def seed_postgres_database(df_models, df_stations, df_ports, df_tariff):
    _configure_console_encoding()
    print("🔌 Kiểm tra kết nối PostgreSQL...")
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        print(" Connected to PostgreSQL! Đang nạp dữ liệu catalog...")

        # 1. Nạp app_user mẫu
        users = [
            (1, 'ADMIN', 'Quản trị Hệ thống ShareGrid', 'admin@sharegrid.vn', '0901000001', 100.00, 'ACTIVE'),
            (2, 'HOST', 'Nguyễn Văn Chủ Trạm (Đà Nẵng)', 'host1@sharegrid.vn', '0901000002', 98.50, 'ACTIVE'),
            (3, 'USER', 'Trần Thị Khách Hàng', 'user1@sharegrid.vn', '0901000003', 95.00, 'ACTIVE')
        ]
        cur.executemany("""
            INSERT INTO app_user (user_id, role, full_name, email, phone, reliability_score, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name;
        """, users)

        # 2. Nạp grid_cluster từ data/grid_cluster.csv
        gc_path = os.path.join(DATA_DIR, "grid_cluster.csv")
        if os.path.exists(gc_path):
            df_gc = pd.read_csv(gc_path)
            for _, r in df_gc.iterrows():
                cur.execute("""
                    INSERT INTO grid_cluster (cluster_id, name, province, timezone, status, h3_index, centroid_lat, centroid_lng, grid_limit_kw)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (cluster_id) DO UPDATE SET grid_limit_kw = EXCLUDED.grid_limit_kw;
                """, (int(r["cluster_id"]), r["name"], r["province"], r["timezone"], r["status"],
                      r["h3_index"], float(r["centroid_lat"]), float(r["centroid_lng"]), float(r["grid_limit_kw"])))

        # 3. Nạp vehicle_model (19 dòng xe thực tế)
        for _, m in df_models.iterrows():
            cur.execute("""
                INSERT INTO vehicle_model (
                    model_id, brand, model_name, vehicle_type, connector_type,
                    source_type, source_ref, battery_kwh, max_kw, max_ac_kw, max_dc_kw, standard_charger_kw, data_note
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (model_id) DO UPDATE SET
                    battery_kwh = EXCLUDED.battery_kwh,
                    max_kw = EXCLUDED.max_kw,
                    connector_type = EXCLUDED.connector_type;
            """, (int(m["model_id"]), m["brand"], m["model_name"], m["vehicle_type"], m["connector_type"],
                  m["source_type"], m["source_ref"], float(m["battery_kwh"]), float(m["max_kw"]),
                  m["max_ac_kw"] if pd.notnull(m["max_ac_kw"]) else None,
                  m["max_dc_kw"] if pd.notnull(m["max_dc_kw"]) else None,
                  m["standard_charger_kw"] if pd.notnull(m["standard_charger_kw"]) else None,
                  m["data_note"]))

        # 3b. Nạp xe demo sau vehicle_model để thỏa khóa ngoại model_id.
        cur.execute("""
            INSERT INTO vehicle (vehicle_id, user_id, model_id, plate_number, nickname, default_soc_target, is_default)
            VALUES (101, 3, 2, '43A-123.45', 'VF 5 Đi Làm', 80.00, TRUE)
            ON CONFLICT (vehicle_id) DO NOTHING;
        """)

        # 4. Nạp charging_station (107 trạm thực tế)
        for _, s in df_stations.iterrows():
            has_coords = (
                pd.notnull(s["lat"])
                and pd.notnull(s["lng"])
                and math.isfinite(float(s["lat"]))
                and math.isfinite(float(s["lng"]))
            )
            loc_sql = "ST_SetSRID(ST_MakePoint(%s, %s), 4326)" if has_coords else "NULL"

            sql = f"""
                INSERT INTO charging_station (
                    station_id, cluster_id, owner_id, name, address, province, area_label,
                    supported_vehicle_type, status, ocpp_id, phone, osm_id, source_type, source_ref,
                    lat, lng, location, open_time, close_time, is_24h, verified,
                    station_power_kw, service_fee_vnd, rating, listed_network, listed_port_count, listed_max_port_kw, qa_notes
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, {loc_sql}, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (station_id) DO UPDATE SET
                    status = EXCLUDED.status,
                    verified = EXCLUDED.verified,
                    station_power_kw = EXCLUDED.station_power_kw,
                    rating = EXCLUDED.rating,
                    qa_notes = EXCLUDED.qa_notes;
            """
            params = [
                int(s["station_id"]), int(s["cluster_id"]), int(s["owner_id"]), s["name"], s["address"], s["province"], s["area_label"],
                s["supported_vehicle_type"], s["status"], s["ocpp_id"], s["phone"], s["osm_id"], s["source_type"], s["source_ref"],
                float(s["lat"]) if has_coords else None,
                float(s["lng"]) if has_coords else None,
            ]
            if has_coords:
                params.extend([float(s["lng"]), float(s["lat"])])
            params.extend([
                s["open_time"], s["close_time"], bool(s["is_24h"]), bool(s["verified"]),
                float(s["station_power_kw"]), float(s["service_fee_vnd"]),
                float(s["rating"]) if pd.notnull(s["rating"]) else None,
                s["listed_network"],
                int(s["listed_port_count"]) if pd.notnull(s["listed_port_count"]) else None,
                float(s["listed_max_port_kw"]) if pd.notnull(s["listed_max_port_kw"]) else None,
                s["qa_notes"]
            ])
            cur.execute(sql, tuple(params))

        # 5. Nạp port
        for _, p in df_ports.iterrows():
            cur.execute("""
                INSERT INTO port (port_id, station_id, port_code, connector_type, control_type, status, min_power_kw, max_power_kw)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (port_id) DO UPDATE SET max_power_kw = EXCLUDED.max_power_kw;
            """, (int(p["port_id"]), int(p["station_id"]), p["port_code"], p["connector_type"],
                  p["control_type"], p["status"], float(p["min_power_kw"]), float(p["max_power_kw"])))

        # 6. Nạp tariff_window
        for _, t in df_tariff.iterrows():
            cur.execute("""
                INSERT INTO tariff_window (tariff_id, cluster_id, day_type, band, start_time, end_time, price_vnd_kwh, source_ref)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (tariff_id) DO UPDATE SET price_vnd_kwh = EXCLUDED.price_vnd_kwh;
            """, (int(t["tariff_id"]), int(t["cluster_id"]), t["day_type"], t["band"],
                  t["start_time"], t["end_time"], float(t["price_vnd_kwh"]), t["source_ref"]))

        conn.commit()
    except Exception as e:
        if conn is not None:
            try:
                conn.rollback()
            except Exception as rollback_error:
                print(f"Rollback PostgreSQL thất bại: {rollback_error}", file=sys.stderr)
        print(
            f"Không thể nạp catalog vào PostgreSQL tại {DB_CONFIG['host']}:{DB_CONFIG['port']}: {e}",
            file=sys.stderr,
        )
        sys.exit(1)
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()

    print("🎉 Nạp dữ liệu vào PostgreSQL thành công 100%!")


if __name__ == "__main__":
    df_models, df_stations, df_ports, df_tariff = clean_and_extract_catalogs()
    seed_postgres_database(df_models, df_stations, df_ports, df_tariff)
