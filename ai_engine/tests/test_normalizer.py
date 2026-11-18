"""Kiểm tra biên thời gian, biểu giá và cổng khóa của normalizer."""

import json
from pathlib import Path
from typing import Any

import pytest

from ai_engine.normalizer import iso_to_slot, normalize, slot_to_iso, to_response_slots
from ai_engine.schemas import OptimizeRequest


@pytest.fixture
def data() -> dict[str, Any]:
    """Đọc lại snapshot mẫu cho từng phép thử."""
    sample = Path(__file__).resolve().parents[1] / "samples/input_snapshot.json"
    return json.loads(sample.read_text(encoding="utf8"))


def test_sample(data: dict[str, Any]) -> None:
    """Đối chiếu dữ liệu từ snapshot tới lịch trả Backend."""
    data["snapshot_time"] = "2026-11-18T08:07:59+07:00"
    problem = normalize(OptimizeRequest.model_validate(data))
    assert (problem.T, problem.dt, problem.first_mutable_slot) == (4, 0.25, 1)
    assert problem.t0_time.minute == 0
    assert problem.price == (2000,) * 4
    car = problem.requests["R-01"]
    assert (car.remaining_kwh, car.candidate_ports, car.feasible_max_kw) == (5, ("P-01",), 20)
    assert car.active_slots == range(4)
    assert problem.requests["R-02"].active_slots == range(1, 4)
    for slot in range(-1, 5):
        assert iso_to_slot(slot_to_iso(slot, problem.t0_time), problem.t0_time) == slot
    rows = to_response_slots(problem, [("R-01", "P-01", 1, 20)])
    assert rows[0].slot_start.isoformat() == "2026-11-18T08:15:00+07:00"


@pytest.mark.parametrize("split", ["24:00", "00:00"])
def test_midnight(data: dict[str, Any], split: str) -> None:
    """Cắt giờ đỗ và giờ mở cửa qua đêm, chuyển đúng giá lúc nửa đêm."""
    data["snapshot_time"] = "2026-11-18T23:39:00+07:00"
    data["tariffs"] = [
        dict(start_time="21:00", end_time=split, price_vnd_kwh=3000),
        dict(start_time="00:00", end_time="21:00", price_vnd_kwh=1000)]
    data["stations"][0].update(open_time="2026-11-18T23:31:00+07:00", close_time="2026-11-19T00:29:00+07:00")
    data["requests"][0].update(arrival_time="2026-11-18T23:46:00+07:00", departure_time="2026-11-19T00:28:00+07:00")
    problem = normalize(OptimizeRequest.model_validate(data))
    assert problem.price == (3000, 3000, 1000, 1000)
    assert problem.stations["ST-01"].open_slots == range(1, 3)
    car = problem.requests["R-01"]
    assert (car.arrival_slot, car.departure_slot, list(car.active_slots)) == (2, 3, [2])


def test_recurring_overnight(data: dict[str, Any]) -> None:
    """Biểu giá qua đêm áp dụng cả phần kéo dài từ ngày hôm trước."""
    data["tariffs"] = [
        dict(start_time="22:00", end_time="08:05", price_vnd_kwh=3000),
        dict(start_time="08:05", end_time="22:00", price_vnd_kwh=1500)]
    assert normalize(OptimizeRequest.model_validate(data)).price == (2000, 1500, 1500, 1500)


@pytest.mark.parametrize("start, error", [("08:01", "Thiếu giá"), ("07:59", "chồng lấn")])
def test_invalid_prices(data: dict[str, Any], start: str, error: str) -> None:
    """Phát hiện lỗ hổng hoặc chồng lấn trong một slot."""
    data["tariffs"] = [
        dict(start_time="22:00", end_time="08:01", price_vnd_kwh=1),
        dict(start_time=start, end_time="22:00", price_vnd_kwh=2)]
    if error == "Thiếu giá":
        data["tariffs"][0]["end_time"] = "08:00"
    with pytest.raises(ValueError, match=error):
        normalize(OptimizeRequest.model_validate(data))


def test_lost_and_incompatible(data: dict[str, Any]) -> None:
    """Cổng thay thế phải hoạt động, đúng trạm và đầu nối."""
    ports = data["stations"][0]["ports"]
    ports[0]["status"] = "OFFLINE"
    ports.append(dict(ports[0], port_id="backup", status="ACTIVE"))
    data["requests"][2]["connector_type"] = "CHAdeMO"
    problem = normalize(OptimizeRequest.model_validate(data))
    locked = problem.requests["R-01"]
    assert (locked.port_lost, locked.candidate_ports, locked.replacement_ports) == (True, (), ("backup",))
    unmatched = problem.requests["R-03"]
    assert not unmatched.candidate_ports and not unmatched.port_lost
    assert locked.feasible_max_kw == unmatched.feasible_max_kw == 0


@pytest.mark.parametrize("status", ["DONE", "CANCELLED", "NO_SHOW", "FAILED", "CHARGING"])
def test_skipped(data: dict[str, Any], status: str) -> None:
    """Ghi lại kết quả bằng không cho xe đóng phiên hoặc đã sạc đủ."""
    data["requests"][0]["status"] = status
    if status == "CHARGING":
        data["requests"][0]["energy_delivered_kwh"] = 12
    problem = normalize(OptimizeRequest.model_validate(data))
    assert "R-01" not in problem.requests
    assert problem.skipped_results["R-01"] == (0, 0)
