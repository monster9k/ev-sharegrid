import csv
from datetime import datetime

from ai_engine.scripts.benchmark_real import LOCAL_TZ, ROOT, tariffs_for


def test_benchmark_tariffs_cover_saturday_peak_and_sunday():
    with (ROOT / "data" / "tariff_window_cleaned.csv").open(encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))
    start = datetime(2026, 11, 21, 17, 30, tzinfo=LOCAL_TZ)
    end = datetime(2026, 11, 22, 22, 30, tzinfo=LOCAL_TZ)
    windows = tariffs_for(1, "evn_tou_1620_2700_4212_vnd_kwh", start, end, rows)
    assert [window["price_vnd_kwh"] for window in windows] == [4212, 2700, 1620, 2700]
    assert windows[1]["end_time"] == windows[2]["start_time"] == "2026-11-22T00:00:00+07:00"
