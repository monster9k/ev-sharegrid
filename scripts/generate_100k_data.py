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
    "password": os.environ.get("POSTGRES_PASSWORD"),
    "host": os.environ.get("POSTGRES_HOST", "localhost"),
    "port": int(os.environ.get("POSTGRES_PORT", 5432))
}

SEED = 42
TARGET_CLUSTER_UTILIZATION = 0.80
CHARGING_EFFICIENCY = 0.90
MIN_REQUEST_ENERGY_KWH = 15.0
MAX_REQUEST_ENERGY_KWH = 40.0
SCENARIOS = [100, 500, 1000, 2500, 5000, 10000]
QUALITY_CONTROLLED_SCENARIOS = {500, 1000}
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


def fit_cluster_energy_budget(requests, target_kwh):
    """Scale randomized per-vehicle demands within SOC-derived 15–40 kWh bounds."""
    lower = np.full(len(requests), MIN_REQUEST_ENERGY_KWH, dtype=float)
    upper = np.asarray([row["_max_energy_kwh"] for row in requests], dtype=float)
    sampled = np.asarray([row["_sampled_energy_kwh"] for row in requests], dtype=float)
    minimum = float(lower.sum())
    maximum = float(upper.sum())
    if target_kwh < minimum or target_kwh > maximum:
        raise ValueError(
            f"Không thể đạt tải mục tiêu {target_kwh:.1f} kWh với {len(requests)} xe "
            f"trong dải {MIN_REQUEST_ENERGY_KWH:g}–{MAX_REQUEST_ENERGY_KWH:g} kWh; "
            f"giới hạn khả thi là {minimum:.1f}–{maximum:.1f} kWh."
        )

    sampled_total = float(sampled.sum())
    if target_kwh <= sampled_total:
        sampled_room = sampled - lower
        factor = (target_kwh - minimum) / max(float(sampled_room.sum()), 1e-12)
        values = lower + sampled_room * factor
    else:
        upper_room = upper - sampled
        factor = (maximum - target_kwh) / max(float(upper_room.sum()), 1e-12)
        values = upper - upper_room * factor
    return np.round(values, 4)


