from datetime import date, datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

import pytest

from backend.ai_contract import (
    build_cluster_snapshot,
    pick_request_result,
    to_ai_connector,
)


TZ = ZoneInfo("Asia/Ho_Chi_Minh")


class SnapshotCursor:
    def __init__(self):
        self.one = None
        self.many = []
        self.executed = []

    def execute(self, query, params=()):
        normalized = " ".join(query.split())
        self.executed.append((normalized, params))
        self.one = None
        self.many = []
        if "FROM grid_cluster" in normalized:
            self.one = {"cluster_id": 7, "grid_limit_kw": Decimal("12"), "timezone": "Asia/Ho_Chi_Minh"}
        elif "FROM charging_station" in normalized:
            self.many = [{
                "station_id": 10,
                "station_power_kw": Decimal("12"),
                "open_time": time(0),
                "close_time": time(0),
                "is_24h": True,
            }]
        elif "FROM port p" in normalized:
            self.many = [{
                "port_id": 20,
                "station_id": 10,
                "connector_type": "CCS2_DC",
                "control_type": "CONTINUOUS",
                "status": "OCCUPIED",
                "min_power_kw": Decimal("0"),
                "max_power_kw": Decimal("11"),
            }]
        elif "FROM charging_request cr" in normalized:
            self.many = [{
                "request_id": 31,
                "station_id": 10,
                "arrival_time": datetime(2026, 11, 18, 17, 0, tzinfo=TZ),
                "departure_time": datetime(2026, 11, 18, 18, 0, tzinfo=TZ),
                "battery_kwh_snapshot": Decimal("60"),
                "max_kw_snapshot": Decimal("11"),
                "energy_needed_kwh": Decimal("12.345678"),
                "priority_weight": Decimal("1"),
                "status": "CHARGING",
                "connector_type": "CCS2_DC",
                "energy_delivered_kwh": Decimal("2.5"),
                "locked_port_id": 20,
            }]
        elif "FROM schedule sc" in normalized:
            self.many = [
                {
                    "request_id": 31,
                    "port_id": 20,
                    "slot_start": datetime(2026, 11, 18, 16, 45, tzinfo=TZ),
                    "power_kw": Decimal("2"),
                },
                {
                    "request_id": 31,
                    "port_id": 20,
                    "slot_start": datetime(2026, 11, 18, 17, 0, tzinfo=TZ),
                    "power_kw": Decimal("2"),
                },
            ]
        elif "FROM tariff_window" in normalized:
            self.many = [
                {
                    "day_type": "WEEKDAY",
                    "start_time": time(0),
                    "end_time": time(12),
                    "price_vnd_kwh": Decimal("1600"),
                    "valid_from": date(2025, 1, 1),
                    "valid_to": date(2099, 12, 31),
                },
                {
                    "day_type": "WEEKDAY",
                    "start_time": time(12),
                    "end_time": time(0),
                    "price_vnd_kwh": Decimal("2400"),
                    "valid_from": date(2025, 1, 1),
                    "valid_to": date(2099, 12, 31),
                },
            ]
        else:
            raise AssertionError(f"Unexpected SQL: {normalized}")

    def fetchone(self):
        return self.one

    def fetchall(self):
        return self.many


@pytest.mark.parametrize(
    ("source", "expected"),
    [
        ("CCS2_DC", "CCS2"),
        ("CCS2", "CCS2"),
        ("AC_HOME_VINFAST_ADAPTER", "AC_HOME"),
        ("AC_HOME", "AC_HOME"),
        ("Type2", "Type2"),
        ("CHAdeMO", "CHAdeMO"),
    ],
)
def test_to_ai_connector_maps_catalog_values(source, expected):
    assert to_ai_connector(source) == expected


def test_to_ai_connector_rejects_unknown_name_clearly():
    with pytest.raises(ValueError, match="Unsupported connector_type.*CCS2.*Type2"):
        to_ai_connector("TeslaSuperPlug")


def test_build_cluster_snapshot_matches_ai_contract_and_only_freezes_elapsed_slots():
    cursor = SnapshotCursor()
    now = datetime(2026, 11, 18, 17, 7, tzinfo=TZ)

    snapshot = build_cluster_snapshot(cursor, 7, 42, snapshot_time=now)

    assert snapshot["cluster_id"] == "7"
    assert snapshot["input_version"] == 42
    assert snapshot["slot_minutes"] == 15
    assert snapshot["requests"][0]["connector_type"] == "CCS2"
    assert snapshot["requests"][0]["energy_needed_kwh"] == 12.345678
    assert snapshot["requests"][0]["energy_delivered_kwh"] == 2.5
    assert snapshot["requests"][0]["locked_port_id"] == "20"
    assert snapshot["stations"][0]["ports"][0]["status"] == "ACTIVE"
    assert [slot["slot_start"] for slot in snapshot["previous_schedule"]] == [
        "2026-11-18T16:45:00+07:00"
    ]
    assert snapshot["tariffs"][0]["start_time"] == "2026-11-18T17:07:00+07:00"
    assert snapshot["tariffs"][-1]["end_time"] == (
        now + timedelta(hours=24)
    ).isoformat(timespec="seconds")


def test_pick_request_result_matches_numeric_and_string_ids():
    body = {"request_results": [{"request_id": "31", "shortfall_kwh": 1.25}]}

    assert pick_request_result(body, 31) == {"request_id": "31", "shortfall_kwh": 1.25}
    with pytest.raises(LookupError, match="request_id=32"):
        pick_request_result(body, 32)
