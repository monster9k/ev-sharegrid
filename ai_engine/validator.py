"""Kiểm tra độc lập nghiệm đã lập trước khi trả cho Backend."""

from collections import defaultdict
from dataclasses import dataclass, replace
from math import isfinite
from time import perf_counter
from typing import Callable

from .baselines import solve_llf
from .normalizer import NormProblem, Solution
from .schemas import Algorithm, SolverStatus

from .settings import EPS_KW, is_leq, is_zero


@dataclass(frozen=True, slots=True)
class Violation:
    """Một lỗi kèm vị trí; trường vị trí có thể trống với lỗi tổng hợp."""
    code: str
    request_id: str | None
    port_id: str | None
    slot: int | None
    description: str


@dataclass(slots=True)
class ValidationReport:
    """Kết quả kiểm tra của nghiệm được trả về."""
    ok: bool
    violations: list[Violation]


def validate_solution(problem: NormProblem, solution: Solution) -> ValidationReport:
    """Tái tính điện năng và tải từ lịch thưa, đối chiếu với snapshot."""
    errors: list[Violation] = []
    grid: dict[int, float] = defaultdict(float)
    stations: dict[tuple[str, int], float] = defaultdict(float)
    energy: dict[str, float] = defaultdict(float)
    port_owner: dict[tuple[str, int], str] = {}
    car_port: dict[tuple[str, int], str] = {}
    first_port: dict[str, str] = {}

    def add(code: str, message: str, rid: str | None = None,
            pid: str | None = None, t: int | None = None) -> None:
        """Ghi lỗi với ngữ cảnh đủ để truy lại dòng lịch."""
        errors.append(Violation(code, rid, pid, t, message))

    def check_pair(rid: str, pid: str, t: int | None) -> None:
        """Kiểm tra tính hợp lệ của một cặp xe và cổng."""
        r, port = problem.requests.get(rid), problem.ports.get(pid)
        if r is None:
            add("UNKNOWN_REQUEST", "Yêu cầu không thuộc danh sách cần giải.", rid, pid, t)
        if port is None:
            add("UNKNOWN_PORT", "Cổng không tồn tại.", rid, pid, t)
        if r and port:
            if r.station_id != port.station_id:
                add("WRONG_STATION", "Xe và cổng khác trạm.", rid, pid, t)
            if r.connector_type != port.connector_type:
                add("CONNECTOR", "Chuẩn đầu nối không tương thích.", rid, pid, t)
            if port.status != "ACTIVE":
                add("PORT_INACTIVE", "Cổng không hoạt động.", rid, pid, t)
            if r.locked_port_id and r.locked_port_id != pid and not (r.port_lost and pid in r.replacement_ports and problem.ports[r.locked_port_id].status != "ACTIVE"):
                add("LOCK_CHANGED", "Đã đổi cổng đang khóa cho phiên.", rid, pid, t)

    for rid, pid in solution.assign.items():
        check_pair(rid, pid, None)
    for (rid, pid, t), kw in solution.power.items():
        if not isfinite(kw):
            add("NONFINITE_POWER", "Công suất không hữu hạn.", rid, pid, t)
            continue
        if not is_leq(0, kw, EPS_KW):
            add("NEGATIVE_POWER", "Công suất âm.", rid, pid, t)
            continue
        if is_zero(kw, EPS_KW):
            continue
        check_pair(rid, pid, t)
        if solution.assign.get(rid) != pid:
            add("ASSIGN_MISMATCH", "Cổng cấp điện khác bảng gán cổng.", rid, pid, t)
        if first_port.setdefault(rid, pid) != pid:
            add("PORT_CHANGED", "Một phiên sử dụng nhiều cổng.", rid, pid, t)
        if car_port.setdefault((rid, t), pid) != pid:
            add("MULTIPLE_PORTS", "Xe nhận điện từ hai cổng trong cùng slot.", rid, pid, t)
        if port_owner.setdefault((pid, t), rid) != rid:
            add("PORT_COLLISION", "Hai xe cùng nhận điện tại một cổng.", rid, pid, t)
        if type(t) is not int or not 0 <= t < problem.T:
            add("HORIZON", "Slot nằm ngoài horizon hoặc sai kiểu.", rid, pid, t)
            continue
        if t < problem.first_mutable_slot and not is_zero(kw - problem.previous_schedule.get((rid, pid, t), 0), EPS_KW):
            add("FROZEN_SLOT", "Slot đã bắt đầu và phải được giữ nguyên.", rid, pid, t)
        grid[t] += kw
        energy[rid] += kw * problem.dt
        r, port = problem.requests.get(rid), problem.ports.get(pid)
        if r:
            if not r.arrival_slot <= t < r.departure_slot:
                add("PARKING_WINDOW", "Slot nằm ngoài thời gian đỗ xe.", rid, pid, t)
            if not is_leq(kw, r.vehicle_max_kw, EPS_KW):
                add("VEHICLE_MAX", "Vượt công suất tối đa của xe.", rid, pid, t)
        if port:
            sid = port.station_id
            stations[sid, t] += kw
            if t not in problem.stations[sid].open_slots:
                add("STATION_CLOSED", "Trạm không mở cửa trọn slot.", rid, pid, t)
            if port.control_type == "ON_OFF_SWITCH":
                if not is_zero(kw - port.max_power_kw, EPS_KW):
                    add("ON_OFF_POWER", "Cổng đóng/ngắt phải bật đúng công suất định mức.", rid, pid, t)
            elif not (is_leq(port.min_power_kw, kw, EPS_KW) and is_leq(kw, port.max_power_kw, EPS_KW)):
                add("CONTINUOUS_POWER", "Công suất ngoài dải điều chỉnh của cổng.", rid, pid, t)
    for (rid, pid, t), kw in problem.previous_schedule.items():
        if t < problem.first_mutable_slot and not is_zero(solution.power.get((rid, pid, t), 0) - kw, EPS_KW):
            add("FROZEN_SLOT", "Nghiệm bỏ hoặc sửa công suất đã khóa.", rid, pid, t)
    for t, total in grid.items():
        if not is_leq(total, problem.grid_limit_kw, EPS_KW):
            add("GRID_CAP", f"Cụm dùng {total:g} kW, vượt trần {problem.grid_limit_kw:g} kW.", t=t)
    for (sid, t), total in stations.items():
        if not is_leq(total, problem.stations[sid].station_power_kw, EPS_KW):
            add("STATION_CAP", f"Trạm {sid} dùng {total:g} kW, vượt trần trạm.", t=t)
    for rid, r in problem.requests.items():
        if not is_leq(energy[rid], r.remaining_kwh):
            add("OVERALLOCATED", "Điện năng cấp vượt nhu cầu còn lại.", rid)
        missing = solution.shortfall.get(rid)
        if missing is None or not isfinite(missing) or not is_leq(0, missing) or not is_zero(energy[rid] + missing - r.remaining_kwh):
            add("ENERGY_BALANCE", "Điện đã cấp và phần thiếu khai báo không khớp nhu cầu.", rid)
    for rid, missing in solution.shortfall.items():
        if rid not in problem.requests and (rid not in problem.skipped_results or not is_zero(missing)):
            add("UNEXPECTED_SHORTFALL", "Phần thiếu không thuộc yêu cầu cần giải.", rid)
    return ValidationReport(not errors, errors)


