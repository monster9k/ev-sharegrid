"""Hợp đồng JSON và kiểm tra dữ liệu đầu vào, đầu ra của EV ShareGrid."""

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Annotated, Any, Literal

from .settings import (
    DEFAULT_TIME_BUDGET_MS,
    LARGE_SCENARIO_TIME_BUDGET_MS,
    SMALL_SCENARIO_REQUEST_LIMIT,
    EPS_KW,
    is_leq,
    is_zero,
)

from pydantic import (
    AfterValidator, AliasChoices,
    AwareDatetime,
    BaseModel,
    BeforeValidator,
    ConfigDict,
    Field,
    model_validator,
)


class ConnectorType(str, Enum):
    """Chuẩn đầu nối giữa xe và cổng sạc."""

    CCS2 = "CCS2"
    TYPE2 = "Type2"
    CHADEMO = "CHAdeMO"
    AC_HOME = "AC_HOME"


def _canonical_connector(value: Any) -> Any:
    """Map catalog connector spellings to the AI Engine's canonical names."""
    return {
        "CCS2_DC": ConnectorType.CCS2.value,
        "AC_HOME_VINFAST_ADAPTER": ConnectorType.AC_HOME.value,
    }.get(value, value) if isinstance(value, str) else value


ConnectorInput = Annotated[ConnectorType, BeforeValidator(_canonical_connector)]


class ControlType(str, Enum):
    """Khả năng điều khiển công suất của cổng."""

    CONTINUOUS = "CONTINUOUS"
    ON_OFF_SWITCH = "ON_OFF_SWITCH"


class PortStatus(str, Enum):
    """Trạng thái vận hành cổng sạc."""

    ACTIVE = "ACTIVE"
    MAINTENANCE = "MAINTENANCE"
    OFFLINE = "OFFLINE"


class RequestStatus(str, Enum):
    """Trạng thái vòng đời yêu cầu sạc."""

    PENDING = "PENDING"
    SCHEDULED = "SCHEDULED"
    CONFIRMED = "CONFIRMED"
    CHARGING = "CHARGING"
    DONE = "DONE"
    CANCELLED = "CANCELLED"
    NO_SHOW = "NO_SHOW"
    FAILED = "FAILED"


class SolverStatus(str, Enum):
    """Trạng thái kết quả giải bài toán điều phối."""

    OPTIMAL = "OPTIMAL"
    FEASIBLE = "FEASIBLE"
    FALLBACK = "FALLBACK"
    INFEASIBLE = "INFEASIBLE"
    ERROR = "ERROR"


class Algorithm(str, Enum):
    """Tên thuật toán lập lịch được hỗ trợ trong hợp đồng API."""

    MILP = "MILP"
    MILP_MPC = "MILP_MPC"
    NSGA_II = "NSGA_II"
    CP_SAT = "CP_SAT"
    LP_MPC = "LP_MPC"
    MASTER_LP = "MASTER_LP"
    LLF = "LLF"
    FCFS = "FCFS"
    EDF = "EDF"
    EQUAL_SHARE = "EQUAL_SHARE"
    ASAP = "ASAP"


class ForecastModel(str, Enum):
    """Tên mô hình dự báo số lượt xe theo giờ."""

    HOURLY_MEAN = "HOURLY_MEAN"
    RANDOM_FOREST = "RANDOM_FOREST"
    XGBOOST = "XGBOOST"
    BEST = "BEST"


def _check_datetime_input(value: Any) -> Any:
    """Chỉ nhận datetime hoặc chuỗi ISO-8601 đầy đủ có đuôi +07:00."""
    if isinstance(value, datetime):
        return value
    if not isinstance(value, str) or not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?\+07:00", value
    ):
        raise ValueError("Thời gian phải là ISO-8601 có timezone +07:00")
    return value


def _check_timezone(value: datetime) -> datetime:
    """Yêu cầu múi giờ Việt Nam cho mọi thời điểm."""
    if value.utcoffset() != timedelta(hours=7):
        raise ValueError("Thời gian phải có timezone +07:00")
    return value


def _check_slot(value: datetime) -> datetime:
    """Kiểm tra đầu slot thuộc các mốc 00, 15, 30, 45 phút."""
    if value.minute % 15 or value.second or value.microsecond:
        raise ValueError("slot_start phải căn chẵn 15 phút")
    return value


