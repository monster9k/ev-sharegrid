# EV ShareGrid AI Engine

Service HTTP JSON điều phối sạc theo slot 15 phút và dự báo lượt xe theo giờ. Chạy các lệnh từ thư mục **chứa** `ai_engine/`, với Python 3.10 trở lên.

## Cài và chạy

```sh
python -m venv .venv
# Bash: source .venv/bin/activate
# PowerShell: .\.venv\Scripts\Activate.ps1
python -m pip install -r ai_engine/requirements.txt
python -m uvicorn ai_engine.main:app --port 8001
```

Swagger ở `http://localhost:8001/docs`. `GET /health` trả phiên bản và danh sách các backend phát hiện được. CORS tắt mặc định. Thời gian JSON dùng múi giờ +07:00.

## Gọi API bằng curl (Bash)

```sh
curl -sS http://localhost:8001/ai/optimize \
  -H 'Content-Type: application/json' -H 'X-Request-ID: demo-001' \
  --data-binary @ai_engine/samples/input_snapshot.json

curl -sS http://localhost:8001/ai/benchmark \
  -H 'Content-Type: application/json' \
  -d '{"scenario_id":"demo","algorithms":["MILP_MPC","LP_MPC","LLF","EDF","FCFS","EQUAL_SHARE","ASAP","NSGA_II"],"seed":42,"repeats":2}'

curl -sS http://localhost:8001/ai/forecast \
  -H 'Content-Type: application/json' \
  -d '{"cluster_id":"demo","history":[{"hour_start":"2026-11-18T08:00:00+07:00","arrivals":7}],"horizon_hours":24,"model":"BEST"}'
```

Optimize trả 422 khi payload sai schema. Với payload hợp lệ, đọc `status` trong body HTTP 200. Khi solver lỗi, service thử LLF rồi kiểm tra lịch. Worker chạy trong tiến trình riêng. Khi vượt hạn `time_budget_ms + 500` ms tính từ lúc handler bắt đầu, service dừng worker và trả `ERROR`. `algorithm=null` khi không có kết quả để công bố. KPI trong phản hồi ERROR là giá trị giữ chỗ. `solve_ms` của nghiệm thành công đo thời gian chuẩn hóa, giải và kiểm tra trong worker. Tổng độ trễ HTTP còn có thời gian khởi động Python, mã hóa phản hồi và truyền mạng. Header X-Request-ID dùng để đối chiếu với log.

Solver hiện dùng SCIP cho biến nguyên, GLOP khi miền nghiệm tuyến tính chính xác. `LP_MPC` có thể dùng SCIP nếu còn cổng đóng/ngắt, có công suất sàn hoặc hai xe có khả năng tranh cổng. Trường algorithm phản ánh backend thực tế. Slot đã chạy được giữ nguyên khi có previous_schedule. Điện năng còn lại phải bao gồm toàn bộ điện của slot freeze nếu gửi slot đó trong lịch cũ. Bản này chưa tích hợp Master LP với các worker theo trạm.

Benchmark nhận một trong hai nguồn dữ liệu: snapshot inline hoặc scenario_id tương ứng với `ai_engine/data/scenarios/<id>.json`. Ví dụ demo đã có sẵn. Các lượt chạy tuần tự trên cùng snapshot và cùng seed. Bảng `summary` có KPI trung bình, số lần vượt trần lớn nhất, thời gian trung bình và độ lệch chuẩn tổng thể. `actual_algorithms` cho biết nếu MILP đã rơi về LLF. ASAP được phép vượt giới hạn trạm và cụm để đo tác dụng của điều phối. NSGA_II trả NOT_IMPLEMENTED.

## Huấn luyện dự báo

```sh
python -m ai_engine.scripts.make_fake_history --months 4 --seed 42 --output history.csv
```

```python
import pandas as pd
from ai_engine.forecast import train, predict

history = pd.read_csv("history.csv")
for name in ("HOURLY_MEAN", "RANDOM_FOREST", "XGBOOST"):
    result = train(history, name, cluster_id="demo", holidays=["2025-01-01"])
    print(name, result["metrics"], result["artifact"])
points = predict("demo", history, horizon_hours=24, model="BEST")
```

Gói bàn giao có hai artifact demo cho cluster `synthetic-demo` (Hourly Mean và Random Forest, 90 ngày giả, seed 42). Huấn luyện lại bằng dữ liệu cụm trước khi dùng thực tế.

