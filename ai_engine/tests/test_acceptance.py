"""Nghiệm thu trang 20 và các giả định cho tình huống trang 16."""

from __future__ import annotations

from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from pathlib import Path
from time import perf_counter
from typing import Any
import json

import pytest
from pydantic import ValidationError

from ai_engine.baselines import compute_kpi
from ai_engine.explainer import build_all_results, build_explanation
from ai_engine.normalizer import STEP, NormProblem, Solution, normalize
from ai_engine.optimizer_milp import solve
from ai_engine.schemas import OptimizeRequest
from ai_engine.validator import validate_solution

SAMPLE = Path(__file__).resolve().parents[1] / "samples/page20_input.json"


def snapshot() -> dict[str, Any]:
    """Đọc một bản snapshot trang 20 độc lập."""
    return json.loads(SAMPLE.read_bytes())


def run(data: dict[str, Any]) -> tuple[NormProblem, Solution]:
    """Đi qua đúng schema, normalizer, optimizer và validator của service."""
    p = normalize(OptimizeRequest.model_validate(data))
    s = solve(p)
    report = validate_solution(p,s)
    assert report.ok, report.violations
    return p,s


def test_page20(capsys: pytest.CaptureFixture[str]) -> None:
    """Giả định snapshot đúng 17:00 là lần lập lịch đầu trước khi bật cổng."""
    p,s=run(snapshot())
    loads=defaultdict(float)
    rows=defaultdict(list)
    for (rid,pid,t),kw in sorted(s.power.items()):
        r,port=p.requests[rid],p.ports[pid]
        start=p.t0_time+t*STEP
        assert r.arrival_time<=start and start+STEP<=r.departure_time
        if port.control_type=="ON_OFF_SWITCH":
            assert kw in (0,1.0)
        loads[port.station_id,t]+=kw
        rows[t].append(f"{rid}/{pid}/{kw:g}")
    with capsys.disabled():
        print(f"\nTrang 20 | {s.algorithm.value} | {s.status.value}")
        print("Slot  | xe/cổng/kW                  | S1 | S2 | cụm kW")
        for t in range(p.T):
            a,b=loads["10",t],loads["11",t]
            print(f"{p.t0_time+t*STEP:%H:%M} | {', '.join(rows[t]):28} | {a:g} | {b:g} | {a+b:g}")
            assert a<=4+1e-6 and b<=2+1e-6 and a+b<=3+1e-6
        print(f"Chi phí: {compute_kpi(p,s).total_cost_vnd:g} VND")
    assert sum(s.power.values())*p.dt==pytest.approx(2.5)
    assert set(s.shortfall)==set("ABCD") and all(abs(v)<=1e-6 for v in s.shortfall.values())
    assert compute_kpi(p,s).total_cost_vnd==pytest.approx(5500,abs=1)
    assert s.status in {"OPTIMAL","FEASIBLE"}
    assert s.algorithm != "LLF"
    assert s.status != "FALLBACK"


def test_new_joins_old() -> None:
    """Giả định hai xe CONFIRMED có lịch đầu, hai xe PENDING đến khi lập lại lịch."""
    d=snapshot()
    old=deepcopy(d)
    old["requests"]=[r for r in old["requests"] if r["status"]=="CONFIRMED"]
    p,s=run(old)
    d["previous_schedule"]=[dict(request_id=r,port_id=j,slot_start=(p.t0_time+t*STEP).isoformat(),power_kw=v)
                            for (r,j,t),v in s.power.items()]
    _,new=run(d)
    assert new.shortfall["A"]<=1e-6 and new.shortfall["C"]<=1e-6


def test_old_charging() -> None:
    """Giả định A đang sạc tại 101, đồng hồ đã ghi 0,5 kWh và slot hiện tại đã chạy."""
    d=snapshot()
    d["requests"][0].update(status="CHARGING",locked_port_id=101,energy_delivered_kwh=.5)
    p,s=run(d)
    rows=[(j,t,v) for (r,j,t),v in s.power.items() if r=="A"]
    assert rows and all(j=="101" and t>=1 for j,t,_ in rows)
    assert sum(v for _,_,v in rows)*p.dt==pytest.approx(.5)


def test_terminal_excluded() -> None:
    """Giả định cả bốn trạng thái cuối đều không còn nghĩa vụ cấp điện."""
    d=snapshot()
    for r,status in zip(d["requests"],["DONE","CANCELLED","NO_SHOW","FAILED"]):
        r["status"]=status
    p,s=run(d)
    results=build_all_results(p,s)
    assert not p.requests and not s.power and not s.assign
    assert {r.request_id for r in results}==set("ABCD")
    assert all(r.allocated_kwh==r.shortfall_kwh==0 for r in results)


