# scripts/generate_100k_data.py
"""
Script sinh dữ liệu quy mô lớn (G2: TASK-13)
 - Sinh 100.000 app_user + vehicle (dựa trên 19 mẫu xe thực tế từ khảo sát của Ánh)
 - Sinh 6 kịch bản request (100, 500, 1.000, 2.500, 5.000, 10.000 requests)
   tại các trạm sạc thực tế ở Đà Nẵng phục vụ benchmark AI Engine.
Tác giả: Thắng (thangchien1607@gmail.com)
"""

import os
import sys
from datetime import datetime, timedelta, timezone
import numpy as np
import pandas as pd

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")

DB_CONFIG = {
    "dbname": os.environ.get("POSTGRES_DB", "ev_sharegrid"),
    "user": os.environ.get("POSTGRES_USER", "postgres"),
    "password": os.environ.get("POSTGRES_PASSWORD", "password"),
    "host": os.environ.get("POSTGRES_HOST", "localhost"),
    "port": int(os.environ.get("POSTGRES_PORT", 5432))
}

SEED = 42
TARGET_CLUSTER_UTILIZATION = 0.80
PEAK_WINDOW_MAX_LOAD_RATIO = 0.90
PEAK_WINDOW_START_HOUR = 17
PEAK_WINDOW_END_HOUR = 20
PEAK_WINDOW_HOURS = PEAK_WINDOW_END_HOUR - PEAK_WINDOW_START_HOUR
CHARGING_EFFICIENCY = 0.90
SCENARIOS = [100, 500, 1000, 2500, 5000, 10000]
BEHAVIOR_RATIOS = {"short_stay": 0.40, "workplace": 0.35, "overnight": 0.25}

np.random.seed(SEED)


def allocate_counts(total, weights):
    """Allocate an exact row count proportionally, using largest remainders."""
    weight_sum = sum(weights.values())
    exact = {key: total * value / weight_sum for key, value in weights.items()}
    counts = {key: int(value) for key, value in exact.items()}
    remaining = total - sum(counts.values())
    order = sorted(weights, key=lambda key: (-(exact[key] - counts[key]), str(key)))
    for key in order[:remaining]:
        counts[key] += 1
    return counts


def distribute_energy(target_kwh, max_energy_by_request):
    """Distribute energy up to each request's battery-derived physical limit."""
    capacities = np.floor(np.asarray(max_energy_by_request, dtype=float) * 10000) / 10000
    total_capacity = float(capacities.sum())
    allocated_total = min(max(float(target_kwh), 0.0), total_capacity)
    if allocated_total <= 0 or total_capacity <= 0:
        return np.zeros(len(capacities), dtype=float)

    values = np.floor((allocated_total * capacities / total_capacity) * 10000) / 10000
    remaining = round(allocated_total - float(values.sum()), 4)
    for index in np.argsort(-capacities):
        room = round(float(capacities[index] - values[index]), 4)
        addition = min(room, remaining)
        values[index] = round(float(values[index] + addition), 4)
        remaining = round(remaining - addition, 4)
        if remaining <= 0:
            break
    return values


def _profile_arrival_and_duration(profile, rng):
    if profile == "short_stay":
        hour = int(rng.integers(8, 22))
        duration_minutes = int(rng.choice([90, 120, 150]))
    elif profile == "workplace":
        hour = int(rng.integers(7, 10))
        duration_minutes = int(rng.choice([480, 510, 540, 570]))
    else:
        hour = int(rng.integers(18, 23))
        duration_minutes = int(rng.choice([540, 600, 660, 720]))

    minute = int(rng.choice([0, 30]))
    arrival = datetime(2026, 11, 18, hour, minute, tzinfo=timezone(timedelta(hours=7)))
    departure = arrival + timedelta(minutes=duration_minutes)
    return arrival, departure, duration_minutes / 60.0