def safe_solve(problem: NormProblem, solver_fn: Callable[[NormProblem], Solution]
               ) -> tuple[Solution, SolverStatus, ValidationReport]:
    """Kiểm tra độc lập hai lần thử; nếu cả hai hỏng thì trả lịch rỗng và lỗi."""
    start = perf_counter()
    failures: list[Violation] = []
    for fallback, solver in ((False, solver_fn), (True, solve_llf)):
        try:
            attempt = problem
            if fallback:
                left = max(0, int(problem.time_budget_ms - (perf_counter() - start) * 1000))
                attempt = replace(problem, time_budget_ms=left)
            sol = solver(attempt)
            report = validate_solution(problem, sol)
            if sol.status in (SolverStatus.ERROR, SolverStatus.INFEASIBLE):
                report = ValidationReport(False, report.violations + [
                    Violation("SOLVER_STATUS", None, None, None, f"Solver trả trạng thái {sol.status.value}.")])
            if report.ok:
                if fallback:
                    sol = replace(sol, status=SolverStatus.FALLBACK)
                return sol, sol.status, report
            failures.extend(report.violations)
        except Exception as exc:
            failures.append(Violation("SOLVER_EXCEPTION", None, None, None,
                                      f"Lỗi khi chạy hoặc kiểm tra solver: {type(exc).__name__}: {exc}"))
    empty = Solution({}, {}, SolverStatus.ERROR, Algorithm.LLF,
                     {rid: r.remaining_kwh for rid, r in problem.requests.items()})
    return empty, empty.status, ValidationReport(False, failures)
