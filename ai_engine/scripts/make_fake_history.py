"""Lịch sử giả theo giờ để kiểm thử dự báo lượt xe đến."""

import argparse
import sys
import csv
from datetime import datetime, timedelta, timezone
from pathlib import Path
from random import Random


if __name__ == "__main__":
    if not __package__:
        # Allow direct invocation from PowerShell as well as python -m.
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from ai_engine.console import configure_console

    configure_console()


def make_history(months: int = 4, seed: int = 42) -> list[dict[str, str | int]]:
    """Sinh 90–180 ngày, có chu kỳ tuần, cao điểm chiều và nhiễu có seed."""
    if not 3 <= months <= 6:
        raise ValueError("months phải từ 3 đến 6")
    rng = Random(seed)
    start = datetime(2025, 1, 1, tzinfo=timezone(timedelta(hours=7)))
    rows = []
    for i in range(months * 30 * 24):
        t = start + timedelta(hours=i)
        h, d = t.hour, t.weekday()
        count = 4 + 8*(7 <= h <= 21) + 18*(17 <= h <= 20)
        count += 7*(d >= 5 and 9 <= h <= 15) - 5*(d >= 5 and 17 <= h <= 20)
        count += (d % 5)*2 if d < 5 else 0
        rows.append(dict(hour_start=t.isoformat(), arrivals=max(0, round(count+rng.gauss(0,2)))))
    return rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--months", type=int, default=4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output", type=Path, default=Path("history.csv"))
    args = parser.parse_args()
    # A UTF-8 BOM lets Excel detect the encoding when opening the CSV directly.
    with args.output.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["hour_start", "arrivals"])
        writer.writeheader()
        writer.writerows(make_history(args.months, args.seed))
