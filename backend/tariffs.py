"""EVN Time-of-Use (TOU) tariff configuration and utilities."""
from __future__ import annotations

from datetime import date, datetime
from typing import Any
from zoneinfo import ZoneInfo

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")

# EVN 2026 3-tier rates (VND/kWh)
RATE_OFF_PEAK = 1620.0
RATE_NORMAL = 2700.0
RATE_PEAK = 4212.0

TIER_OFF_PEAK = "OFF_PEAK"
TIER_NORMAL = "NORMAL"
TIER_PEAK = "PEAK"


def get_tou_tier(dt: datetime) -> tuple[str, float]:
    """Return (tier, price_vnd_kwh) for a given datetime according to EVN 2026 TOU rules in VN time."""
    if dt.tzinfo is not None:
        local_dt = dt.astimezone(VN_TZ)
    else:
        local_dt = dt.replace(tzinfo=VN_TZ)

    weekday = local_dt.weekday()  # 0: Mon, ..., 6: Sun
    hour_val = local_dt.hour + local_dt.minute / 60.0

    # 00:00 - 06:00 is off-peak every day
    if hour_val < 6.0:
        return TIER_OFF_PEAK, RATE_OFF_PEAK

    # Sunday: Normal all day from 06:00 to 24:00 (no peak)
    if weekday == 6:
        return TIER_NORMAL, RATE_NORMAL

    # Monday to Saturday:
    # Peak: 17:30 - 22:30
    if 17.5 <= hour_val < 22.5:
        return TIER_PEAK, RATE_PEAK

    # Normal: 06:00 - 17:30 and 22:30 - 24:00
    return TIER_NORMAL, RATE_NORMAL


def get_24h_tariff_schedule() -> list[dict[str, Any]]:
    """Return standard 24-hour tariff breakdown (0h to 23h) for weekday/standard TOU."""
    schedule = []
    for h in range(24):
        # Sample mid-hour for tier determination on standard weekday (Monday)
        sample_dt = datetime(2026, 11, 23, h, 30, tzinfo=VN_TZ)
        tier, price = get_tou_tier(sample_dt)
        schedule.append({
            "hour": h,
            "start_time": f"{h:02d}:00",
            "end_time": f"{(h + 1):02d}:00",
            "tariff_tier": tier,
            "vnd_per_kwh": price,
        })
    return schedule
