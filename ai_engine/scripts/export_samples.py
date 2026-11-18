"""Xuất dữ liệu bàn giao từ HTTP thực của ứng dụng, chạy bằng python -m."""

from copy import deepcopy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any

from ai_engine.schemas import OptimizeRequest, OptimizeResponse

ROOT = Path(__file__).resolve().parents[1]


def _json_bytes(value: Any) -> bytes:
    """Ghi JSON UTF-8, giữ tiếng Việt và từ chối số không hữu hạn."""
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf8")


def _cases() -> dict[str, bytes]:
    """Giữ nguyên byte của snapshot gốc và dựng ba biến thể độc lập."""
    original = (ROOT / "samples/page20_input.json").read_bytes()
    base = json.loads(original)
    charging = deepcopy(base)
    charging["input_version"] = "handover-charging"
    car = next(r for r in charging["requests"] if r["request_id"] == "A")
    car.update(status="CHARGING", locked_port_id=101, energy_delivered_kwh=0.5)
    fallback = dict(base, input_version="handover-fallback", time_budget_ms=1)
    shortfall = dict(base, input_version="handover-shortfall", grid_limit_kw=1.0)
    return {"": original, "_charging": _json_bytes(charging),
            "_fallback": _json_bytes(fallback), "_shortfall": _json_bytes(shortfall)}


def export(directory: Path = ROOT / "handover") -> None:
    """Kiểm tra toàn bộ kết quả trước khi cập nhật các file bàn giao."""
    from fastapi.testclient import TestClient
    from ai_engine.main import app

    files: dict[str, bytes] = {}
    with TestClient(app) as client:
        for suffix, payload in _cases().items():
            OptimizeRequest.model_validate_json(payload)
            reply = client.post("/ai/optimize", content=payload,
                                headers={"Content-Type": "application/json"})
            reply.raise_for_status()
            req_bytes = reply.request.content
            if req_bytes != payload:
                raise ValueError("Nội dung gửi đi khác snapshot")
            sol = OptimizeResponse.model_validate_json(reply.content)
            if sol.status not in {"OPTIMAL", "FEASIBLE", "FALLBACK"}:
                raise ValueError(f"{suffix or 'page20'}: trạng thái {sol.status}")
            if suffix == "_charging":
                rows = [row for row in sol.schedules if row.request_id == "A"]
                if not rows or any(row.port_id != "101" for row in rows):
                    raise ValueError("Mẫu CHARGING chưa giữ đúng cổng 101")
            if suffix == "_fallback" and (sol.status != "FALLBACK" or sol.algorithm != "LLF"):
                raise ValueError("Mẫu ngân sách nhỏ chưa trả FALLBACK/LLF")
            if suffix == "_shortfall" and not (sol.kpi.total_shortfall_kwh > 0 and
                    any(r.shortfall_kwh > 0 and r.explanation for r in sol.request_results)):
                raise ValueError("Mẫu thiếu điện chưa có xe bị thiếu và lời giải thích")
            files[f"sample_request{suffix}.json"] = req_bytes
            files[f"sample_response{suffix}.json"] = reply.content
            print(f"{suffix or 'page20'}: HTTP {reply.status_code}, {sol.status.value}, "
                  f"{sol.algorithm}, shortfall={sol.kpi.total_shortfall_kwh:g} kWh")
        files["openapi.json"] = _json_bytes(app.openapi())
    directory.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=directory) as temp:
        stage = Path(temp)
        for name, raw in files.items():
            path = stage / name
            path.write_bytes(raw)
            saved = path.read_bytes()
            json.loads(saved)
            if name.startswith("sample_request"):
                OptimizeRequest.model_validate_json(saved)
            elif name.startswith("sample_response"):
                OptimizeResponse.model_validate_json(saved)
        for name in files:
            (stage / name).replace(directory / name)
    print(f"Đã xuất {len(files)} file JSON vào {directory}")


if __name__ == "__main__":
    export()