def test_cross_cluster() -> None:
    """Giả định snapshot là nguyên tử; một mã trạm ngoài cụm làm toàn bộ input bị từ chối."""
    d=snapshot()
    d["requests"][0]["station_id"]=999
    with pytest.raises(ValidationError,match="station_id"):
        OptimizeRequest.model_validate(d)
    from fastapi.testclient import TestClient
    from ai_engine.main import app
    assert TestClient(app).post("/ai/optimize",json=d).status_code==422


def test_tie_break() -> None:
    """Giả định A và B cùng cửa sổ, trọng số và nhu cầu, khác duy nhất mã; một cổng rảnh."""
    d=snapshot()
    a=d["requests"][0]
    d["requests"]=[a,dict(a,request_id="B")]
    d["stations"][0]["ports"]=d["stations"][0]["ports"][:1]
    answers=[]
    for _ in range(5):
        d["requests"].reverse()
        _,s=run(d)
        answers.append((s.assign,s.power,s.shortfall))
    assert answers[0][1] and all(v==answers[0] for v in answers)


def test_capacity_conflict() -> None:
    """Giả định chỉ trần cụm 1 kW gây thiếu điện, xe vẫn còn cổng tương thích."""
    d=snapshot()
    d["grid_limit_kw"]=1
    d["requests"]=d["requests"][:2]
    p,s=run(d)
    k=compute_kpi(p,s)
    assert k.total_shortfall_kwh>0 and k.cap_violations==0
    assert any("cụm chạm trần" in build_explanation(p,s,r) for r,v in s.shortfall.items() if v>1e-6)


def test_concurrent_booking() -> None:
    """Giả định Backend gọi đồng thời hai lần cùng version; so lịch, bỏ thời gian xử lý."""
    d=snapshot()
    with ThreadPoolExecutor(max_workers=2) as pool:
        first,second=pool.map(run,[deepcopy(d),deepcopy(d)])
    assert first[1].power==second[1].power and first[1].assign==second[1].assign
    assert first[1].power


def test_solver_timeout() -> None:
    """Giả định deadline solver 1 ms; cho phép 50 ms chi phí gọi và trả kết quả Python."""
    d=snapshot()
    d["time_budget_ms"]=1
    p=normalize(OptimizeRequest.model_validate(d))
    start=perf_counter()
    s=solve(p)
    assert perf_counter()-start<=.051
    assert s.status=="FALLBACK" and s.algorithm=="LLF"
    assert validate_solution(p,s).ok


def test_schedule_change() -> None:
    """Giả định chỉ hủy xe chưa nhận điện ở slot khóa, dòng đang chạy giữ nguyên."""
    d=snapshot()
    p,s=run(d)
    frozen={k:v for k,v in s.power.items() if k[2]==0}
    assert frozen
    candidate=next(r for r in d["requests"] if r["request_id"] not in {k[0] for k in frozen})
    candidate["status"]="CANCELLED"
    d["snapshot_time"]="2026-11-18T17:01:00+07:00"
    d["input_version"]="page20-v2"
    d["previous_schedule"]=[dict(request_id=r,port_id=j,slot_start=(p.t0_time+t*STEP).isoformat(),power_kw=v)
                            for (r,j,t),v in s.power.items()]
    _,new=run(d)
    assert {k:v for k,v in new.power.items() if k[2]==0}==pytest.approx(frozen)
    assert all(k[0]!=candidate["request_id"] for k in new.power)


def test_port_maintenance() -> None:
    """Xe đang sạc không tự đổi cổng khi cổng đang cắm báo bảo trì."""
    d=snapshot()
    d["requests"]=d["requests"][:1]
    d["requests"][0].update(status="CHARGING",locked_port_id=101,energy_delivered_kwh=.25)
    _,before=run(d)
    assert before.assign["A"]=="101"
    d["stations"][0]["ports"][0]["status"]="MAINTENANCE"
    p,after=run(d)
    assert not after.power and after.shortfall["A"]==pytest.approx(.75)
    assert "không hoạt động" in build_explanation(p,after,"A")
    d["stations"][0]["ports"][1]["status"]="MAINTENANCE"
    p,none=run(d)
    assert none.shortfall["A"]==pytest.approx(.75) and not none.power
    assert "không hoạt động" in build_explanation(p,none,"A")
