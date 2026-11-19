"""Kiểm thử hợp đồng JSON, mẫu tích hợp và các dữ liệu phải bị từ chối."""

from __future__ import annotations

import copy
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from ai_engine import schemas
from ai_engine.schemas import (
    Algorithm, BenchmarkRequest, BenchmarkResponse, ConnectorType, ForecastModel, ForecastRequest,
    ForecastResponse, OptimizeRequest, OptimizeResponse, export_json_schemas,
)

SAMPLES = Path(__file__).resolve().parents[1] / "samples"


@pytest.fixture
def snapshot() -> dict[str, Any]:
    """Đọc bản mẫu mới cho mỗi test để tránh dùng chung trạng thái."""
    return json.loads((SAMPLES / "input_snapshot.json").read_text(encoding="utf-8"))


@pytest.fixture
def output() -> dict[str, Any]:
    """Đọc kết quả mẫu dùng kiểm thử phản hồi."""
    return json.loads((SAMPLES / "output_schedule.json").read_text(encoding="utf-8"))


def test_parse_sample_files() -> None:
    """Hai file mẫu phải parse và tuần tự hóa lại không mất dữ liệu."""
    for filename, model in (
        ("input_snapshot.json", OptimizeRequest), ("output_schedule.json", OptimizeResponse)
    ):
        parsed = model.model_validate_json((SAMPLES / filename).read_text(encoding="utf-8"))
        assert model.model_validate_json(parsed.model_dump_json()) == parsed


@pytest.mark.parametrize(
    ("connector", "canonical"),
    [
        ("CCS2_DC", "CCS2"),
        ("CCS2", "CCS2"),
        ("AC_HOME_VINFAST_ADAPTER", "AC_HOME"),
        ("AC_HOME", "AC_HOME"),
    ],
)
def test_connector_aliases_normalize_in_requests_and_ports(
    snapshot: dict[str, Any], connector: str, canonical: str,
) -> None:
    """Tên đầu nối trong CSV và tên chuẩn đều parse thành cùng enum."""
    data = snapshot
    station_by_id = {str(station["station_id"]): station for station in data["stations"]}
    pair = None
    for request in data["requests"]:
        station = station_by_id[str(request["station_id"])]
        port = next((
            port for port in station["ports"]
            if port["connector_type"] == canonical
        ), None)
        if request["connector_type"] == canonical and port is not None:
            pair = request, port
            break
    if pair is None and canonical == "AC_HOME":
        data = json.loads((SAMPLES / "page20_input.json").read_text(encoding="utf-8"))
        station_by_id = {str(station["station_id"]): station for station in data["stations"]}
        for request in data["requests"]:
            station = station_by_id[str(request["station_id"])]
            port = next((p for p in station["ports"] if p["connector_type"] == canonical), None)
            if request["connector_type"] == canonical and port is not None:
                pair = request, port
                break
    assert pair is not None, f"Thiếu cặp request/cổng {canonical} trong fixture"
    request, port = pair
    request["connector_type"] = connector
    port["connector_type"] = connector

    parsed = OptimizeRequest.model_validate(data)
    parsed_request = next(r for r in parsed.requests if r.request_id == request["request_id"])
    parsed_station = next(s for s in parsed.stations if s.station_id == str(request["station_id"]))
    parsed_port = next(p for p in parsed_station.ports if p.port_id == str(port["port_id"]))
    expected = ConnectorType(canonical)
    assert parsed_request.connector_type == expected
    assert parsed_port.connector_type == expected


def test_unknown_connector_has_clear_validation_error(snapshot: dict[str, Any]) -> None:
    """Tên lạ vẫn bị từ chối với tên trường và các giá trị chuẩn được nêu rõ."""
    snapshot["requests"][0]["connector_type"] = "CCS1"
    with pytest.raises(ValidationError) as error:
        OptimizeRequest.model_validate(snapshot)
    message = str(error.value)
    assert "connector_type" in message and "CCS2" in message and "AC_HOME" in message


