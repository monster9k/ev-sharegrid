# scripts/generate_100k_data.py
"""
Script sinh dữ liệu quy mô lớn (G2: TASK-13)
 - Sinh 100.000 app_user + vehicle (dựa trên 19 mẫu xe thực tế từ khảo sát của Ánh)
 - Sinh 6 kịch bản request (100, 500, 1.000, 2.500, 5.000, 10.000 requests)
   tại các trạm sạc thực tế ở Đà Nẵng phục vụ benchmark AI Engine.
Tác giả: Thắng (thangchien1607@gmail.com)
"""

import os
import numpy as np
import pandas as pd
import psycopg2

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")

DB_CONFIG = {
    "dbname": os.environ.get("POSTGRES_DB", "ev_sharegrid"),
    "user": os.environ.get("POSTGRES_USER", "postgres"),
    "password": os.environ.get("POSTGRES_PASSWORD", "password"),
    "host": os.environ.get("POSTGRES_HOST", "localhost"),
    "port": int(os.environ.get("POSTGRES_PORT", 5432))
}

np.random.seed(42)


def generate_100k_dataset():
    print("⏳ Đang đọc danh mục 19 mẫu xe & trạm sạc thực tế từ Ánh...")
    os.makedirs(DATA_DIR, exist_ok=True)

    # 1. Đọc danh mục mẫu xe thực tế
    models_path = os.path.join(DATA_DIR, "vehicle_model_cleaned.csv")
    if not os.path.exists(models_path):
        raise FileNotFoundError(f"Chưa tìm thấy {models_path}. Hãy chạy scripts/import_catalog.py trước!")

    df_models = pd.read_csv(models_path)
    model_lookup = {row["model_id"]: row for _, row in df_models.iterrows()}

    # 2. Đọc danh sách trạm sạc đang hoạt động (ACTIVE)
    stations_path = os.path.join(DATA_DIR, "charging_station_cleaned.csv")
    if not os.path.exists(stations_path):
        raise FileNotFoundError(f"Chưa tìm thấy {stations_path}. Hãy chạy scripts/import_catalog.py trước!")

    df_stations = pd.read_csv(stations_path)
    active_stations = df_stations[df_stations["status"] == "ACTIVE"].copy()
    if len(active_stations) == 0:
        active_stations = df_stations.head(15).copy()

    station_list = active_stations[["station_id", "cluster_id", "name"]].to_dict("records")
    print(f"📊 Tìm thấy {len(df_models)} mẫu xe và {len(station_list)} trạm sạc ACTIVE có GPS tại Đà Nẵng.")

    # 3. Sinh 100.000 app_user
    n_users = 100000
    print(f"⏳ Sinh {n_users:,} app_user giả lập...")
    user_ids = np.arange(100, n_users + 100)
    users_df = pd.DataFrame({
        "user_id": user_ids,
        "role": "USER",
        "full_name": [f"Khách hàng {i}" for i in range(1, n_users + 1)],
        "email": [f"user_{i}@sharegrid.vn" for i in range(1, n_users + 1)],
        "phone": [f"090{i:07d}" for i in range(1, n_users + 1)],
        "reliability_score": np.round(np.random.normal(95.0, 3.0, n_users).clip(85.0, 100.0), 2),
        "status": "ACTIVE"
    })
    users_csv = os.path.join(DATA_DIR, "app_user_100k.csv")
    users_df.to_csv(users_csv, index=False, encoding="utf-8")
    print(f"✅ Đã xuất {users_csv} ({len(users_df):,} dòng)")

    # 4. Sinh 100.000 vehicle phân bổ trên 19 mẫu xe thực tế
    # Tỉ lệ mẫu xe dựa trên thị phần xe điện thực tế tại Việt Nam
    # Model 1..19: VF 3, VF 5, VF 6, VF 7, VF 8, Limo Green, Atto 3 Dyn, Atto 3 Prem, Dolphin,
    #              Evo200, Evo200 Lite, Feliz S, Klara S, Vento S, Theon S, VF e34,
    #              Ioniq 5 Excl, Ioniq 5 Prest, Wuling MiniEV
    model_ids = df_models["model_id"].tolist()
    probs = [
        0.20,  # 1: VF 3
        0.22,  # 2: VF 5 Plus
        0.08,  # 3: VF 6 Eco
        0.05,  # 4: VF 7 Eco
        0.08,  # 5: VF 8 Eco
        0.02,  # 6: Limo Green
        0.04,  # 7: BYD ATTO 3 Dynamic
        0.03,  # 8: BYD ATTO 3 Premium
        0.03,  # 9: BYD Dolphin
        0.03,  # 10: VinFast Evo200
        0.01,  # 11: VinFast Evo200 Lite
        0.03,  # 12: VinFast Feliz S
        0.01,  # 13: VinFast Klara S 2022
        0.005, # 14: VinFast Vento S
        0.005, # 15: VinFast Theon S
        0.10,  # 16: VinFast VF e34
        0.02,  # 17: Hyundai Ioniq 5 Exclusive
        0.01,  # 18: Hyundai Ioniq 5 Prestige
        0.03   # 19: Wuling MiniEV
    ]
    # Chuẩn hóa tổng xác suất = 1.0
    probs = np.array(probs) / np.sum(probs)

    print(f"⏳ Sinh {n_users:,} vehicle gắn với 19 mẫu xe...")
    chosen_models = np.random.choice(model_ids, size=n_users, p=probs)
    vehicle_ids = np.arange(100000, n_users + 100000)

    # Sinh biển số theo tỉnh thành: Đà Nẵng (43), Hà Nội (29), TP.HCM (51)
    plates = []
    for i, m_id in enumerate(chosen_models, 1):
        v_type = model_lookup[m_id]["vehicle_type"]
        region = np.random.choice(["43", "29", "51"], p=[0.7, 0.15, 0.15])
        if v_type == "MOTORBIKE":
            plates.append(f"{region}-K1 {i%90000+10000:05d}")
        else:
            plates.append(f"{region}A-{i%90000+10000:05d}")

    vehicles_df = pd.DataFrame({
        "vehicle_id": vehicle_ids,
        "user_id": user_ids,
        "model_id": chosen_models,
        "plate_number": plates,
        "nickname": [f"Xe của {users_df['full_name'].iloc[i]}" for i in range(n_users)],
        "default_soc_target": [85.0 if model_lookup[m]["vehicle_type"] == "MOTORBIKE" else 80.0 for m in chosen_models],
        "is_default": True
    })
    vehicles_csv = os.path.join(DATA_DIR, "vehicle_100k.csv")
    vehicles_df.to_csv(vehicles_csv, index=False, encoding="utf-8")
    print(f"✅ Đã xuất {vehicles_csv} ({len(vehicles_df):,} dòng)")

    # 5. Sinh 6 kịch bản simulation_scenario (100, 500, 1.000, 2.500, 5.000, 10.000 requests)
    scenarios = [100, 500, 1000, 2500, 5000, 10000]
    print(f"⏳ Sinh 6 kịch bản thực nghiệm sạc: {scenarios}...")

    # Khung giờ cao điểm và phân bổ đến sạc
    # 07-09 (sáng), 11-13 (trưa), 17-20 (chiều tối), giờ khác
    hours = np.arange(0, 24)
    hour_weights = [
        0.01, 0.01, 0.01, 0.01, 0.01, 0.02,  # 0h - 5h
        0.05, 0.09, 0.08, 0.06, 0.05,        # 6h - 10h (sáng cao điểm)
        0.07, 0.07, 0.05, 0.04, 0.04, 0.05,  # 11h - 16h (trưa)
        0.09, 0.09, 0.06, 0.04, 0.02, 0.01   # 17h - 22h (chiều cao điểm)
    ]
    # Bổ sung 23h
    if len(hour_weights) == 23:
        hour_weights.append(0.01)
    hour_weights = np.array(hour_weights) / np.sum(hour_weights)

    for sc_id, req_count in enumerate(scenarios, start=1):
        requests = []
        for r_id in range(1, req_count + 1):
            # Chọn user và vehicle
            v_idx = (r_id * 7) % n_users
            v_id = int(vehicles_df["vehicle_id"].iloc[v_idx])
            u_id = int(vehicles_df["user_id"].iloc[v_idx])
            m_id = int(vehicles_df["model_id"].iloc[v_idx])
            model_info = model_lookup[m_id]

            # Chọn trạm sạc thực tế
            st_info = station_list[r_id % len(station_list)]
            st_id = int(st_info["station_id"])
            cl_id = int(st_info["cluster_id"])

            # Thời gian sạc
            arr_h = int(np.random.choice(hours, p=hour_weights))
            arr_m = int(np.random.choice([0, 15, 30, 45]))
            dur_hours = int(np.random.choice([1, 2, 3, 4], p=[0.2, 0.4, 0.3, 0.1]))

            arr_str = f"2026-11-18T{arr_h:02d}:{arr_m:02d}:00+07:00"
            dep_h = min(arr_h + dur_hours, 23)
            dep_m = arr_m
            dep_str = f"2026-11-18T{dep_h:02d}:{dep_m:02d}:00+07:00"
            if dep_h == arr_h:
                dep_str = f"2026-11-18T23:59:00+07:00"

            soc_now = float(np.random.randint(10, 40))
            soc_target = float(np.random.randint(75, 95))
            battery_kwh = float(model_info["battery_kwh"])
            max_kw = float(model_info["max_kw"])

            energy_needed = round(((soc_target - soc_now) / 100.0) * battery_kwh / 0.90, 4)

            requests.append({
                "request_id": r_id,
                "user_id": u_id,
                "vehicle_id": v_id,
                "cluster_id": cl_id,
                "station_id": st_id,
                "scenario_id": sc_id,
                "arrival_time": arr_str,
                "departure_time": dep_str,
                "soc_now": soc_now,
                "soc_target": soc_target,
                "battery_kwh_snapshot": battery_kwh,
                "max_kw_snapshot": max_kw,
                "energy_needed_kwh": energy_needed,
                "status": "PENDING"
            })

        sc_file = os.path.join(DATA_DIR, f"scenario_{req_count}_requests.csv")
        pd.DataFrame(requests).to_csv(sc_file, index=False, encoding="utf-8")
        print(f"  👉 Kịch bản {req_count} requests: {sc_file}")

    # 6. Ghi simulation_scenario vào PostgreSQL nếu có kết nối
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        for sc_id, req_count in enumerate(scenarios, start=1):
            cur.execute("""
                INSERT INTO simulation_scenario (scenario_id, name, registry_users, active_requests)
                VALUES (%s, %s, 100000, %s)
                ON CONFLICT (scenario_id) DO UPDATE SET active_requests = EXCLUDED.active_requests;
            """, (sc_id, f"Kịch bản Thực nghiệm {req_count} requests", req_count))
        conn.commit()
        cur.close()
        conn.close()
        print("🎉 Đã đồng bộ 6 simulation_scenario vào PostgreSQL!")
    except Exception as e:
        print(f"ℹ️ Không thể kết nối PostgreSQL: {e}")

    print("🚀 Hoàn tất 100% việc sinh dữ liệu G2 (TASK-13) từ dữ liệu thực tế của Ánh!")


if __name__ == "__main__":
    generate_100k_dataset()
