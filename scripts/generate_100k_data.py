# scripts/generate_100k_data.py
import numpy as np
import pandas as pd
import psycopg2

DB_CONFIG = {
    "dbname": "ev_sharegrid",
    "user": "postgres",
    "password": "password",
    "host": "localhost",
    "port": 5432
}

np.random.seed(42)

def generate_100k_dataset():
    print("⏳ Đang sinh 100.000 Users và Vehicles giả lập...")
    n_users = 100000
    
    # 1. Sinh 100.000 app_user
    users_df = pd.DataFrame({
        "user_id": np.arange(100, n_users + 100),
        "role": "USER",
        "full_name": [f"User Test {i}" for i in range(1, n_users + 1)],
        "email": [f"user_{i}@sharegrid.vn" for i in range(1, n_users + 1)],
        "phone": [f"090{i:07d}" for i in range(1, n_users + 1)],
        "reliability_score": 95.00,
        "status": "ACTIVE"
    })
    users_df.to_csv("data/app_user_100k.csv", index=False)

    # 2. Sinh 100.000 vehicle tương ứng
    model_ids = [1, 2, 3, 4, 5, 6]
    chosen_models = np.random.choice(model_ids, size=n_users, p=[0.35, 0.25, 0.15, 0.15, 0.05, 0.05])
    vehicles_df = pd.DataFrame({
        "vehicle_id": np.arange(100000, n_users + 100000),
        "user_id": users_df["user_id"],
        "model_id": chosen_models,
        "plate_number": [f"43A-{i:05d}" for i in range(1, n_users + 1)],
        "nickname": [f"Xe của User {i}" for i in range(1, n_users + 1)],
        "default_soc_target": 80.0,
        "is_default": True
    })
    vehicles_df.to_csv("data/vehicle_100k.csv", index=False)
    print("✅ Đã xuất thành công data/app_user_100k.csv và data/vehicle_100k.csv")

    # 3. Tạo 6 kịch bản simulation_scenario
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    scenarios = [100, 500, 1000, 2500, 5000, 10000]
    
    for sc_id, req_count in enumerate(scenarios, start=1):
        cur.execute("""
            INSERT INTO simulation_scenario (scenario_id, name, registry_users, active_requests)
            VALUES (%s, %s, 100000, %s) ON CONFLICT (scenario_id) DO NOTHING;
        """, (sc_id, f"Kịch bản Test {req_count} requests", req_count))
        
        # Sinh file CSV request cho kịch bản
        requests = []
        for r_id in range(1, req_count + 1):
            arr_hour = np.random.randint(7, 18)
            duration = np.random.randint(2, 5)
            soc_now = float(np.random.randint(10, 40))
            soc_target = float(np.random.randint(75, 90))
            
            requests.append({
                "request_id": r_id,
                "user_id": 100 + r_id,
                "vehicle_id": 100000 + r_id,
                "cluster_id": 1,
                "station_id": 10 if r_id % 2 == 0 else 11,
                "scenario_id": sc_id,
                "arrival_time": f"2026-11-18T{arr_hour:02d}:00:00+07:00",
                "departure_time": f"2026-11-18T{(arr_hour + duration):02d}:00:00+07:00",
                "soc_now": soc_now,
                "soc_target": soc_target,
                "battery_kwh_snapshot": 41.9,
                "max_kw_snapshot": 11.0,
                "energy_needed_kwh": round(((soc_target - soc_now) / 100.0) * 41.9 / 0.90, 4),
                "status": "PENDING"
            })
        pd.DataFrame(requests).to_csv(f"data/scenario_{req_count}_requests.csv", index=False)

    conn.commit()
    cur.close()
    conn.close()
    print("✅ Đã xuất 6 file scenario_*.csv và nạp kịch bản vào DB!")

if __name__ == "__main__":
    generate_100k_dataset()