def test_sample_topology_and_kpi(snapshot: dict[str, Any], output: dict[str, Any]) -> None:
    """Kiểm tra cấu hình mẫu và số liệu điện năng, chi phí minh họa."""
    request = OptimizeRequest.model_validate(snapshot)
    result = OptimizeResponse.model_validate(output)
    assert len(request.stations) == 2
    assert sum(len(station.ports) for station in request.stations) == 4
    assert sum(item.status == "CHARGING" for item in request.requests) == 1
    assert sum(item.power_kw * 0.25 for item in result.schedules) == 9.5
    assert sum(item.estimated_cost_vnd for item in result.request_results) == result.kpi.total_cost_vnd == 19000
    assert sum(item.power_kw for item in result.schedules) == result.kpi.peak_power_kw == 38
    assert result.schedules[0].port_id == request.requests[0].locked_port_id
    assert all(item.slot_start > request.snapshot_time for item in result.schedules)


@pytest.mark.parametrize(
    ("path", "value", "message"),
    [
        (("slot_minutes",), 30, "15"),
        (("horizon_slots",), 0, "greater than"),
        (("horizon_slots",), 1.5, "integer"),
        (("time_budget_ms",), 0, "greater than"),
        (("grid_limit_kw",), -1, "greater than"),
        (("grid_limit_kw",), float("inf"), "finite"),
        (("requests", 0, "departure_time"), "2026-11-18T07:30:00+07:00", "departure_time"),
        (("requests", 0, "departure_time"), "2026-11-18T07:00:00+07:00", "departure_time"),
        (("requests", 0, "energy_needed_kwh"), -1, "greater than"),
        (("requests", 0, "energy_delivered_kwh"), -1, "greater than"),
        (("requests", 0, "priority_weight"), 0, "greater than"),
        (("requests", 0, "priority_weight"), -1, "greater than"),
        (("requests", 0, "vehicle_max_kw"), 0, "greater than"),
        (("requests", 0, "station_id"), "UNKNOWN", "station_id"),
        (("requests", 1, "request_id"), "R-01", "request_id"),
        (("requests", 0, "request_id"), "   ", "pattern"),
        (("requests", 0, "locked_port_id"), "UNKNOWN", "locked_port_id"),
        (("requests", 0, "locked_port_id"), "P-03", "locked_port_id"),
        (("requests", 0, "locked_port_id"), "P-02", "connector_type"),
        (("requests", 0, "status"), "INVALID", "Input should be"),
        (("requests", 0, "connector_type"), "Tesla", "Input should be"),
        (("stations", 1, "station_id"), "ST-01", "station_id"),
        (("stations", 1, "ports", 0, "port_id"), "P-01", "port_id"),
        (("stations", 0, "ports", 1, "port_id"), "P-01", "port_id"),
        (("stations", 0, "ports", 0, "min_power_kw"), 21, "min_power_kw"),
        (("stations", 0, "ports", 1, "min_power_kw"), 0, "ON_OFF_SWITCH"),
        (("stations", 0, "ports", 0, "status"), "BROKEN", "Input should be"),
        (("stations", 0, "ports", 0, "control_type"), "VARIABLE", "Input should be"),
        (("stations", 0, "close_time"), "2026-11-18T07:00:00+07:00", "close_time"),
        (("tariffs", 0, "end_time"), "2026-11-18T08:00:00+07:00", "end_time"),
        (("tariffs", 0, "price_vnd_kwh"), -1, "greater than"),
        (("snapshot_time",), "2026-11-18T08:00:00", "timezone"),
        (("snapshot_time",), "2026-11-18T01:00:00Z", "timezone"),
        (("snapshot_time",), 1794963600, "ISO-8601"),
        (("snapshot_time",), datetime(2026, 11, 18, tzinfo=timezone.utc), "timezone"),
        (("snapshot_time",), datetime(2026, 11, 18), "timezone"),
        (("snapshot_time",), "2026-02-30T08:00:00+07:00", "valid datetime"),
        (("unknown_field",), 1, "Extra inputs"),
    ],
)
def test_invalid_snapshot(
    snapshot: dict[str, Any], path: tuple[str | int, ...], value: Any, message: str
) -> None:
    """Thay một giá trị để kiểm tra từng quy tắc đầu vào độc lập."""
    target = snapshot
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    with pytest.raises(ValidationError, match=message):
        OptimizeRequest.model_validate(snapshot)