def generate_scenario_files():
    """Generate fixed-size scenarios; small sets may not physically reach 60% load."""
    rng = np.random.default_rng(SEED)
    models_path = os.path.join(DATA_DIR, "vehicle_model_cleaned.csv")
    vehicles_path = os.path.join(DATA_DIR, "vehicle_100k.csv")
    stations_path = os.path.join(DATA_DIR, "charging_station_cleaned.csv")
    clusters_path = os.path.join(DATA_DIR, "grid_cluster.csv")
    for path in (models_path, vehicles_path, stations_path, clusters_path):
        if not os.path.exists(path):
            raise FileNotFoundError(f"Chưa tìm thấy {path}; hãy nạp catalog trước.")

    df_models = pd.read_csv(models_path)
    df_vehicles = pd.read_csv(vehicles_path)
    df_stations = pd.read_csv(stations_path)
    df_clusters = pd.read_csv(clusters_path)
    active_stations = df_stations[df_stations["status"] == "ACTIVE"].copy()
    if active_stations.empty:
        raise ValueError("Không có trạm ACTIVE có tọa độ để sinh kịch bản.")

    model_lookup = df_models.set_index("model_id").to_dict("index")
    limits_kw = {
        int(row["cluster_id"]): float(row["grid_limit_kw"])
        for _, row in df_clusters.iterrows()
    }
    station_pools = {
        int(cluster_id): group["station_id"].astype(int).to_numpy()
        for cluster_id, group in active_stations.groupby("cluster_id")
    }
    active_clusters = sorted(station_pools)
    missing_limits = set(active_clusters) - set(limits_kw)
    if missing_limits:
        raise ValueError(f"Thiếu grid_limit_kw cho các cụm: {sorted(missing_limits)}")
    cluster_weights = {cluster_id: limits_kw[cluster_id] for cluster_id in active_clusters}
    scenario_summaries = []

    for scenario_id, request_count in enumerate(SCENARIOS, start=1):
        if request_count > len(df_vehicles):
            raise ValueError("Số vehicle mẫu phải ít nhất bằng số request của kịch bản.")
        vehicle_indices = rng.choice(len(df_vehicles), size=request_count, replace=False)
        selected_vehicles = df_vehicles.iloc[vehicle_indices].to_dict("records")

        cluster_counts = allocate_counts(request_count, cluster_weights)
        cluster_labels = [
            cluster_id
            for cluster_id, count in cluster_counts.items()
            for _ in range(count)
        ]
        rng.shuffle(cluster_labels)

        behavior_counts = allocate_counts(request_count, BEHAVIOR_RATIOS)
        behavior_labels = [
            profile
            for profile, count in behavior_counts.items()
            for _ in range(count)
        ]
        rng.shuffle(behavior_labels)

        requests = []
        for index, (vehicle, cluster_id, profile) in enumerate(
            zip(selected_vehicles, cluster_labels, behavior_labels), start=1
        ):
            model_id = int(vehicle["model_id"])
            model = model_lookup[model_id]
            station_id = int(rng.choice(station_pools[cluster_id]))
            arrival, departure, dwell_hours = _profile_arrival_and_duration(profile, rng)
            preferred_soc_now = float(rng.integers(10, 40))
            preferred_soc_target = float(rng.integers(75, 95))
            battery_kwh = float(model["battery_kwh"])
            preferred_energy_kwh = round(
                ((preferred_soc_target - preferred_soc_now) / 100.0)
                * battery_kwh
                / CHARGING_EFFICIENCY,
                4,
            )
            # Conservatively charge the full requested energy against the peak
            # budget when a request arrives during 17:00–20:00.
            arrives_in_peak = (
                PEAK_WINDOW_START_HOUR <= arrival.hour < PEAK_WINDOW_END_HOUR
            )
            requests.append({
                "request_id": index,
                "user_id": int(vehicle["user_id"]),
                "vehicle_id": int(vehicle["vehicle_id"]),
                "cluster_id": cluster_id,
                "station_id": station_id,
                "scenario_id": scenario_id,
                "arrival_time": arrival.isoformat(timespec="seconds"),
                "departure_time": departure.isoformat(timespec="seconds"),
                "soc_now": preferred_soc_now,
                "soc_target": preferred_soc_target,
                "battery_kwh_snapshot": battery_kwh,
                "max_kw_snapshot": float(model["max_kw"]),
                "energy_needed_kwh": None,
                "status": "PENDING",
                "_behavior": profile,
                "_dwell_hours": dwell_hours,
                "_arrives_in_peak": arrives_in_peak,
                "_preferred_energy_kwh": preferred_energy_kwh,
                "_preferred_soc_now": preferred_soc_now,
            })

        physical_max_by_cluster = {}
        for cluster_id in active_clusters:
            cluster_rows = [row for row in requests if row["cluster_id"] == cluster_id]
            peak_rows = [row for row in cluster_rows if row["_arrives_in_peak"]]
            off_peak_rows = [row for row in cluster_rows if not row["_arrives_in_peak"]]

            physical_peak_caps = np.floor(
                np.asarray([row["battery_kwh_snapshot"] for row in peak_rows])
                / CHARGING_EFFICIENCY * 10000
            ) / 10000
            physical_off_peak_caps = np.floor(
                np.asarray([row["battery_kwh_snapshot"] for row in off_peak_rows])
                / CHARGING_EFFICIENCY * 10000
            ) / 10000
            grid_limit_kw = limits_kw[cluster_id]
            target_kwh = (
                TARGET_CLUSTER_UTILIZATION * grid_limit_kw * 24.0
            )
            peak_budget_kwh = (
                PEAK_WINDOW_MAX_LOAD_RATIO * grid_limit_kw * PEAK_WINDOW_HOURS - 0.1
            )
            physical_max_kwh = (
                min(float(physical_peak_caps.sum()), peak_budget_kwh)
                + float(physical_off_peak_caps.sum())
            )
            physical_max_by_cluster[cluster_id] = physical_max_kwh
            if physical_max_kwh < target_kwh:
                # Preserve ordinary 10–39% to 75–94% SOC requests when this
                # fixed row count cannot meet the utilization target even at
                # full battery capacity.
                peak_caps = np.asarray(
                    [row["_preferred_energy_kwh"] for row in peak_rows], dtype=float
                )
                off_peak_caps = np.asarray(
                    [row["_preferred_energy_kwh"] for row in off_peak_rows], dtype=float
                )
            else:
                peak_caps = physical_peak_caps
                off_peak_caps = physical_off_peak_caps
            peak_possible = min(float(peak_caps.sum()), peak_budget_kwh)
            off_peak_capacity = float(off_peak_caps.sum())
            achievable_kwh = min(target_kwh, peak_possible + off_peak_capacity)
            if cluster_rows and peak_rows:
                desired_peak = achievable_kwh * len(peak_rows) / len(cluster_rows)
            else:
                desired_peak = 0.0
            peak_target_kwh = min(peak_possible, desired_peak)
            peak_target_kwh = max(peak_target_kwh, achievable_kwh - off_peak_capacity)
            peak_target_kwh = min(peak_target_kwh, peak_possible)
            peak_allocations = distribute_energy(peak_target_kwh, peak_caps)
            off_peak_target_kwh = max(
                0.0, achievable_kwh - float(peak_allocations.sum())
            )
            off_peak_allocations = distribute_energy(off_peak_target_kwh, off_peak_caps)

            for row, energy_kwh in zip(peak_rows, peak_allocations):
                row["_allocated_energy_kwh"] = float(energy_kwh)
            for row, energy_kwh in zip(off_peak_rows, off_peak_allocations):
                row["_allocated_energy_kwh"] = float(energy_kwh)

        for row in requests:
            battery_kwh = row["battery_kwh_snapshot"]
            energy_kwh = row["_allocated_energy_kwh"]
            soc_delta = min(100.0, energy_kwh * CHARGING_EFFICIENCY / battery_kwh * 100.0)
            max_soc_now = max(0.0, 100.0 - soc_delta)
            soc_now = round(min(row["_preferred_soc_now"], max_soc_now), 6)
            soc_target = round(min(100.0, soc_now + soc_delta), 6)
            row["soc_now"] = soc_now
            row["soc_target"] = soc_target
            row["energy_needed_kwh"] = round(
                ((soc_target - soc_now) / 100.0) * battery_kwh / CHARGING_EFFICIENCY,
                4,
            )
            for internal_key in (
                "_behavior", "_dwell_hours", "_arrives_in_peak", "_allocated_energy_kwh",
                "_preferred_energy_kwh", "_preferred_soc_now",
            ):
                row.pop(internal_key, None)

        sc_file = os.path.join(DATA_DIR, f"scenario_{request_count}_requests.csv")
        pd.DataFrame(requests).to_csv(sc_file, index=False, encoding="utf-8")

        total_kwh = sum(float(row["energy_needed_kwh"]) for row in requests)
        cluster_metrics = {}
        for cluster_id in active_clusters:
            rows = [row for row in requests if int(row["cluster_id"]) == cluster_id]
            energy_kwh = sum(float(row["energy_needed_kwh"]) for row in rows)
            capacity_kwh = limits_kw[cluster_id] * 24.0
            peak_energy_kwh = sum(
                float(row["energy_needed_kwh"])
                for row in rows
                if PEAK_WINDOW_START_HOUR
                <= datetime.fromisoformat(row["arrival_time"]).hour
                < PEAK_WINDOW_END_HOUR
            )
            peak_capacity_kwh = limits_kw[cluster_id] * PEAK_WINDOW_HOURS
            cluster_metrics[cluster_id] = {
                "energy_kwh": energy_kwh,
                "capacity_kwh": capacity_kwh,
                "utilization": energy_kwh / capacity_kwh,
                "peak_ratio": peak_energy_kwh / peak_capacity_kwh,
            }
            if cluster_metrics[cluster_id]["peak_ratio"] > PEAK_WINDOW_MAX_LOAD_RATIO:
                raise ValueError(
                    f"Scenario {request_count}, cụm {cluster_id} vượt giới hạn tải cao điểm: "
                    f"{cluster_metrics[cluster_id]['peak_ratio']:.4f}"
                )
        scenario_summaries.append(
            (request_count, total_kwh, cluster_metrics, physical_max_by_cluster)
        )

    print("Kịch bản | Requests | Tổng kWh | Tỷ lệ tải 24h | Tải theo cụm / tỷ lệ cao điểm")
    for request_count, total_kwh, metrics, physical_limits in scenario_summaries:
        total_capacity = sum(value["capacity_kwh"] for value in metrics.values())
        utilization = total_kwh / total_capacity if total_capacity else 0.0
        target_total = sum(
            TARGET_CLUSTER_UTILIZATION * value["capacity_kwh"]
            for value in metrics.values()
        )
        physical_max_total = sum(physical_limits.values())
        per_cluster = "; ".join(
            f"C{cluster_id}: {value['energy_kwh']:.1f}/{value['capacity_kwh']:.0f} kWh "
            f"({value['utilization']:.1%}), peak {value['peak_ratio']:.1%}"
            for cluster_id, value in metrics.items()
        )
        print(
            f"{request_count:>5} | {request_count:>8} | {total_kwh:>9.1f} | "
            f"{utilization:>10.1%} | {per_cluster}"
        )
        if physical_max_total < target_total:
            print(
                f"  Giới hạn vật lý của {request_count} requests: "
                f"{physical_max_total:.1f}/{total_capacity:.0f} kWh "
                f"({physical_max_total / total_capacity:.1%}); không đạt target 80% với số dòng này."
            )
    inactive_clusters = sorted(set(limits_kw) - set(active_clusters))
    if inactive_clusters:
        print(
            "Không sinh request cho cụm không có trạm ACTIVE có tọa độ: "
            + ", ".join(map(str, inactive_clusters))
        )


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
        raise ValueError("Không có trạm ACTIVE có tọa độ để sinh kịch bản.")

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

    # 5. Sinh các kịch bản có khống chế tổng tải và tải giờ cao điểm.
    generate_scenario_files()

    # 6. Ghi simulation_scenario vào PostgreSQL nếu có kết nối
    try:
        import psycopg2

        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        for sc_id, req_count in enumerate(SCENARIOS, start=1):
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
    import argparse

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser(description="Sinh dữ liệu benchmark EV ShareGrid.")
    parser.add_argument(
        "--scenarios-only",
        action="store_true",
        help="Chỉ sinh lại các CSV scenario từ catalog/user/vehicle hiện có.",
    )
    args = parser.parse_args()
    if args.scenarios_only:
        generate_scenario_files()
    else:
        generate_100k_dataset()
