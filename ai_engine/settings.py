"""Đọc cấu hình service khi khởi động."""
import os


EPS_KWH = EPS_KW = 1e-6


def is_zero(value: float, eps: float = EPS_KWH) -> bool:
    return abs(value) <= eps


def is_leq(a: float, b: float, eps: float = EPS_KWH) -> bool:
    return a <= b + eps


def snap(value: float, eps: float = EPS_KWH) -> float:
    return 0.0 if is_zero(value, eps) else value


def positive(name: str, default: int) -> int:
    """Đọc số nguyên dương từ biến môi trường."""
    value = int(os.getenv(name, str(default)))
    if value < 1:
        raise ValueError(f"{name} phải lớn hơn 0")
    return value


WORKERS = positive("WORKERS", 1)
DEFAULT_TIME_BUDGET_MS = positive("DEFAULT_TIME_BUDGET_MS", 10000)
LARGE_SCENARIO_TIME_BUDGET_MS = positive("LARGE_SCENARIO_TIME_BUDGET_MS", 2000)
SMALL_SCENARIO_REQUEST_LIMIT = 300
DECOMPOSE_THRESHOLD = positive("DECOMPOSE_THRESHOLD", 250)
LOG_LEVEL = os.getenv("LOG_LEVEL", "info").lower()
if LOG_LEVEL not in {"critical", "error", "warning", "info", "debug", "trace"}:
    raise ValueError("LOG_LEVEL không hợp lệ")
