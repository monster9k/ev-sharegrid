"""API HTTP cho lập lịch, so sánh thuật toán và dự báo lượt xe."""

import subprocess
from typing import Any, Awaitable, Callable
import importlib.util
import logging
import sys
from pathlib import Path
from statistics import fmean, pstdev
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse

from .schemas import (BenchmarkRequest, BenchmarkResponse, BenchmarkRun, BenchmarkSummary,
                      ForecastRequest, ForecastResponse, KPI, OptimizeRequest, OptimizeResponse)
from .optimizer_milp import BENCHMARK_SEED
from .settings import (
    WORKERS,
    DEFAULT_TIME_BUDGET_MS,
    LARGE_SCENARIO_TIME_BUDGET_MS,
    SMALL_SCENARIO_REQUEST_LIMIT,
    DECOMPOSE_THRESHOLD,
    LOG_LEVEL,
)
from .service import ENGINES, evaluate, failure

VERSION = "0.1.0"
app = FastAPI(title="EV ShareGrid AI Engine",version=VERSION)
LOG = logging.getLogger("uvicorn.error")
LOG.setLevel(5 if LOG_LEVEL == 'trace' else LOG_LEVEL.upper())
SCENARIOS = Path(__file__).parent/"data"/"scenarios"
# Đường dẫn hàm do service chọn; client không truyền tên module.
SOLVER_ENTRY = "ai_engine.optimizer_milp:solve"


