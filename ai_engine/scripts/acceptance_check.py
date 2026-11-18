"""Chạy nghiệm thu ràng buộc, cổng đóng/ngắt, MPC và độ trễ HTTP."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from random import Random
from time import perf_counter
from typing import Any
from urllib.request import Request, urlopen

from ai_engine.baselines import SOLVERS
from ai_engine.normalizer import normalize
from ai_engine.optimizer_milp import solve
from ai_engine.schemas import OptimizeRequest, OptimizeResponse
from ai_engine.validator import validate_solution

SAMPLE = Path(__file__).resolve().parents[1]/"samples/page20_input.json"
SEED = 16520


def instance(rng: Random, i: int, hard: bool = False) -> dict[str, Any]:
    """Sinh snapshot tái lập với hai loại cổng, nhu cầu và cửa sổ đỗ khác nhau."""
    d=json.loads(SAMPLE.read_bytes())
    d["input_version"]=f"accept-{i}"
    d["time_budget_ms"]=2000 if hard else 100
    count=rng.randint(1000,2000) if hard else rng.choice((4,8,16,32,64))
    d["horizon_slots"]=rng.choice((12,16,24)) if hard else rng.randint(4,12)
    d["tariffs"]=[dict(start_time="00:00",end_time="24:00",price_vnd_kwh=2000)]
    d["grid_limit_kw"]=rng.choice((3,6,10,20,40))
    templates=d["requests"]
    for j,station in enumerate(d["stations"]):
        prototype=station["ports"][0]
        n=rng.randint(8,24) if hard else rng.randint(2,6)
        station["ports"]=[dict(prototype,port_id=f"s{j}p{k}") for k in range(n)]
        station["station_power_kw"]=rng.randint(2,2*n)
    d["requests"]=[]
    for k in range(count):
        src=rng.choice(templates)
        sid=0 if src["station_id"]==10 else 1
        if k==0:
            src=templates[0]
            sid=0
        station=d["stations"][sid]
        departure=rng.randint(2,d["horizon_slots"])
        a=0 if k==0 else rng.randint(0,departure-1)
        def stamp(t: int) -> str:
            """Đổi số slot tương đối sang giờ ISO của ngày nghiệm thu."""
            return f"2026-11-18T{17+t//4:02d}:{15*(t%4):02d}:00+07:00"
        d["requests"].append(dict(src,request_id=f"r{k}",arrival_time=stamp(a),
            departure_time=stamp(departure),energy_needed_kwh=rng.randint(2,14)*.25,
            energy_delivered_kwh=.25 if k==0 else 0,
            priority_weight=rng.choice((1,2,3)),status="CHARGING" if k==0 else "PENDING",
            locked_port_id=station["ports"][0]["port_id"] if k==0 else None))
    return d


def check(url: str | None = None) -> int:
    """In bốn dòng PASS/FAIL và trả mã khác không nếu một hạng mục không đạt."""
    rng=Random(SEED)
    counts=[0]*4
    totals=[0]*4
    details: dict[int,list[str]]={i:[] for i in range(4)}
    algorithms: Counter[str]=Counter()
    engines={"OPTIMIZER":solve,**{n:SOLVERS[n] for n in ("LLF","FCFS","EDF","EQUAL_SHARE")}}
    for i in range(200):
        p=normalize(OptimizeRequest.model_validate(instance(rng,i)))
        for name,fn in engines.items():
            for k in range(3):
                totals[k]+=1
            try:
                s=fn(p)
                if name=="OPTIMIZER":
                    algorithms[f"{s.algorithm.value}/{s.status.value}"]+=1
                report=validate_solution(p,s)
                switch_ok=all(v in (0,p.ports[j].max_power_kw) for (_,j,_),v in s.power.items()
                              if p.ports[j].control_type=="ON_OFF_SWITCH")
                r=p.requests["r0"]
                rows=[(j,t,v) for (rid,j,t),v in s.power.items() if rid==r.request_id]
                locked_ok=(r.energy_delivered_kwh>0 if hasattr(r,"energy_delivered_kwh")
                           else p.source_requests[r.request_id].energy_delivered_kwh>0)
                locked_ok &= (s.assign.get(r.request_id,r.locked_port_id)==r.locked_port_id and
                              all(j==r.locked_port_id and t>=p.first_mutable_slot for j,t,_ in rows) and
                              sum(v for _,_,v in rows)*p.dt<=r.remaining_kwh+1e-6)
                for k,good in enumerate((report.ok and s.status in {"OPTIMAL","FEASIBLE","FALLBACK"},
                                         switch_ok,locked_ok)):
                    counts[k]+=int(good)
                    if not good and len(details[k])<3:
                        details[k].append(f"instance={i} {name} {report.violations[:1]}")
            except Exception as exc:
                for k in range(3):
                    if len(details[k])<3:
                        details[k].append(f"{i}/{name}: {exc}")
    client=None
    durations=[]
    totals[3]=20
    try:
        if url is None:
            from fastapi.testclient import TestClient
            from ai_engine.main import app
            client=TestClient(app)
        for i in range(20):
            payload=instance(rng,i,True)
            encoded=json.dumps(payload).encode()
            start=perf_counter()
            try:
                if url:
                    request=Request(url.rstrip("/")+"/ai/optimize",data=encoded,
                                    headers={"Content-Type":"application/json"})
                    with urlopen(request,timeout=2.5) as response:
                        status,raw=response.status,response.read()
                else:
                    response=client.post("/ai/optimize",content=encoded,
                                         headers={"Content-Type":"application/json"})
                    status,raw=response.status_code,response.content
                elapsed=(perf_counter()-start)*1000
                durations.append(elapsed)
                result=OptimizeResponse.model_validate_json(raw)
                if status!=200 or elapsed>2500 or result.status not in {"OPTIMAL","FEASIBLE","FALLBACK"}:
                    raise ValueError(f"HTTP={status}, {elapsed:.1f} ms, {result.status}")
                counts[3]+=1
            except Exception as exc:
                if len(details[3])<3:
                    details[3].append(f"instance={i}: {exc}")
    except ImportError as exc:
        details[3].append(f"Chưa chạy được HTTP: {exc}")
    finally:
        if client:
            client.close()
    print(f"Seed {SEED}; 200 snapshot × 5 solver. Solver chính thực tế: {dict(algorithms)}")
    for k,label in enumerate(("Ràng buộc cứng","ON_OFF_SWITCH","Khóa lịch MPC","Chống treo API")):
        ok=counts[k]==totals[k]
        print(f"{label:18} {'PASS' if ok else 'FAIL':4} {counts[k]:4}/{totals[k]}  {' | '.join(details[k])}")
    if durations:
        print(f"HTTP tối đa: {max(durations):.1f} ms")
    return int(counts!=totals)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url",help="URL service đang chạy; mặc định dùng FastAPI TestClient")
    raise SystemExit(check(parser.parse_args().base_url))