Có thể truyền lịch sử dưới dạng list hoặc DataFrame. Nếu có cột cluster_id, huấn luyện/lấy dự báo theo đúng cụm. Tính feature theo giờ Việt Nam: giờ trong ngày, thứ, cuối tuần, lễ, số lượt đúng 24/168 giờ trước và trung bình 24 giờ trước. Lag thiếu dùng -1, giờ thiếu trong lịch sử không được coi là 0 lượt. Danh sách ngày lễ cấu hình qua tham số holidays hoặc biến môi trường EV_VN_HOLIDAYS (YYYY-MM-DD phân cách bằng dấu phẩy). Mặc định danh sách rỗng. Cần truyền ngày nghỉ thực tế cho từng năm.

Giữ 20% quan sát cuối làm tập đánh giá. Mỗi khối tối đa 24 quan sát dùng dự báo trước đó trong cùng khối để tính lag. Sau đánh giá, fit lại trên toàn bộ lịch sử và lưu artifact tại `ai_engine/models/<mã băm cụm>/<MODEL>.joblib`. BEST so MAE trên cùng dữ liệu đánh giá. API trả model thực tế, metrics gồm MAE/RMSE theo đơn vị lượt/giờ, warnings và predictions. Khi có dưới 336 giờ quan sát hoặc thiếu artifact phù hợp, API tính Hourly Mean từ lịch sử gửi lên. Khi không có đánh giá holdout, metrics là null. Forecast chỉ trả số lượt đến, độc lập với ngân sách công suất và lịch sạc.

## Kiểm thử

```sh
# TestClient của FastAPI cần httpx trong môi trường kiểm thử.
python -m pip install httpx
python -m pytest ai_engine/tests -q
python -m ai_engine.schemas
```

## Các file

| File hoặc thư mục | Chức năng |
|---|---|
| schemas.py | Hợp đồng Pydantic, enum, JSON Schema cho Backend |
| normalizer.py | Chuyển timestamp, giá và cửa sổ sạc thành dữ liệu theo slot |
| baselines.py | Năm thuật toán đối chứng và tính KPI |
| optimizer_milp.py | Bộ giải SCIP/GLOP, warm start LLF và mục tiêu nhiều lượt |
| validator.py | Kiểm tra độc lập ràng buộc và điều hành fallback |
| explainer.py | Tính kết quả từng xe, diễn giải theo slot thực tế |
| forecast.py | Huấn luyện, chọn model, lưu artifact và dự báo theo giờ |
| service.py | Chạy pipeline optimize trong worker và chuyển kết quả sang JSON |
| main.py | FastAPI, timeout tiến trình, benchmark, forecast và health |
| scripts/make_fake_history.py | Sinh 3–6 tháng dữ liệu giả có chu kỳ và nhiễu |
| data/scenarios/demo.json | Snapshot ví dụ cho benchmark theo ID |
| samples/ | Snapshot, lịch và bộ JSON Schema mẫu |
| tests/ | Test solver, dữ liệu, forecast và HTTP |
| requirements.txt | Các phụ thuộc chạy service |

## Xuất mẫu cho FE/BE

Chạy từ thư mục cha của `ai_engine/`, trong cùng môi trường đã cài requirements và httpx:

```sh
python -m ai_engine.scripts.export_samples
python -m uvicorn ai_engine.main:app --port 8001
```

Lệnh đầu dùng FastAPI TestClient, không cần bật server. Script ghi nguyên body request và response vào `ai_engine/handover/` sau khi kiểm tra bốn ca và xuất OpenAPI. Mẫu shortfall có cả request để Khoa tái hiện. Đối chiếu các cột DB và ý nghĩa expected_soc trong `handover/FIELD_MAPPING.md`. Lệnh thứ hai mở server thật; gọi `GET http://127.0.0.1:8001/health` để kiểm tra.

## Chạy bằng Docker

Từ thư mục cha của `ai_engine`, chạy:

```sh
cd ai_engine
docker compose -f docker-compose.ai.yml up -d --build
curl -fsS http://localhost:8001/health
curl -fsS -H "Content-Type: application/json" --data-binary @samples/page20_input.json http://localhost:8001/ai/optimize
docker compose -f docker-compose.ai.yml down
```

Compose gắn thư mục `./models` vào container. Trên Linux, cấp quyền ghi thư mục này cho UID 10001 để lưu mô hình. Có thể đặt `WORKERS` (1), `LOG_LEVEL` (info) và `DEFAULT_TIME_BUDGET_MS` (2000) trước khi khởi động. Ngân sách trong request được ưu tiên. API hiển thị `DECOMPOSE_THRESHOLD` (1000) qua health; bản solver hiện tại chưa triển khai Master LP để sử dụng ngưỡng này. Để kiểm thử ngoài Docker, cài `python -m pip install -r ai_engine/requirements-dev.txt` từ thư mục cha.
