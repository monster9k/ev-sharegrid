"""Kiểm tra mô hình, sai số holdout và hành vi dự phòng."""

from pathlib import Path

import pytest

from ai_engine.forecast import forecast, predict, train
from ai_engine.scripts.make_fake_history import make_history


@pytest.fixture(scope="module")
def fitted(tmp_path_factory: pytest.TempPathFactory) -> tuple:
    """Fit baseline trên một lịch sử chung."""
    root=tmp_path_factory.mktemp("models")
    rows=make_history(3)
    metrics=train(rows,"HOURLY_MEAN","C",models_dir=root)["metrics"]
    return root,rows,metrics


@pytest.mark.parametrize("name",["HOURLY_MEAN","RANDOM_FOREST","XGBOOST"])
def test_accuracy(fitted: tuple,name: str) -> None:
    """Ba thuật toán phải trả đủ 24 giờ và đạt ngưỡng trên cùng tập test."""
    root,rows,base=fitted
    result=train(rows,name,"C",models_dir=root)
    assert result["model"]==name and Path(result["artifact"]).is_file()
    assert result["metrics"]["mae"] <= 1.2*base["mae"]
    prediction=forecast("C",rows,model=name,models_dir=root)
    assert prediction["model"]==name and prediction["metrics"]==result["metrics"]
    assert len(prediction["predictions"])==24
    assert all(type(r["pred_arrivals"]) is int and r["pred_arrivals"]>=0 for r in prediction["predictions"])


def test_fallback(tmp_path: Path) -> None:
    """Thiếu artifact hoặc lịch sử ngắn đều phát cảnh báo."""
    rows=make_history(3)
    for history in (rows,rows[:120]):
        with pytest.warns(RuntimeWarning):
            items=predict("missing",history,model="XGBOOST",models_dir=tmp_path)
        assert len(items)==24 and items[0]["hour_start"].endswith("+07:00")


def test_best(fitted: tuple) -> None:
    """Chọn MAE nhỏ nhất trên cùng holdout."""
    root,rows,base=fitted
    rf=train(rows,"RANDOM_FOREST","C",models_dir=root)
    chosen=forecast("C",rows,model="BEST",models_dir=root)
    assert chosen["metrics"]["mae"] <= min(base["mae"],rf["metrics"]["mae"])