def scenario_type(request_count):
    if request_count == 100:
        return "CAPACITY_LIMITED_SAMPLE"
    if request_count in QUALITY_CONTROLLED_SCENARIOS:
        return "LOAD_CONTROLLED_QUALITY"
    if request_count == 10000:
        return "LLF_THROUGHPUT_ONLY"
    return "THROUGHPUT_OVERLOAD"


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
    """Generate fixed-size scenarios using stations with a compatible active port."""
    rng = np.random.default_rng(SEED)
    models_path = os.path.join(DATA_DIR, "vehicle_model_cleaned.csv")
    vehicles_path = os.path.join(DATA_DIR, "vehicle_100k.csv")
    stations_path = os.path.join(DATA_DIR, "charging_station_cleaned.csv")
    ports_path = os.path.join(DATA_DIR, "port_cleaned.csv")
    clusters_path = os.path.join(DATA_DIR, "grid_cluster.csv")
    for path in (models_path, vehicles_path, stations_path, ports_path, clusters_path):
        if not os.path.exists(path):
            raise FileNotFoundError(f"Chưa tìm thấy {path}; hãy nạp catalog trước.")

    df_models = pd.read_csv(models_path)
    df_vehicles = pd.read_csv(vehicles_path)
    df_stations = pd.read_csv(stations_path)
    df_ports = pd.read_csv(ports_path)
    df_clusters = pd.read_csv(clusters_path)
    active_stations = df_stations[df_stations["status"] == "ACTIVE"].copy()
    if active_stations.empty:
        raise ValueError("Không có trạm ACTIVE có tọa độ để sinh kịch bản.")

    model_lookup = df_models.set_index("model_id").to_dict("index")
    limits_kw = {
        int(row["cluster_id"]): float(row["grid_limit_kw"])
        for _, row in df_clusters.iterrows()
    }
    active_ports = df_ports[df_ports["status"] == "ACTIVE"]
    connectors_by_station = {
        int(station_id): set(group["connector_type"].astype(str))
        for station_id, group in active_ports.groupby("station_id")
    }
    station_pools = {}
    for cluster_id, group in active_stations.groupby("cluster_id"):
        connector_pools = {}
        for connector in sorted(set(df_models["connector_type"].astype(str))):
            compatible_ids = [
                int(row["station_id"])
                for _, row in group.iterrows()
                if connector in connectors_by_station.get(int(row["station_id"]), set())
            ]
            if compatible_ids:
                connector_pools[connector] = np.asarray(compatible_ids, dtype=int)
        station_pools[int(cluster_id)] = connector_pools
    active_clusters = sorted(station_pools)
    missing_limits = set(active_clusters) - set(limits_kw)
    if missing_limits:
        raise ValueError(f"Thiếu grid_limit_kw cho các cụm: {sorted(missing_limits)}")
    cluster_weights = {cluster_id: limits_kw[cluster_id] for cluster_id in active_clusters}
    scenario_summaries = []

    for scenario_id, request_count in enumerate(SCENARIOS, start=1):
        if request_count > len(df_vehicles):
            raise ValueError("Số vehicle mẫu phải ít nhất bằng số request của kịch bản.")
        cluster_counts = allocate_counts(request_count, cluster_weights)
        assignments = []
        used_vehicle_ids = set()
        for cluster_id, count in cluster_counts.items():
            compatible_connectors = set(station_pools[cluster_id])
            candidate_mask = df_vehicles["model_id"].map(
                lambda model_id: model_lookup[int(model_id)]["connector_type"]
                in compatible_connectors
            )
            candidates = df_vehicles[candidate_mask]
            candidates = candidates[~candidates["vehicle_id"].isin(used_vehicle_ids)]
            if len(candidates) < count:
                raise ValueError(
                    f"Không đủ xe có đầu nối tương thích cụm {cluster_id}: "
                    f"cần {count}, có {len(candidates)}."
                )
            chosen = candidates.iloc[
                rng.choice(len(candidates), size=count, replace=False)
            ].to_dict("records")
            used_vehicle_ids.update(int(vehicle["vehicle_id"]) for vehicle in chosen)
            assignments.extend((vehicle, cluster_id) for vehicle in chosen)
        rng.shuffle(assignments)

        behavior_counts = allocate_counts(request_count, BEHAVIOR_RATIOS)
        behavior_labels = [
            profile
            for profile, count in behavior_counts.items()
            for _ in range(count)
        ]
        rng.shuffle(behavior_labels)

        requests = []
        for index, ((vehicle, cluster_id), profile) in enumerate(
            zip(assignments, behavior_labels), start=1
        ):
            model_id = int(vehicle["model_id"])
            model = model_lookup[model_id]
            connector = str(model["connector_type"])
            compatible_station_ids = station_pools[cluster_id][connector]
            station_id = int(rng.choice(compatible_station_ids))
            arrival, departure, dwell_hours = _profile_arrival_and_duration(profile, rng)
            battery_kwh = float(model["battery_kwh"])
            soc_now = float(rng.uniform(5.0, 20.0))
            max_energy_kwh = min(
                MAX_REQUEST_ENERGY_KWH,
                battery_kwh * (100.0 - soc_now) / 100.0 / CHARGING_EFFICIENCY
                - 0.001,
            )
            if max_energy_kwh < MIN_REQUEST_ENERGY_KWH:
                raise ValueError(
                    f"Xe {vehicle['vehicle_id']} không thể xin ít nhất "
                    f"{MIN_REQUEST_ENERGY_KWH:g} kWh từ SOC {soc_now:.2f}%"
                )
            sampled_energy_kwh = float(
                rng.uniform(MIN_REQUEST_ENERGY_KWH, max_energy_kwh)
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
                "soc_now": None,
                "soc_target": None,
                "battery_kwh_snapshot": battery_kwh,
                "max_kw_snapshot": float(model["max_kw"]),
                "connector_type": connector,
                "energy_needed_kwh": None,
                "status": "PENDING",
                "behavior_profile": profile,
                "scenario_type": scenario_type(request_count),
                "_soc_now": soc_now,
                "_max_energy_kwh": max_energy_kwh,
                "_sampled_energy_kwh": sampled_energy_kwh,
            })

        physical_max_by_cluster = {}
        for cluster_id in active_clusters:
            cluster_rows = [row for row in requests if row["cluster_id"] == cluster_id]
            physical_max_by_cluster[cluster_id] = sum(
                row["_max_energy_kwh"] for row in cluster_rows
            )
            if request_count in QUALITY_CONTROLLED_SCENARIOS:
                target_kwh = (
                    TARGET_CLUSTER_UTILIZATION * limits_kw[cluster_id] * 24.0
                )
                energies = fit_cluster_energy_budget(cluster_rows, target_kwh)
            else:
                energies = np.asarray(
                    [row["_sampled_energy_kwh"] for row in cluster_rows], dtype=float
                )
            for row, energy_kwh in zip(cluster_rows, energies):
                row["_allocated_energy_kwh"] = float(energy_kwh)

        for row in requests:
            battery_kwh = row["battery_kwh_snapshot"]
            energy_kwh = row["_allocated_energy_kwh"]
            soc_now = round(row["_soc_now"], 6)
            soc_target = round(
                soc_now + energy_kwh * CHARGING_EFFICIENCY / battery_kwh * 100.0,
                6,
            )
            if soc_target > 100.0:
                raise ValueError(
                    f"Request {row['request_id']} có SOC mục tiêu vượt 100%: {soc_target}"
                )
            row["soc_now"] = soc_now
            row["soc_target"] = soc_target
            row["energy_needed_kwh"] = round(
                ((soc_target - soc_now) / 100.0) * battery_kwh / CHARGING_EFFICIENCY,
                4,
            )
            if not MIN_REQUEST_ENERGY_KWH <= row["energy_needed_kwh"] <= MAX_REQUEST_ENERGY_KWH:
                raise ValueError(
                    f"Request {row['request_id']} nằm ngoài dải năng lượng "
                    f"{MIN_REQUEST_ENERGY_KWH:g}–{MAX_REQUEST_ENERGY_KWH:g} kWh: "
                    f"{row['energy_needed_kwh']} kWh"
                )
            for internal_key in (
                "_soc_now", "_max_energy_kwh", "_sampled_energy_kwh", "_allocated_energy_kwh"
            ):
                row.pop(internal_key, None)

        sc_file = os.path.join(DATA_DIR, f"scenario_{request_count}_requests.csv")
        connector_mismatches = [
            row for row in requests
            if row["connector_type"] not in connectors_by_station.get(row["station_id"], set())
        ]
        if connector_mismatches:
            raise ValueError(
                f"Scenario {request_count} có {len(connector_mismatches)} request tại trạm "
                "không có cổng ACTIVE cùng đầu nối."
            )
        connector_mismatch_count = len(connector_mismatches)
        pd.DataFrame(requests).to_csv(sc_file, index=False, encoding="utf-8")

        total_kwh = sum(float(row["energy_needed_kwh"]) for row in requests)
        request_energies = [float(row["energy_needed_kwh"]) for row in requests]
        cluster_metrics = {}
        for cluster_id in active_clusters:
            rows = [row for row in requests if int(row["cluster_id"]) == cluster_id]
            energy_kwh = sum(float(row["energy_needed_kwh"]) for row in rows)
            capacity_kwh = limits_kw[cluster_id] * 24.0
            cluster_metrics[cluster_id] = {
                "energy_kwh": energy_kwh,
                "capacity_kwh": capacity_kwh,
                "utilization": energy_kwh / capacity_kwh,
            }
            if (
                request_count in QUALITY_CONTROLLED_SCENARIOS
                and not 0.60 <= cluster_metrics[cluster_id]["utilization"] <= 0.90
            ):
                raise ValueError(
                    f"Scenario {request_count}, cụm {cluster_id} ngoài dải tải mục tiêu 60–90%: "
                    f"{cluster_metrics[cluster_id]['utilization']:.4%}"
                )
        if request_count >= 2500 and total_kwh <= sum(
            value["capacity_kwh"] for value in cluster_metrics.values()
        ):
            raise ValueError(
                f"Scenario {request_count} được gắn nhãn quá tải nhưng nhu cầu không vượt trần 24h."
            )
        scenario_summaries.append(
            (
                request_count,
                scenario_type(request_count),
                total_kwh,
                cluster_metrics,
                physical_max_by_cluster,
                connector_mismatch_count,
                float(np.mean(request_energies)),
                min(request_energies),
                max(request_energies),
            )
        )

    print(
        "Kịch bản | Loại | Requests | Tổng kWh | Tải 24h | TB/xe | Min/xe | Max/xe | "
        "Sai đầu nối | Tải theo cụm"
    )
    for (
        request_count,
        scenario_label,
        total_kwh,
        metrics,
        physical_limits,
        connector_mismatch_count,
        mean_kwh,
        min_kwh,
        max_kwh,
    ) in scenario_summaries:
        total_capacity = sum(value["capacity_kwh"] for value in metrics.values())
        utilization = total_kwh / total_capacity if total_capacity else 0.0
        target_total = sum(
            TARGET_CLUSTER_UTILIZATION * value["capacity_kwh"]
            for value in metrics.values()
        )
        physical_max_total = sum(physical_limits.values())
        per_cluster = "; ".join(
            f"C{cluster_id}: {value['energy_kwh']:.1f}/{value['capacity_kwh']:.0f} kWh "
            f"({value['utilization']:.1%})"
            for cluster_id, value in metrics.items()
        )
        print(
            f"{request_count:>5} | {scenario_label:<25} | {request_count:>8} | "
            f"{total_kwh:>9.1f} | {utilization:>7.1%} | {mean_kwh:>6.2f} | "
            f"{min_kwh:>6.2f} | {max_kwh:>6.2f} | {connector_mismatch_count:>11} | {per_cluster}"
        )
        if request_count == 100 and physical_max_total < 0.60 * total_capacity:
            print(
                f"  Giới hạn vật lý của {request_count} requests tối đa: "
                f"{physical_max_total:.1f}/{total_capacity:.0f} kWh "
                f"({physical_max_total / total_capacity:.1%}); dưới 60% ngay cả khi mỗi xe đạt mức tối đa."
            )
        if request_count in QUALITY_CONTROLLED_SCENARIOS:
            print(
                f"  Nhu cầu được lấy độc lập theo xe rồi hiệu chỉnh theo cụm về "
                f"{TARGET_CLUSTER_UTILIZATION:.0%} tải 24h (giữ biến thiên cá nhân)."
            )
        if request_count == 10000:
            print(
                "  LLF_THROUGHPUT_ONLY: bài test thông lượng trong kịch bản quá tải, "
                "không dùng để đánh giá chất lượng điều phối."
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