def test_overlapping_tariffs(snapshot: dict[str, Any]) -> None:
    """Các khoảng giá trùng nhau không được chấp nhận."""
    snapshot["tariffs"].append(copy.deepcopy(snapshot["tariffs"][0]))
    with pytest.raises(ValidationError, match="chồng lấn"):
        OptimizeRequest.model_validate(snapshot)


def test_boundary_values_and_non_aligned_snapshot(snapshot: dict[str, Any]) -> None:
    """Giữ dữ liệu phục vụ MPC và nhu cầu đã hoàn thành cho normalizer."""
    snapshot["snapshot_time"] = "2026-11-18T08:07:13+07:00"
    snapshot["requests"][0]["energy_needed_kwh"] = 0
    snapshot["requests"][1]["priority_weight"] = 0.1
    snapshot["requests"][1]["arrival_time"] = "2026-11-18T08:16:37+07:00"
    parsed = OptimizeRequest.model_validate(snapshot)
    assert parsed.requests[0].energy_delivered_kwh > parsed.requests[0].energy_needed_kwh
    assert parsed.snapshot_time.minute == 7


@pytest.mark.parametrize("time", ["08:01:00", "08:15:01", "08:15:00.000001"])
def test_slot_alignment(output: dict[str, Any], time: str) -> None:
    """Đầu slot phải căn chính xác đến phút và giây."""
    output["schedules"][0]["slot_start"] = f"2026-11-18T{time}+07:00"
    with pytest.raises(ValidationError, match="15 phút"):
        OptimizeResponse.model_validate(output)


@pytest.mark.parametrize("minute", ["00", "15", "30", "45"])
def test_valid_slot_boundaries(output: dict[str, Any], minute: str) -> None:
    """Chấp nhận cả bốn mốc slot trong một giờ."""
    output["schedules"][0]["slot_start"] = f"2026-11-18T08:{minute}:00+07:00"
    OptimizeResponse.model_validate(output)


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("status",), "SUCCESS"),
        (("algorithm",), "UNKNOWN"),
        (("solve_ms",), -1),
        (("kpi", "on_time_rate"), 1.01),
        (("kpi", "cap_violations"), -1),
        (("request_results", 0, "expected_soc"), 101),
        (("request_results", 0, "shortfall_kwh"), -1),
        (("request_results", 1, "request_id"), "R-01"),
        (("schedules", 0, "request_id"), "UNKNOWN"),
        (("schedules", 0, "power_kw"), -1),
        (("kpi", "total_cost_vnd"), float("nan")),
    ],
)
def test_invalid_response(output: dict[str, Any], path: tuple[str | int, ...], value: Any) -> None:
    """Phản hồi cũng phải tuân thủ kiểu, enum và miền giá trị."""
    target = output
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    with pytest.raises(ValidationError):
        OptimizeResponse.model_validate(output)


def test_benchmark_roundtrip(snapshot: dict[str, Any], output: dict[str, Any]) -> None:
    """Benchmark nhận snapshot tùy chọn và biểu diễn rõ LLF fallback."""
    request = BenchmarkRequest(scenario_id="demo", algorithms=[Algorithm.MILP], snapshot=snapshot)
    assert request.seed == 42 and request.repeats == 1
    assert BenchmarkRequest(scenario_id="demo", algorithms=[Algorithm.LLF]).snapshot is None
    output["status"] = "FALLBACK"
    response = BenchmarkResponse.model_validate({
        "scenario_id": "demo", "seed": 42, "repeats": 1,
        "results": [{"algorithm": "MILP", "repeat_index": 0, "result": output}],
    })
    assert response.results[0].result.algorithm == Algorithm.LLF
    assert BenchmarkResponse.model_validate_json(response.model_dump_json()) == response


