"""Huấn luyện và dự báo số lượt đến theo giờ, độc lập với bộ lập lịch."""

from __future__ import annotations

import hashlib
import math
import os
import tempfile
import warnings
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Iterable

import joblib
import numpy as np
import pandas as pd

from .schemas import ForecastHistoryItem

MODELS = Path(__file__).parent / "models"
NAMES = ("HOURLY_MEAN", "RANDOM_FOREST", "XGBOOST")
HOUR = timedelta(hours=1)
History = pd.DataFrame | list[dict[str, Any]] | list[ForecastHistoryItem]


def _series(history: History, cluster: str) -> dict[datetime, int]:
    """Chọn một cụm, kiểm tra múi giờ, giữ nguyên khoảng trống quan sát."""
    rows = history.to_dict("records") if isinstance(history, pd.DataFrame) else history
    result = {}
    for raw in rows:
        if isinstance(raw, ForecastHistoryItem):
            item = raw
        else:
            if raw.get("cluster_id", cluster) != cluster:
                continue
            item = ForecastHistoryItem.model_validate({k:raw[k] for k in ("hour_start","arrivals")})
        if item.hour_start in result:
            raise ValueError("Lịch sử trùng giờ")
        result[item.hour_start] = item.arrivals
    if not result:
        raise ValueError("Không có lịch sử của cụm")
    return dict(sorted(result.items()))


def _holidays(values: Iterable[str | date] | None) -> set[str]:
    """Đọc ngày lễ cấu hình ở dạng YYYY-MM-DD theo giờ Việt Nam."""
    if values is None:
        values = filter(None, os.getenv("EV_VN_HOLIDAYS", "").split(","))
    return {date.fromisoformat(str(v).strip()).isoformat() for v in values}


def _kind(t: datetime, holidays: set[str]) -> int:
    """Phân biệt ngày thường, cuối tuần và ngày lễ."""
    return 2 if t.date().isoformat() in holidays else int(t.weekday() >= 5)


def _features(t: datetime, past: dict, holidays: set[str]) -> list[float]:
    """Dựng lag theo giờ lịch và trung bình 24 giờ trước thời điểm t."""
    window = [past[t-HOUR*i] for i in range(1,25) if t-HOUR*i in past]
    return [t.hour, t.weekday(), int(t.weekday()>=5), int(_kind(t,holidays)==2),
            past.get(t-24*HOUR,-1), past.get(t-168*HOUR,-1),
            sum(window)/len(window) if window else -1]


def _fit(name: str, data: dict, holidays: set[str], seed: int) -> Any:
    """Huấn luyện một mô hình bằng lịch sử tính đến thời điểm chốt."""
    if name == "HOURLY_MEAN":
        groups = defaultdict(list)
        for t,y in data.items():
            groups[_kind(t,holidays),t.hour].append(y)
            groups[-1,t.hour].append(y)
        return {k:sum(v)/len(v) for k,v in groups.items()} | {(-1,-1):sum(data.values())/len(data)}
    if name == "RANDOM_FOREST":
        from sklearn.ensemble import RandomForestRegressor
        model = RandomForestRegressor(n_estimators=64,min_samples_leaf=4,n_jobs=1,random_state=seed)
    elif name == "XGBOOST":
        from xgboost import XGBRegressor
        model = XGBRegressor(n_estimators=120,max_depth=4,learning_rate=.08,n_jobs=1,
                             objective="reg:squarederror",random_state=seed)
    else:
        raise ValueError(f"Model không hợp lệ: {name}")
    return model.fit(np.asarray([_features(t,data,holidays) for t in data]),list(data.values()))


def _one(name: str, estimator: Any, t: datetime, past: dict, holidays: set[str]) -> int:
    """Dự báo một bước và chuyển sang số lượt nguyên không âm."""
    if name == "HOURLY_MEAN":
        v = estimator.get((_kind(t,holidays),t.hour),estimator.get((-1,t.hour),estimator[-1,-1]))
    else:
        v = estimator.predict(np.asarray([_features(t,past,holidays)]))[0]
    return max(0,round(float(v)))


def _path(root: Path, cluster: str, name: str) -> Path:
    """Tách artifact theo cụm và thuật toán bằng tên an toàn."""
    return root / hashlib.sha256(cluster.encode()).hexdigest() / (name+".joblib")


