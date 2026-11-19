"""Measure only the 10,000-request LLF throughput scenario from local data."""

from __future__ import annotations

import csv
import json
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from fastapi.testclient import TestClient

import ai_engine.scripts.benchmark_real as benchmark
from ai_engine.main import app


OUTPUT = ROOT / "data" / "scenario_10000_llf_measurement.json"
SEED = 42
REQUEST_COUNT = 10000
LOCAL_TZ = benchmark.LOCAL_TZ


def read_local_data(_ref: str, relative_path: str):
    """Read the current working-tree CSV rather than an older Git revision."""
    raw = (ROOT / relative_path).read_bytes()
    rows = list(csv.DictReader(raw.decode("utf-8-sig").splitlines()))
    return rows, raw


def main() -> None:
    benchmark.read_csv_at = read_local_data
    tables, hashes = benchmark.read_inputs("working-tree")
    snapshots, scenario = benchmark.build_scenario(
        REQUEST_COUNT, tables, hashes, "working-tree"
    )
    client = TestClient(app)
    responses = {}

    for cluster_text, snapshot in snapshots.items():
        start = datetime.fromisoformat(snapshot["snapshot_time"])
        end = start + snapshot["horizon_slots"] * benchmark.SLOT
        snapshot["tariffs"] = benchmark.tariffs_for(
            int(cluster_text),
            "fixed_2000_vnd_kwh",
            start,
            end,
            tables["tariff_window_cleaned.csv"],
        )
        response = client.post(
            "/ai/benchmark",
            json={
                "scenario_id": f"scenario-10000-cluster-{cluster_text}-llf-throughput",
                "algorithms": ["LLF"],
                "seed": SEED,
                "repeats": 1,
                "snapshot": snapshot,
            },
        )
        if response.status_code != 200:
            raise RuntimeError(
                f"POST /ai/benchmark returned {response.status_code}: {response.text}"
            )
        responses[cluster_text] = response.json()

    result = benchmark.aggregate_algorithm(
        responses, scenario["requests_by_cluster"], "LLF"
    )
    report = {
        "label": "LLF_THROUGHPUT_ONLY",
        "purpose": "10,000-request throughput test; not a dispatch-quality result",
        "measured_at": datetime.now(LOCAL_TZ).isoformat(timespec="seconds"),
        "seed": SEED,
        "request_count": REQUEST_COUNT,
        "source_csv": "data/scenario_10000_requests.csv",
        "source_csv_sha256": hashes["data/scenario_10000_requests.csv"],
        "request_demand_kwh": scenario["demand_kwh"],
        "cluster_capacity_24h_kwh": scenario["capacity_kwh"],
        "input_demand_ratio": scenario["utilization_ratio"],
        "requests_by_cluster": scenario["requests_by_cluster"],
        "benchmark_endpoint": "POST /ai/benchmark",
        "tariff_mode": "fixed_2000_vnd_kwh",
        "algorithm": result,
        "measurement_notes": {
            "solve_ms": "Sum of measured solver times for the two cluster requests.",
            "cap_violations": "Validator KPI reported by the AI Engine.",
            "machine_dependent": True,
        },
    }
    OUTPUT.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    kpi = result["kpi"]
    print(
        f"{REQUEST_COUNT} requests | demand={scenario['demand_kwh']:.4f} kWh | "
        f"input_ratio={scenario['utilization_ratio']:.4%} | "
        f"algorithm={','.join(result['actual_algorithms'])} | status={result['status']} | "
        f"solve_ms={result['solve_ms']!r} | cap_violations={kpi['cap_violations']} | "
        f"shortfall_kwh={kpi['total_shortfall_kwh']!r} | "
        f"on_time_rate={kpi['on_time_rate']!r}"
    )
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