@pytest.mark.parametrize("patch", [
    {"algorithms": []}, {"algorithms": ["LLF", "LLF"]}, {"algorithms": ["UNKNOWN"]},
    {"seed": -1}, {"seed": 4294967296}, {"repeats": 0}, {"repeats": True}, {"snapshot": {}},
])
def test_invalid_benchmark(patch: dict[str, Any]) -> None:
    """Từ chối cấu hình benchmark sai."""
    with pytest.raises(ValidationError):
        BenchmarkRequest.model_validate({"scenario_id": "demo", "algorithms": ["LLF"], **patch})


def test_forecast_defaults_and_response() -> None:
    """Forecast mặc định 24 giờ và cho phép số lượt kỳ vọng thập phân."""
    request = ForecastRequest.model_validate({
        "cluster_id": "C", "history": [{"hour_start": "2026-11-18T08:00:00+07:00", "arrivals": 0}],
    })
    assert request.horizon_hours == 24 and request.model == ForecastModel.HOURLY_MEAN
    start = request.history[0].hour_start + timedelta(hours=1)
    response = ForecastResponse.model_validate({
        "cluster_id": "C", "model": "HOURLY_MEAN", "horizon_hours": 24,
        "predictions": [{"hour_start": start + timedelta(hours=i), "predicted_arrivals": 2.5} for i in range(24)],
    })
    assert ForecastResponse.model_validate_json(response.model_dump_json()) == response


@pytest.mark.parametrize("patch", [
    {"history": []}, {"horizon_hours": 0}, {"model": "LLM"},
    {"history": [{"hour_start": "2026-11-18T08:15:00+07:00", "arrivals": 1}]},
    {"history": [{"hour_start": "2026-11-18T08:00:00+07:00", "arrivals": -1}]},
    {"history": [{"hour_start": "2026-11-18T08:00:00+07:00", "arrivals": 1.5}]},
    {"history": [{"hour_start": "2026-11-18T08:00:00+07:00", "arrivals": 1}] * 2},
])
def test_invalid_forecast(patch: dict[str, Any]) -> None:
    """Từ chối dữ liệu dự báo sai giờ, số lượt hoặc cấu hình."""
    with pytest.raises(ValidationError):
        ForecastRequest.model_validate({
            "cluster_id": "C", "history": [{"hour_start": "2026-11-18T08:00:00+07:00", "arrivals": 1}], **patch,
        })


@pytest.mark.parametrize("hours", [[], [9], [9, 9], [10, 9], [9, 11]])
def test_invalid_forecast_response(hours: list[int]) -> None:
    """Dự báo phải đủ số giờ, không trùng, không đảo thứ tự và không hở giờ."""
    with pytest.raises(ValidationError):
        ForecastResponse.model_validate({
            "cluster_id": "C", "model": "HOURLY_MEAN", "horizon_hours": 2,
            "predictions": [{"hour_start": f"2026-11-18T{hour:02d}:00:00+07:00", "predicted_arrivals": 1} for hour in hours],
        })


def test_field_descriptions() -> None:
    """Mọi trường của mọi model phải có mô tả cho Swagger."""
    for candidate in vars(schemas).values():
        if isinstance(candidate, type) and issubclass(candidate, schemas.APIModel):
            assert all(field.description for field in candidate.model_fields.values())


def test_exported_schemas(tmp_path: Path) -> None:
    """Schema giao Backend phải khớp model và mọi $ref phải tồn tại cục bộ."""
    exported = export_json_schemas(tmp_path / "openapi_schemas.json")
    payload = json.loads(exported.read_text(encoding="utf-8"))
    checked_in = json.loads((SAMPLES / "openapi_schemas.json").read_text(encoding="utf-8"))
    assert checked_in == payload
    assert set(payload["schemas"]) == {model.__name__ for model in schemas.API_SCHEMAS}
    for schema in payload["schemas"].values():
        pending: list[Any] = [schema]
        while pending:
            node = pending.pop()
            if isinstance(node, dict):
                if "$ref" in node:
                    reference = node["$ref"]
                    assert reference.startswith("#/$defs/")
                    assert reference.removeprefix("#/$defs/") in schema["$defs"]
                pending.extend(node.values())
            elif isinstance(node, list):
                pending.extend(node)