def _check_hour(value: datetime) -> datetime:
    """Kiểm tra thời điểm bắt đầu giờ."""
    if value.minute or value.second or value.microsecond:
        raise ValueError("hour_start phải căn chẵn giờ")
    return value


LocalDatetime = Annotated[
    AwareDatetime, BeforeValidator(_check_datetime_input), AfterValidator(_check_timezone)
]
SlotDatetime = Annotated[LocalDatetime, AfterValidator(_check_slot)]
HourDatetime = Annotated[LocalDatetime, AfterValidator(_check_hour)]
def _string_id(value: Any) -> Any:
    """Chuẩn hóa ID số nguyên của Backend thành khóa chuỗi nội bộ."""
    return str(value) if type(value) is int else value


Identifier = Annotated[str, Field(strict=True, min_length=1, pattern=r"\S"),
                       BeforeValidator(_string_id, json_schema_input_type=str | int)]
NonNegativeFloat = Annotated[float, Field(ge=0, allow_inf_nan=False)]
PositiveFloat = Annotated[float, Field(gt=0, allow_inf_nan=False)]
PositiveInt = Annotated[int, Field(strict=True, gt=0)]
NonNegativeInt = Annotated[int, Field(strict=True, ge=0)]


class APIModel(BaseModel):
    """Cấu hình chung: từ chối trường lạ và số không hữu hạn."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False, validate_default=True)


class Port(APIModel):
    """Thông số và trạng thái một cổng sạc."""

    port_id: Identifier = Field(description="Mã cổng duy nhất trong toàn cụm.")
    connector_type: ConnectorInput = Field(description="Chuẩn đầu nối của cổng.")
    control_type: ControlType = Field(description="Kiểu điều khiển công suất.")
    min_power_kw: NonNegativeFloat = Field(description="Công suất nhỏ nhất khi bật, kW.")
    max_power_kw: PositiveFloat = Field(description="Công suất định mức lớn nhất, kW.")
    status: PortStatus = Field(description="Trạng thái hoạt động của cổng.")

    @model_validator(mode="after")
    def validate_power(self) -> Port:
        """Kiểm tra miền công suất và quy tắc cổng đóng/ngắt."""
        if not is_leq(self.min_power_kw, self.max_power_kw, EPS_KW):
            raise ValueError("min_power_kw phải <= max_power_kw")
        if self.control_type == ControlType.ON_OFF_SWITCH and not is_zero(self.min_power_kw - self.max_power_kw, EPS_KW):
            raise ValueError("ON_OFF_SWITCH yêu cầu min_power_kw == max_power_kw")
        self.min_power_kw = (self.max_power_kw if self.control_type == ControlType.ON_OFF_SWITCH
                             else min(self.min_power_kw, self.max_power_kw))
        return self


class Station(APIModel):
    """Trạm sạc với một khoảng mở cửa tuyệt đối trong snapshot."""

    station_id: Identifier = Field(description="Mã trạm duy nhất trong cụm.")
    station_power_kw: NonNegativeFloat = Field(description="Giới hạn tổng công suất trạm, kW.")
    open_time: LocalDatetime = Field(description="Thời điểm mở cửa ISO-8601 +07:00.")
    close_time: LocalDatetime = Field(description="Thời điểm đóng cửa, không bao gồm mốc này; +07:00.")
    ports: list[Port] = Field(description="Danh sách cổng thuộc trạm.")

    @model_validator(mode="after")
    def validate_station(self) -> Station:
        """Kiểm tra giờ mở cửa và mã cổng nội bộ."""
        if self.close_time <= self.open_time:
            raise ValueError("close_time phải > open_time")
        if len({port.port_id for port in self.ports}) != len(self.ports):
            raise ValueError("port_id không được trùng")
        return self


DailyClock = Annotated[str, Field(pattern=r"^(?:(?:[01][0-9]|2[0-3]):[0-5][0-9]|24:00)$")]


class Tariff(APIModel):
    """Giá điện trong khoảng thời gian nửa kín [bắt đầu, kết thúc)."""

    start_time: LocalDatetime | DailyClock = Field(description="Bắt đầu theo ISO-8601 +07:00 hoặc giờ hằng ngày HH:MM tại Việt Nam.")
    end_time: LocalDatetime | DailyClock = Field(description="Kết thúc cùng kiểu với start_time. Giờ hằng ngày được qua đêm, 24:00 là cuối ngày.")
    price_vnd_kwh: NonNegativeFloat = Field(description="Đơn giá điện, VND/kWh.")

    @model_validator(mode="after")
    def validate_interval(self) -> Tariff:
        """Kiểm tra khoảng áp dụng giá có độ dài dương."""
        if isinstance(self.start_time, str) != isinstance(self.end_time, str):
            raise ValueError("start_time và end_time phải cùng kiểu")
        if isinstance(self.start_time, str):
            if self.start_time == self.end_time or (self.start_time, self.end_time) == ("24:00", "00:00"):
                raise ValueError("Khoảng giá hằng ngày phải có độ dài dương")
            return self
        if self.end_time <= self.start_time:
            raise ValueError("end_time phải > start_time")
        return self


class ChargingRequestIn(APIModel):
    """Nhu cầu sạc của một xe, không chứa đặc quyền theo tuổi tài khoản."""

    request_id: Identifier = Field(description="Mã yêu cầu sạc duy nhất trong snapshot.")
    station_id: Identifier = Field(description="Mã trạm xe đăng ký sạc.")
    connector_type: ConnectorInput = Field(description="Chuẩn đầu nối xe yêu cầu.")
    battery_capacity_kwh: PositiveFloat | None = Field(default=None, description="Dung lượng pin sử dụng được, kWh.")
    current_soc_pct: float | None = Field(default=None, ge=0, le=100, description="SOC tại thời điểm snapshot, phần trăm.")
    previous_port_id: Identifier | None = Field(default=None, description="Cổng trước khi Backend chuyển phiên sang cổng hiện tại.")
    vehicle_max_kw: PositiveFloat = Field(description="Công suất sạc tối đa xe nhận được, kW.")
    arrival_time: LocalDatetime = Field(description="Thời điểm xe đến, ISO-8601 +07:00.")
    departure_time: LocalDatetime = Field(description="Thời điểm xe rời đi, ISO-8601 +07:00; phải sau khi đến.")
    energy_needed_kwh: NonNegativeFloat = Field(description="Tổng điện năng xe yêu cầu cho phiên, kWh.")
    energy_delivered_kwh: NonNegativeFloat = Field(description="Điện năng đã cấp trước snapshot, kWh.")
    priority_weight: PositiveFloat = Field(description="Trọng số ưu tiên dương; không dựa vào tuổi tài khoản.")
    status: RequestStatus = Field(description="Trạng thái hiện tại của yêu cầu sạc.")
    locked_port_id: Identifier | None = Field(default=None, description="Cổng đã khóa cho phiên; CHARGING có khóa phải giữ nguyên cổng.")

    @model_validator(mode="after")
    def validate_interval(self) -> ChargingRequestIn:
        """Kiểm tra xe rời đi sau thời điểm đến."""
        if self.departure_time <= self.arrival_time:
            raise ValueError("departure_time phải > arrival_time")
        return self


class KPI(APIModel):
    """Chỉ số đánh giá chung của một nghiệm lập lịch."""

    total_shortfall_kwh: NonNegativeFloat = Field(description="Tổng điện năng còn thiếu sau lịch, kWh.")
    total_cost_vnd: NonNegativeFloat = Field(description="Tổng chi phí điện của lịch mới, VND.")
    peak_power_kw: NonNegativeFloat = Field(description="Công suất tổng cụm lớn nhất trong lịch, kW.")
    on_time_rate: float = Field(ge=0, le=1, description="Tỷ lệ yêu cầu được sạc đủ trước hạn, từ 0 đến 1.")
    fairness: float | None = Field(default=None, ge=0, le=1, description="Chỉ số Jain trên tỷ lệ điện đã phân bổ cho các yêu cầu cần giải. Null với kết quả cũ chưa đo.")
    cap_violations: NonNegativeInt = Field(description="Số vi phạm giới hạn công suất; nghiệm hợp lệ phải bằng 0.")


class RequestResult(APIModel):
    """Kết quả phân bổ và giải thích cho một yêu cầu sạc."""

    request_id: Identifier = Field(description="Mã yêu cầu sạc.")
    allocated_kwh: NonNegativeFloat = Field(description="Điện năng cấp thêm trong lịch mới, kWh.")
    shortfall_kwh: NonNegativeFloat = Field(description="Điện năng còn thiếu so với nhu cầu còn lại, kWh.")
    expected_soc: float | None = Field(ge=0, le=100, description="SOC dự kiến theo phần trăm; khi thiếu dữ liệu pin, dùng tỷ lệ đáp ứng tổng nhu cầu phiên.")
    estimated_cost_vnd: NonNegativeFloat = Field(description="Chi phí ước tính của phần điện năng cấp thêm, VND.")
    explanation: str = Field(min_length=1, description="Giải thích kết quả phân bổ bằng tiếng Việt.")


class ScheduleItem(APIModel):
    """Công suất một xe tại một cổng trong một slot 15 phút."""

    request_id: Identifier = Field(description="Mã yêu cầu được cấp điện.")
    port_id: Identifier = Field(description="Mã cổng được giữ cố định trong phiên.")
    slot_start: SlotDatetime = Field(description="Đầu slot ISO-8601 +07:00, căn :00, :15, :30 hoặc :45.")
    power_kw: NonNegativeFloat = Field(description="Công suất cấp trong toàn slot, kW; cho phép 0.")


class OptimizeRequest(APIModel):
    """Snapshot đầu vào của POST /ai/optimize."""

    cluster_id: Identifier = Field(description="Mã cụm trạm cần điều phối.")
    input_version: Identifier | Annotated[int, Field(strict=True, ge=0)] = Field(description="Phiên bản snapshot do Backend cấp, chuỗi hoặc số nguyên không âm.")
    snapshot_time: LocalDatetime = Field(description="Thời điểm chụp trạng thái ISO-8601 +07:00; có thể nằm giữa slot.")
    slot_minutes: Literal[15] = Field(description="Độ dài slot cố định 15 phút, tương đương 0,25 giờ.")
    horizon_slots: PositiveInt = Field(description="Số slot trong khoảng lập lịch.")
    previous_schedule: list[ScheduleItem] = Field(default_factory=list, description="Lịch MPC cũ. Công suất ở slot đóng băng phải được tính đủ trong nhu cầu còn lại của snapshot.")
    grid_limit_kw: NonNegativeFloat = Field(description="Giới hạn công suất cụm áp dụng cho mọi slot, kW.")
    time_budget_ms: PositiveInt = Field(default=DEFAULT_TIME_BUDGET_MS, description="Ngân sách thời gian giải tối đa, mili giây.")
    stations: list[Station] = Field(description="Danh sách trạm và cổng thuộc cụm.")
    tariffs: list[Tariff] = Field(description="Các khoảng giá điện không chồng lấn; phủ thời gian cần tính phí.")
    requests: list[ChargingRequestIn] = Field(description="Các yêu cầu sạc trong snapshot, mã không trùng.")

    @model_validator(mode="before")
    @classmethod
    def apply_scale_time_budget(cls, value: Any) -> Any:
        """Dùng mặc định 10 giây cho snapshot nhỏ và chặn ngân sách mặc định ở tải lớn."""
        if not isinstance(value, dict):
            return value
        payload = dict(value)
        requests = payload.get("requests")
        count = len(requests) if isinstance(requests, list) else 0
        if count >= SMALL_SCENARIO_REQUEST_LIMIT:
            if "time_budget_ms" not in payload:
                payload["time_budget_ms"] = LARGE_SCENARIO_TIME_BUDGET_MS
            else:
                budget = payload["time_budget_ms"]
                if isinstance(budget, int) and not isinstance(budget, bool):
                    payload["time_budget_ms"] = min(budget, LARGE_SCENARIO_TIME_BUDGET_MS)
        return payload

    @model_validator(mode="after")
    def validate_references(self) -> OptimizeRequest:
        """Kiểm tra mã định danh và liên kết trạm, cổng trong thời gian tuyến tính."""
        stations = {station.station_id: station for station in self.stations}
        if len(stations) != len(self.stations):
            raise ValueError("station_id không được trùng")
        ports: dict[str, tuple[str, Port]] = {}
        for station in self.stations:
            for port in station.ports:
                if port.port_id in ports:
                    raise ValueError("port_id không được trùng trong toàn cụm")
                ports[port.port_id] = (station.station_id, port)
        seen: set[str] = set()
        for request in self.requests:
            if request.request_id in seen:
                raise ValueError("request_id không được trùng")
            seen.add(request.request_id)
            if request.station_id not in stations:
                raise ValueError("station_id của request phải tồn tại")
            if request.locked_port_id is not None:
                locked = ports.get(request.locked_port_id)
                if locked is None or locked[0] != request.station_id:
                    raise ValueError("locked_port_id phải tồn tại và thuộc trạm của request")
                if locked[1].connector_type != request.connector_type:
                    raise ValueError("locked_port_id phải đúng connector_type")
        tariffs = sorted((t for t in self.tariffs if isinstance(t.start_time, datetime)), key=lambda tariff: tariff.start_time)
        if any(right.start_time < left.end_time for left, right in zip(tariffs, tariffs[1:])):
            raise ValueError("Các khoảng tariffs không được chồng lấn")
        return self


class OptimizeResponse(APIModel):
    """Kết quả POST /ai/optimize; ràng buộc vật lý do validator kiểm tra riêng."""

    status: SolverStatus = Field(description="Trạng thái giải hoặc fallback.")
    algorithm: Algorithm | None = Field(description="Thuật toán thực tế tạo ra nghiệm; null nếu chưa có nghiệm.")
    solve_ms: NonNegativeFloat = Field(description="Thời gian xử lý thực tế, mili giây.")
    kpi: KPI = Field(description="Các chỉ số đánh giá nghiệm.")
    request_results: list[RequestResult] = Field(description="Kết quả chi tiết cho từng yêu cầu.")
    schedules: list[ScheduleItem] = Field(description="Danh sách phân bổ công suất theo slot 15 phút.")

    @model_validator(mode="after")
    def validate_result_ids(self) -> OptimizeResponse:
        """Từ chối kết quả trùng mã và lịch tham chiếu yêu cầu không có kết quả."""
        ids = {result.request_id for result in self.request_results}
        if len(ids) != len(self.request_results):
            raise ValueError("request_id trong request_results không được trùng")
        if any(item.request_id not in ids for item in self.schedules):
            raise ValueError("request_id trong schedules phải có request_results")
        return self


class BenchmarkRequest(APIModel):
    """Cấu hình so sánh thuật toán trên một kịch bản hoặc snapshot."""

    scenario_id: Identifier = Field(default="inline", description="Mã kịch bản benchmark do service quản lý.")
    algorithms: list[Algorithm] = Field(min_length=1, description="Các thuật toán cần so sánh, không trùng tên.")
    seed: NonNegativeInt = Field(default=42, le=4294967295, description="Hạt giống ngẫu nhiên uint32 để tái lập kết quả.")
    repeats: PositiveInt = Field(default=1, description="Số lần chạy cho mỗi thuật toán.")
    snapshot: OptimizeRequest | None = Field(default=None, description="Snapshot tùy chọn; khi có sẽ dùng thay dữ liệu kịch bản.")

    @model_validator(mode="after")
    def validate_algorithms(self) -> BenchmarkRequest:
        """Không chạy trùng thuật toán ngoài số lần lặp đã chỉ định."""
        if len(set(self.algorithms)) != len(self.algorithms):
            raise ValueError("algorithms không được trùng")
        return self


class BenchmarkRun(APIModel):
    """Kết quả một lần chạy benchmark, giữ rõ thuật toán yêu cầu và thực tế."""

    algorithm: Algorithm = Field(description="Thuật toán được yêu cầu chạy.")
    repeat_index: NonNegativeInt = Field(description="Chỉ số lần chạy bắt đầu từ 0.")
    result: OptimizeResponse = Field(description="Kết quả chuẩn, chứa thuật toán thực tế và KPI của lần chạy.")


class BenchmarkSummary(APIModel):
    """Thống kê theo thuật toán trên các lượt chạy."""
    algorithm: Algorithm = Field(description="Thuật toán yêu cầu.")
    status: str = Field(description="Trạng thái tổng hợp hoặc NOT_IMPLEMENTED.")
    actual_algorithms: list[Algorithm] = Field(description="Các thuật toán thực tế đã chạy.")
    kpi: KPI | None = Field(default=None, description="KPI trung bình, số vi phạm là giá trị lớn nhất qua các lượt.")
    solve_ms_mean: NonNegativeFloat | None = Field(default=None, description="Thời gian trung bình, ms.")
    solve_ms_std: NonNegativeFloat | None = Field(default=None, description="Độ lệch chuẩn tổng thể, ms.")


class BenchmarkResponse(APIModel):
    """Danh sách kết quả từng lần chạy để Backend tổng hợp so sánh."""

    scenario_id: Identifier = Field(description="Mã kịch bản đã chạy.")
    seed: NonNegativeInt = Field(le=4294967295, description="Hạt giống ngẫu nhiên uint32 đã sử dụng.")
    repeats: PositiveInt = Field(description="Số lần chạy cho mỗi thuật toán.")
    summary: list[BenchmarkSummary] = Field(default_factory=list, description="Bảng KPI theo thuật toán.")
    results: list[BenchmarkRun] = Field(description="Kết quả chi tiết theo thuật toán và lần lặp.")


class ForecastHistoryItem(APIModel):
    """Số lượt xe thực tế trong một giờ lịch sử."""

    hour_start: HourDatetime = Field(description="Đầu giờ quan sát ISO-8601 +07:00, phút và giây bằng 0.")
    arrivals: NonNegativeInt = Field(description="Số lượt xe đến trong giờ, số nguyên không âm.")


class ForecastRequest(APIModel):
    """Đầu vào dự báo lượt xe của POST /ai/forecast."""

    cluster_id: Identifier = Field(description="Mã cụm trạm cần dự báo.")
    history: list[ForecastHistoryItem] = Field(min_length=1, description="Lịch sử lượt xe theo giờ, không trùng giờ; cho phép chưa sắp xếp.")
    horizon_hours: PositiveInt = Field(default=24, description="Số giờ dự báo liên tiếp sau giờ lịch sử mới nhất.")
    model: ForecastModel = Field(default=ForecastModel.HOURLY_MEAN, description="Mô hình dự báo được yêu cầu sử dụng.")

    @model_validator(mode="after")
    def validate_history(self) -> ForecastRequest:
        """Từ chối các quan sát trùng giờ."""
        if len({item.hour_start for item in self.history}) != len(self.history):
            raise ValueError("hour_start trong history không được trùng")
        return self


class ForecastPrediction(APIModel):
    """Số lượt xe kỳ vọng trong một giờ tương lai."""

    hour_start: HourDatetime = Field(description="Đầu giờ dự báo ISO-8601 +07:00.")
    predicted_arrivals: NonNegativeInt | NonNegativeFloat = Field(validation_alias=AliasChoices("pred_arrivals","predicted_arrivals"), serialization_alias="pred_arrivals", description="Số lượt xe dự báo không âm; cho phép số thập phân kỳ vọng.")


class ForecastResponse(APIModel):
    """Kết quả dự báo lượt xe theo giờ."""

    cluster_id: Identifier = Field(description="Mã cụm trạm được dự báo.")
    model: ForecastModel = Field(description="Mô hình thực tế dùng để dự báo.")
    horizon_hours: PositiveInt = Field(description="Số giờ đã dự báo.")
    metrics: dict[str, NonNegativeFloat] | None = Field(default=None, description="MAE và RMSE trên tập kiểm tra theo thời gian.")
    warnings: list[str] = Field(default_factory=list, description="Lý do dùng mô hình dự phòng nếu có.")
    predictions: list[ForecastPrediction] = Field(description="Dự báo theo thứ tự thời gian, mỗi giờ một phần tử.")

    @model_validator(mode="after")
    def validate_predictions(self) -> ForecastResponse:
        """Kiểm tra số lượng và tính liên tiếp của các giờ dự báo."""
        if len(self.predictions) != self.horizon_hours:
            raise ValueError("Số predictions phải bằng horizon_hours")
        if any(
            right.hour_start - left.hour_start != timedelta(hours=1)
            for left, right in zip(self.predictions, self.predictions[1:])
        ):
            raise ValueError("predictions phải theo thứ tự và liên tiếp mỗi giờ")
        return self


API_SCHEMAS: tuple[type[APIModel], ...] = (
    OptimizeRequest, OptimizeResponse, BenchmarkRequest, BenchmarkResponse,
    ForecastRequest, ForecastResponse,
)


def export_json_schemas(destination: Path | None = None) -> Path:
    """Xuất các JSON Schema độc lập với tham chiếu $defs cục bộ cho Backend."""
    target = destination or Path(__file__).parent / "samples" / "openapi_schemas.json"
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "description": (
            "Bộ JSON Schema độc lập sinh bằng model_json_schema(), không phải tài liệu OpenAPI đầy đủ. "
            "Mỗi schema có $defs riêng. Các validator liên trường được thực thi bởi Python. "
            "Mọi thời gian phải có +07:00; slot_start căn 15 phút; hour_start căn giờ."
        ),
        "schemas": {model.__name__: model.model_json_schema() for model in API_SCHEMAS},
    }
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return target


if __name__ == "__main__":
    from .console import configure_console

    configure_console()
    export_json_schemas()