def train(history: History, algorithm: str, cluster_id: str | None = None, *,
          holidays: Iterable[str | date] | None = None, models_dir: Path = MODELS,
          seed: int = 42) -> dict[str, Any]:
    """Đánh giá trên 20% giờ cuối theo từng cửa sổ tối đa 24 giờ, rồi fit lại."""
    if cluster_id is None:
        rows = history.to_dict("records") if isinstance(history,pd.DataFrame) else history
        ids = {row["cluster_id"] for row in rows if isinstance(row,dict) and "cluster_id" in row}
        if len(ids)>1:
            raise ValueError("Cần chỉ định cluster_id cho lịch sử nhiều cụm")
        cluster_id = next(iter(ids),"default")
    data = _series(history,cluster_id)
    if algorithm not in NAMES:
        raise ValueError("Thuật toán không hợp lệ")
    if len(data)<2:
        raise ValueError("Cần ít nhất hai giờ để chia train/test")
    days = _holidays(holidays)
    name = algorithm if len(data)>=336 else "HOURLY_MEAN"
    notice = [] if name==algorithm else ["Dưới 336 giờ quan sát, dùng Hourly Mean."]
    items = list(data.items())
    cut = min(len(items)-1,max(1,int(.8*len(items))))
    past = dict(items[:cut])
    estimator = _fit(name,past,days,seed)
    errors = []
    for start in range(cut,len(items),24):
        block = items[start:start+24]
        simulated = past.copy()
        for t,y in block:
            yhat = _one(name,estimator,t,simulated,days)
            errors.append(yhat-y)
            simulated[t] = yhat
        past.update(block)
    metrics = dict(mae=float(np.mean(np.abs(errors))),rmse=math.sqrt(float(np.mean(np.square(errors)))))
    # Chỉ so sánh MAE khi các model đánh giá cùng lịch sử và cùng cửa sổ.
    signature = hashlib.sha256(repr(items).encode()).hexdigest()
    artifact = dict(model=name,estimator=_fit(name,data,days,seed),metrics=metrics,
                    holidays=days,end=items[-1][0],signature=signature)
    target = _path(models_dir,cluster_id,name)
    target.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent,delete=False) as tmp:
        temp = Path(tmp.name)
    try:
        joblib.dump(artifact,temp,compress=3)
        os.replace(temp,target)
    finally:
        temp.unlink(missing_ok=True)
    return dict(model=name,metrics=metrics,warnings=notice,artifact=str(target))


def forecast(cluster_id: str, history: History, horizon_hours: int = 24,
             model: str = "HOURLY_MEAN", *, models_dir: Path = MODELS,
             holidays: Iterable[str | date] | None = None) -> dict[str,Any]:
    """Dự báo đệ quy và trả kèm model thực tế, cảnh báo và sai số holdout."""
    if horizon_hours<1 or model not in (*NAMES,"BEST"):
        raise ValueError("Cấu hình dự báo không hợp lệ")
    data = _series(history,cluster_id)
    last = max(data)
    notices = []
    candidates = []
    if len(data)>=336:
        for name in NAMES if model=="BEST" else (model,):
            path = _path(models_dir,cluster_id,name)
            if path.exists():
                try:
                    obj = joblib.load(path)
                    if obj["end"]<=last:
                        candidates.append(obj)
                except (ValueError,ImportError,OSError,EOFError,KeyError) as exc:
                    notices.append(f"Không đọc được model {name}: {type(exc).__name__}.")
    if candidates:
        latest = max(candidates,key=lambda a:a["end"])
        obj = min((a for a in candidates if a["signature"]==latest["signature"]),
                  key=lambda a:a["metrics"]["mae"])
        name,estimator,metrics,days = obj["model"],obj["estimator"],obj["metrics"],obj["holidays"]
    else:
        notices.append("Dưới 14 ngày quan sát." if len(data)<336 else "Chưa có artifact phù hợp.")
        notices[-1] += " Dùng Hourly Mean từ lịch sử hiện tại."
        name,days,metrics = "HOURLY_MEAN",_holidays(holidays),None
        estimator = _fit(name,data,days,42)
    predictions = []
    for i in range(1,horizon_hours+1):
        t = last+i*HOUR
        data[t] = _one(name,estimator,t,data,days)
        predictions.append(dict(hour_start=t.isoformat(),pred_arrivals=data[t]))
    return dict(cluster_id=cluster_id,model=name,horizon_hours=horizon_hours,
                predictions=predictions,metrics=metrics,warnings=notices)


def predict(cluster_id: str, history: History, horizon_hours: int = 24,
            model: str = "HOURLY_MEAN", **options: Any) -> list[dict[str,Any]]:
    """Trả danh sách dự báo; phát cảnh báo Python nếu cần fallback."""
    result = forecast(cluster_id,history,horizon_hours,model,**options)
    for message in result["warnings"]:
        warnings.warn(message,RuntimeWarning,stacklevel=2)
    return result["predictions"]
