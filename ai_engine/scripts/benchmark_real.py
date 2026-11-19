"""Run reproducible API benchmarks against committed CSV scenario data.

The benchmark uses the regenerated data commit directly so it does not depend
on which data branch happens to be checked out. Each cluster is submitted as
its own POST /ai/benchmark snapshot, then cluster KPI are combined by request
count and by slot. The CSV lacks delivered-energy and priority fields, so the
benchmark uses 0 kWh delivered and priority 1.0, matching the prior baseline.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import subprocess
from collections import Counter, defaultdict
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from ai_engine.main import app


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "ai_engine" / "benchmark_real.json"
SEED = 42
SCENARIOS = (100, 500, 1000, 10000)
ALL_ALGORITHMS = ("MILP_MPC", "LP_MPC", "LLF", "EDF", "FCFS", "EQUAL_SHARE", "ASAP")
# MILP_MPC is included at 10k because the configured request threshold routes
# it directly to the bounded LLF path before constructing a solver model.
FAST_ALGORITHMS_10000 = ("MILP_MPC", "LLF", "EDF", "FCFS", "EQUAL_SHARE", "ASAP")
LOCAL_TZ = timezone(timedelta(hours=7))
SLOT = timedelta(minutes=15)


def read_csv_at(ref: str, path: str) -> tuple[list[dict[str, str]], bytes]:
    """Read one tracked CSV from a Git ref and keep its exact bytes for hashing."""
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"{ref}:{path}"],
        check=True,
        capture_output=True,
    )
    raw = completed.stdout
    rows = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))
    return rows, raw


def parse_date_time(day: date, value: str) -> datetime:
    """Turn a CSV daily clock into an aware local datetime."""
    hours, minutes = map(int, value.split(":"))
    if hours == 24 and minutes == 0:
        return datetime.combine(day + timedelta(days=1), time(), LOCAL_TZ)
    return datetime.combine(day, time(hours, minutes), LOCAL_TZ)


def iso(value: datetime) -> str:
    return value.isoformat(timespec="seconds")


def read_inputs(ref: str) -> tuple[dict[str, list[dict[str, str]]], dict[str, str]]:
    files = (
        "grid_cluster.csv",
        "charging_station_cleaned.csv",
        "port_cleaned.csv",
        "tariff_window_cleaned.csv",
        "vehicle_100k.csv",
        "vehicle_model_cleaned.csv",
    )
    tables: dict[str, list[dict[str, str]]] = {}
    hashes: dict[str, str] = {}
    for filename in files:
        path = f"data/{filename}"
        rows, raw = read_csv_at(ref, path)
        tables[filename] = rows
        hashes[path] = hashlib.sha256(raw).hexdigest()
    return tables, hashes


def tariffs_for(
    cluster_id: int,
    tariff_mode: str,
    start: datetime,
    end: datetime,
    tou_rows: list[dict[str, str]],
) -> list[dict[str, Any]]:
    """Build full-horizon fixed or source-CSV weekday/weekend tariff intervals."""
    if tariff_mode == "fixed_2000_vnd_kwh":
        return [{"start_time": iso(start), "end_time": iso(end), "price_vnd_kwh": 2000.0}]

    result: list[dict[str, Any]] = []
    day = start.date()
    while datetime.combine(day, time(), LOCAL_TZ) < end:
        day_type = "WEEKDAY" if day.weekday() < 5 else "WEEKEND"
        rows = [
            row for row in tou_rows
            if int(row["cluster_id"]) == cluster_id and row["day_type"] == day_type
        ]
        if not rows:
            raise ValueError(f"Thiếu biểu giá {day_type} cho cụm {cluster_id} trong CSV nguồn")
        for row in sorted(rows, key=lambda item: item["start_time"]):
            interval_start = parse_date_time(day, row["start_time"])
            interval_end = parse_date_time(day, row["end_time"])
            clipped_start = max(interval_start, start)
            clipped_end = min(interval_end, end)
            if clipped_start < clipped_end:
                result.append({
                    "start_time": iso(clipped_start),
                    "end_time": iso(clipped_end),
                    "price_vnd_kwh": float(row["price_vnd_kwh"]),
                })
        day += timedelta(days=1)

    result.sort(key=lambda item: item["start_time"])
    cursor = start
    for item in result:
        interval_start = datetime.fromisoformat(item["start_time"])
        interval_end = datetime.fromisoformat(item["end_time"])
        if interval_start != cursor:
            raise ValueError(f"Biểu giá bị hở hoặc chồng tại {cursor.isoformat()}")
        cursor = interval_end
    if cursor != end:
        raise ValueError(f"Biểu giá không phủ hết horizon đến {end.isoformat()}")
    return result


def build_scenario(
    count: int,
    tables: dict[str, list[dict[str, str]]],
    hashes: dict[str, str],
    dataset_ref: str,
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, Any]]:
    scenario_path = f"data/scenario_{count}_requests.csv"
    scenario_rows, scenario_bytes = read_csv_at(dataset_ref, scenario_path)
    if len(scenario_rows) != count:
        raise ValueError(f"{scenario_path}: expected {count} rows, found {len(scenario_rows)}")
    hashes[scenario_path] = hashlib.sha256(scenario_bytes).hexdigest()

    clusters = {
        int(row["cluster_id"]): float(row["grid_limit_kw"])
        for row in tables["grid_cluster.csv"]
        if row["grid_limit_kw"]
    }
    stations = {
        int(row["station_id"]): row
        for row in tables["charging_station_cleaned.csv"]
        if row["status"] == "ACTIVE"
    }
    ports_by_station: dict[int, list[dict[str, str]]] = defaultdict(list)
    active_connectors_by_station: dict[int, set[str]] = defaultdict(set)
    active_port_count = 0
    for port in tables["port_cleaned.csv"]:
        station_id = int(port["station_id"])
        ports_by_station[station_id].append(port)
        if port["status"] == "ACTIVE":
            active_connectors_by_station[station_id].add(port["connector_type"])
            active_port_count += 1
    vehicles = {
        int(row["vehicle_id"]): int(row["model_id"])
        for row in tables["vehicle_100k.csv"]
    }
    models = {
        int(row["model_id"]): row
        for row in tables["vehicle_model_cleaned.csv"]
    }
    requests_by_cluster: dict[str, list[dict[str, Any]]] = defaultdict(list)
    demand_by_cluster: Counter[int] = Counter()
    connector_mismatches = 0
    long_stay_requests = 0
    active_station_ids: set[int] = set()
    first_arrival: datetime | None = None
    last_departure: datetime | None = None

    for row in scenario_rows:
        cluster_id = int(row["cluster_id"])
        station_id = int(row["station_id"])
        station = stations.get(station_id)
        if station is None or int(station["cluster_id"]) != cluster_id:
            raise ValueError(f"Request {row['request_id']} references a non-active/wrong-cluster station")
        vehicle_model = models[vehicles[int(row["vehicle_id"])]]
        connector = vehicle_model["connector_type"]
        arrival = datetime.fromisoformat(row["arrival_time"])
        departure = datetime.fromisoformat(row["departure_time"])
        if first_arrival is None or arrival < first_arrival:
            first_arrival = arrival
        if last_departure is None or departure > last_departure:
            last_departure = departure
        if (departure - arrival) >= timedelta(hours=8):
            long_stay_requests += 1
        if connector not in active_connectors_by_station[station_id]:
            connector_mismatches += 1
        active_station_ids.add(station_id)
        energy = float(row["energy_needed_kwh"])
        demand_by_cluster[cluster_id] += energy
        requests_by_cluster[str(cluster_id)].append({
            "request_id": int(row["request_id"]),
            "station_id": station_id,
            "connector_type": connector,
            "battery_capacity_kwh": float(row["battery_kwh_snapshot"]),
            "current_soc_pct": float(row["soc_now"]),
            "vehicle_max_kw": float(row["max_kw_snapshot"]),
            "arrival_time": row["arrival_time"],
            "departure_time": row["departure_time"],
            "energy_needed_kwh": energy,
            "energy_delivered_kwh": 0.0,
            "priority_weight": 1.0,
            "status": row["status"],
            "locked_port_id": None,
        })

    if first_arrival is None or last_departure is None:
        raise ValueError(f"{scenario_path} is empty")
    snapshot_time = datetime.combine(first_arrival.date(), time(), LOCAL_TZ)
    horizon_slots = math.ceil((last_departure - snapshot_time).total_seconds() / SLOT.total_seconds())
    horizon_end = snapshot_time + horizon_slots * SLOT
    if horizon_slots <= 0:
        raise ValueError("Scenario horizon must contain at least one slot")

    snapshots: dict[str, dict[str, Any]] = {}
    for cluster_text, requests in requests_by_cluster.items():
        cluster_id = int(cluster_text)
        stations_for_cluster = [
            station for station in stations.values()
            if int(station["cluster_id"]) == cluster_id
        ]
        station_payloads = []
        for station in stations_for_cluster:
            if station["is_24h"].lower() != "true":
                raise ValueError(
                    f"Station {station['station_id']} is not 24h; the AI snapshot schema cannot represent a daily opening recurrence"
                )
            station_id = int(station["station_id"])
            station_payloads.append({
                "station_id": station_id,
                "station_power_kw": float(station["station_power_kw"]),
                "open_time": iso(snapshot_time),
                "close_time": iso(horizon_end),
                "ports": [
                    {
                        "port_id": int(port["port_id"]),
                        "connector_type": port["connector_type"],
                        "control_type": port["control_type"],
                        "min_power_kw": float(port["min_power_kw"]),
                        "max_power_kw": float(port["max_power_kw"]),
                        "status": port["status"],
                    }
                    for port in ports_by_station[station_id]
                ],
            })
        snapshots[cluster_text] = {
            "cluster_id": cluster_id,
            "input_version": f"scenario-{count}-cluster-{cluster_id}",
            "snapshot_time": iso(snapshot_time),
            "slot_minutes": 15,
            "horizon_slots": horizon_slots,
            "grid_limit_kw": clusters[cluster_id],
            "stations": station_payloads,
            "tariffs": [],
            "requests": requests,
        }

    active_clusters = sorted(demand_by_cluster)
    total_capacity = sum(clusters[cluster] * 24.0 for cluster in active_clusters)
    metadata = {
        "request_count": count,
        "requests_by_cluster": {str(cluster): len(requests_by_cluster[str(cluster)]) for cluster in active_clusters},
        "demand_kwh": sum(demand_by_cluster.values()),
        "capacity_kwh": total_capacity,
        "utilization_ratio": sum(demand_by_cluster.values()) / total_capacity,
        "demand_kwh_by_cluster": {str(cluster): demand_by_cluster[cluster] for cluster in active_clusters},
        "capacity_kwh_by_cluster": {
            str(cluster): clusters[cluster] * 24.0 for cluster in active_clusters
        },
        "utilization_ratio_by_cluster": {
            str(cluster): demand_by_cluster[cluster] / (clusters[cluster] * 24.0)
            for cluster in active_clusters
        },
        "long_stay_8h_or_more_count": long_stay_requests,
        "active_station_count": len(active_station_ids),
        "active_port_count_in_catalog": active_port_count,
        "vehicle_connector_without_matching_active_port_count": connector_mismatches,
        "scenario_sha256": hashes[scenario_path],
        "horizon_slots": horizon_slots,
        "horizon_end": iso(horizon_end),
    }
    return snapshots, metadata


def aggregate_algorithm(
    cluster_responses: dict[str, dict[str, Any]],
    request_counts: dict[str, int],
    algorithm: str,
) -> dict[str, Any]:
    cluster_runs: dict[str, dict[str, Any]] = {}
    all_statuses: list[str] = []
    actual_algorithms: set[str] = set()
    total_shortfall = 0.0
    total_cost = 0.0
    total_solve_ms = 0.0
    total_cap_violations = 0
    weighted_on_time = 0.0
    total_requests = 0
    load_by_slot: Counter[str] = Counter()

    for cluster_id, response in cluster_responses.items():
        result = next(
            run["result"] for run in response["results"]
            if run["algorithm"] == algorithm
        )
        kpi = result["kpi"]
        count = request_counts[cluster_id]
        status = result["status"]
        all_statuses.append(status)
        if result["algorithm"]:
            actual_algorithms.add(result["algorithm"])
        total_shortfall += kpi["total_shortfall_kwh"]
        total_cost += kpi["total_cost_vnd"]
        total_solve_ms += result["solve_ms"]
        total_cap_violations += kpi["cap_violations"]
        weighted_on_time += kpi["on_time_rate"] * count
        total_requests += count
        for item in result["schedules"]:
            load_by_slot[item["slot_start"]] += item["power_kw"]
        cluster_runs[cluster_id] = {
            "status": status,
            "actual_algorithm": result["algorithm"],
            "solve_ms": result["solve_ms"],
            "request_count": count,
            "kpi": kpi,
        }

    statuses = sorted(set(all_statuses))
    return {
        "requested_algorithm": algorithm,
        "actual_algorithms": sorted(actual_algorithms),
        "status": statuses[0] if len(statuses) == 1 else "MIXED",
        "status_by_cluster": {cluster: row["status"] for cluster, row in cluster_runs.items()},
        "solve_ms": total_solve_ms,
        "kpi": {
            "on_time_rate": weighted_on_time / total_requests if total_requests else 1.0,
            "total_shortfall_kwh": total_shortfall,
            "total_cost_vnd": total_cost,
            "peak_power_kw": max(load_by_slot.values(), default=0.0),
            "cap_violations": total_cap_violations,
        },
        "cluster_results": cluster_runs,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dataset-ref",
        default="d067916",
        help="Git ref containing the latest develop scenarios and catalog after PR #24 (default: d067916)",
    )
    args = parser.parse_args()
    tables, hashes = read_inputs(args.dataset_ref)
    client = TestClient(app)
    milestones = []

    for count in SCENARIOS:
        snapshots, scenario = build_scenario(count, tables, hashes, args.dataset_ref)
        tariff_results = []
        algorithms = FAST_ALGORITHMS_10000 if count == 10000 else ALL_ALGORITHMS
        request_counts = scenario["requests_by_cluster"]
        for tariff_mode in ("fixed_2000_vnd_kwh", "evn_tou_1600_2400_4000_vnd_kwh"):
            responses = {}
            for cluster_id, snapshot in snapshots.items():
                snapshot["tariffs"] = tariffs_for(
                    int(cluster_id),
                    tariff_mode,
                    datetime.fromisoformat(snapshot["snapshot_time"]),
                    datetime.fromisoformat(snapshot["snapshot_time"])
                    + int(snapshot["horizon_slots"]) * SLOT,
                    tables["tariff_window_cleaned.csv"],
                )
                response = client.post("/ai/benchmark", json={
                    "scenario_id": f"scenario-{count}-cluster-{cluster_id}-{tariff_mode}",
                    "algorithms": list(algorithms),
                    "seed": SEED,
                    "repeats": 1,
                    "snapshot": snapshot,
                })
                if response.status_code != 200:
                    raise RuntimeError(
                        f"POST /ai/benchmark returned {response.status_code}: {response.text}"
                    )
                responses[cluster_id] = response.json()
            tariff_results.append({
                "tariff": tariff_mode,
                "algorithms": [
                    aggregate_algorithm(responses, request_counts, algorithm)
                    for algorithm in algorithms
                ],
            })
        milestones.append({**scenario, "tariffs": tariff_results})

    report = {
        "title": "EV ShareGrid AI Engine measured benchmark",
        "measured_on": datetime.now(LOCAL_TZ).date().isoformat(),
        "seed": SEED,
        "source": {
            "dataset_ref": args.dataset_ref,
            "scenario_generation_seed": SEED,
            "benchmark_seed": SEED,
            "request_files": [f"data/scenario_{count}_requests.csv" for count in SCENARIOS],
            "catalog_files": [path for path in hashes if "/scenario_" not in path],
            "scenario_files": [path for path in hashes if "/scenario_" in path],
            "sha256": hashes,
            "assumptions": {
                "energy_delivered_kwh": 0.0,
                "priority_weight": 1.0,
                "station_hours": "Active stations in source catalog are marked 24h.",
                "connector_mismatch": "Requests retain the vehicle model connector; mismatches remain unmet and are counted in KPI.",
                "cluster_execution": "Separate POST /ai/benchmark calls per cluster; aggregate cost, shortfall, solve_ms and violations by sum, on-time rate by request count, and peak from combined per-slot schedules.",
            },
            "endpoint_client": "FastAPI TestClient POST /ai/benchmark",
        },
        "tariffs": {
            "fixed_2000_vnd_kwh": {"price_vnd_kwh": 2000.0},
            "evn_tou_1600_2400_4000_vnd_kwh": {
                "source": "data/tariff_window_cleaned.csv",
                "rates_vnd_kwh": [1600.0, 2400.0, 4000.0],
            },
        },
        "algorithms": list(ALL_ALGORITHMS),
        "algorithms_at_10000_requests": list(FAST_ALGORITHMS_10000),
        "milestones": milestones,
    }
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
    for milestone in milestones:
        print(
            f"{milestone['request_count']:>5} requests: "
            f"{milestone['demand_kwh']:.12g} kWh / "
            f"{milestone['capacity_kwh']:.12g} kWh = "
            f"{milestone['utilization_ratio']:.12%}; "
            f"long-stay >=8h: {milestone['long_stay_8h_or_more_count']}"
        )
        for tariff in milestone["tariffs"]:
            for result in tariff["algorithms"]:
                if result["requested_algorithm"] == "LLF":
                    print(
                        f"  {tariff['tariff']} LLF solve_ms={result['solve_ms']!r} "
                        f"status={result['status']} shortfall_kwh={result['kpi']['total_shortfall_kwh']!r}"
                    )


if __name__ == "__main__":
    main()
