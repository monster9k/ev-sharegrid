"""Kiểm tra nội dung giải thích theo số liệu thực của từng tình huống."""

from dataclasses import replace

import pytest

from ai_engine.baselines import solve_llf
from ai_engine.explainer import build_all_results, build_explanation
from ai_engine.tests.test_baselines import sample


def test_intervals_price_soc() -> None:
    """Hai slot rẻ liên tiếp có chung khoảng giờ, chi phí và SOC đúng."""
    p = sample()
    r = replace(p.requests["R-01"], remaining_kwh=10)
    src = p.source_requests["R-01"].model_copy(update=dict(energy_needed_kwh=15, current_soc_pct=30,
                                                            battery_capacity_kwh=50))
    p = replace(p, requests={r.request_id:r}, source_requests={r.request_id:src}, price=(5000,2400,2400,5000))
    sol = solve_llf(p)
    result, = build_all_results(p, sol)
    for part in ["P-01", "08:15-08:45", "thấp nhất 2.400đ/kWh", "5 kWh đã nạp", "09:00"]:
        assert part in result.explanation
    assert result.expected_soc == 50 and result.estimated_cost_vnd == 24000


@pytest.mark.parametrize("kind", ["cụm", "trạm"])
def test_actual_caps(kind: str) -> None:
    """Nguyên nhân nêu đúng giới hạn quan sát trong cửa sổ xe."""
    p = sample()
    r = p.requests["R-01"]
    p = replace(p, requests={r.request_id:r}, T=2)
    s = p.stations[r.station_id]
    p = replace(p, grid_limit_kw=8) if kind == "cụm" else replace(p, stations={s.station_id:replace(s,station_power_kw=8)})
    sol = solve_llf(p)
    text = build_explanation(p, sol, r.request_id)
    assert f"{kind} chạm trần 8 kW lúc 08:15" in text
    result, = build_all_results(p, sol)
    assert result.expected_soc == 70 and result.shortfall_kwh == 3


def test_no_ports_skipped_maintenance() -> None:
    """Nêu đúng cổng hỏng, xe đã đủ điện và chuyển cổng có bằng chứng."""
    p = sample()
    r = replace(p.requests["R-01"], candidate_ports=(), port_lost=True)
    p = replace(p, requests={r.request_id:r}, skipped_results={"R-02":(0,0)})
    p.source_requests["R-02"] = p.source_requests["R-02"].model_copy(update={"energy_delivered_kwh":1.75})
    sol = solve_llf(p)
    a,b = build_all_results(p, sol)
    assert "cổng khóa P-01 không hoạt động" in a.explanation
    assert "không cần sạc thêm" in b.explanation and b.shortfall_kwh == 0
    p = sample()
    p.ports["P-02"] = replace(p.ports["P-02"], status="MAINTENANCE")
    p.source_requests["R-01"] = p.source_requests["R-01"].model_copy(update={"previous_port_id":"P-02"})
    assert "thay cổng P-02 đang bảo trì" in build_explanation(p, solve_llf(p), "R-01")

def test_switch_minimum() -> None:
    """Phần thiếu quá nhỏ để bật cổng không bị quy thành quá tải."""
    p = sample()
    r = replace(p.requests["R-02"], remaining_kwh=1)
    p = replace(p, requests={r.request_id:r})
    assert "một slot cần ít nhất 1,75 kWh" in build_explanation(p, solve_llf(p), r.request_id)


def test_busy_port() -> None:
    """Chỉ báo cổng bận khi xe khác thực sự nhận điện trên mọi slot."""
    p = sample()
    r = replace(p.requests["R-01"], remaining_kwh=15)
    waiting = replace(r, request_id="B", locked_port_id=None)
    p = replace(p, requests={r.request_id:r, "B":waiting})
    assert "cấp điện cho xe khác" in build_explanation(p, solve_llf(p), "B")