@app.middleware("http")
async def log_request(request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
    """Gắn mã truy vết và ghi thông tin snapshot khi kết thúc."""
    rid=request.headers.get("x-request-id") or uuid4().hex
    request.state.request_id=rid
    try:
        response=await call_next(request)
        response.headers["X-Request-ID"]=rid
        return response
    finally:
        LOG.info("request_id=%r cluster_id=%r input_version=%r path=%s",rid,
                 getattr(request.state,"cluster_id",None),getattr(request.state,"input_version",None),
                 request.url.path)


@app.exception_handler(Exception)
async def unexpected(request: Request, exc: Exception) -> JSONResponse:
    """Giữ lỗi nội bộ ngoài nội dung trả cho client."""
    LOG.error("request_id=%r lỗi xử lý",getattr(request.state,"request_id",None),exc_info=exc)
    if request.url.path=="/ai/optimize":
        return JSONResponse(failure(0).model_dump(mode="json"))
    return JSONResponse({"detail":"Lỗi xử lý nội bộ","request_id":getattr(request.state,"request_id",None)},500)


@app.post("/ai/optimize",response_model=OptimizeResponse)
def optimize(body: OptimizeRequest, request: Request) -> OptimizeResponse:
    """Tách solver sang tiến trình riêng và dừng hẳn khi hết hạn."""
    request.state.cluster_id, request.state.input_version = body.cluster_id, body.input_version
    start = perf_counter()
    deadline = start + body.time_budget_ms / 1000 + 0.5
    try:
        payload = b'{"snapshot":' + body.model_dump_json().encode("utf8") + b'}'
        with subprocess.Popen(
            [sys.executable, "-m", "ai_engine.service", SOLVER_ENTRY],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        ) as process:
            try:
                raw, _ = process.communicate(payload, timeout=max(0, deadline-perf_counter()))
            except BaseException:
                process.kill()
                process.communicate()
                raise
            if process.returncode:
                raise RuntimeError(f"Worker kết thúc với mã {process.returncode}")
        result = OptimizeResponse.model_validate_json(raw)
        if perf_counter() > deadline:
            raise TimeoutError("Hết thời gian trả kết quả")
        return result
    except Exception as exc:
        LOG.warning("request_id=%s optimize thất bại: %s",request.state.request_id,type(exc).__name__)
        return failure((perf_counter()-start)*1000)


@app.post("/ai/benchmark",response_model=BenchmarkResponse)
def benchmark(body: BenchmarkRequest,request: Request) -> BenchmarkResponse:
    """Chạy tuần tự trên cùng snapshot và tổng hợp theo thuật toán yêu cầu."""
    snap=body.snapshot
    if snap is None:
        if not all(c.isalnum() or c in "_-" for c in body.scenario_id):
            raise HTTPException(404,"Không tìm thấy kịch bản")
        path=SCENARIOS/(body.scenario_id+".json")
        if not path.is_file():
            raise HTTPException(404,"Không tìm thấy kịch bản")
        snap=OptimizeRequest.model_validate_json(path.read_bytes())
    request.state.cluster_id,request.state.input_version=snap.cluster_id,snap.input_version
    runs=[]
    summaries=[]
    for alg in body.algorithms:
        if alg not in ENGINES:
            summaries.append(BenchmarkSummary(algorithm=alg,status="NOT_IMPLEMENTED",actual_algorithms=[]))
            continue
        batch=[]
        for i in range(body.repeats):
            token=BENCHMARK_SEED.set(body.seed)
            start=perf_counter()
            try:
                result=evaluate(snap,ENGINES[alg],asap=alg=="ASAP")
            except Exception:
                LOG.exception("request_id=%s lỗi benchmark %s",request.state.request_id,alg)
                result=failure((perf_counter()-start)*1000)
            finally:
                BENCHMARK_SEED.reset(token)
            batch.append(result)
            runs.append(BenchmarkRun(algorithm=alg,repeat_index=i,result=result))
        valid=[r for r in batch if r.status!="ERROR"]
        statuses={r.status.value for r in batch}
        mean_kpi=None
        if valid:
            values={k:fmean(getattr(r.kpi,k) for r in valid) for k in
                    ("total_shortfall_kwh","on_time_rate","total_cost_vnd","peak_power_kw","fairness")}
            mean_kpi=KPI(**values,cap_violations=max(r.kpi.cap_violations for r in valid))
        times=[r.solve_ms for r in batch]
        summaries.append(BenchmarkSummary(algorithm=alg,status=next(iter(statuses)) if len(statuses)==1 else "MIXED",
            actual_algorithms=sorted({r.algorithm for r in batch if r.algorithm}),kpi=mean_kpi,
            solve_ms_mean=fmean(times),solve_ms_std=pstdev(times)))
    return BenchmarkResponse(scenario_id=body.scenario_id,seed=body.seed,repeats=body.repeats,
                             results=runs,summary=summaries)


@app.post("/ai/forecast",response_model=ForecastResponse)
def forecast_api(body: ForecastRequest,request: Request) -> ForecastResponse:
    """Trả số lượt dự báo, mô hình thực tế và sai số đã đo."""
    from .forecast import forecast
    request.state.cluster_id=body.cluster_id
    return ForecastResponse.model_validate(forecast(body.cluster_id,body.history,body.horizon_hours,body.model))


@app.get("/health")
def health() -> dict[str, Any]:
    """Liệt kê thuật toán nạp được trong môi trường hiện tại."""
    names=["LLF","FCFS","EDF","EQUAL_SHARE","ASAP"]
    try:
        from ortools.linear_solver import pywraplp
        for backend,name in (("SCIP","MILP_MPC"),("GLOP","LP_MPC")):
            if pywraplp.Solver.CreateSolver(backend) is not None:
                names.append(name)
    except (ImportError,OSError):
        pass
    models=["HOURLY_MEAN"]
    for module,name in (("sklearn","RANDOM_FOREST"),("xgboost","XGBOOST")):
        if importlib.util.find_spec(module):
            models.append(name)
    return dict(version=VERSION,algorithms=names,forecast_models=models, workers=WORKERS,
                default_time_budget_ms=DEFAULT_TIME_BUDGET_MS,
                large_scenario_time_budget_ms=LARGE_SCENARIO_TIME_BUDGET_MS,
                small_scenario_request_limit=SMALL_SCENARIO_REQUEST_LIMIT,
                decompose_threshold=DECOMPOSE_THRESHOLD)
