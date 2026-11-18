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

Ngân sách mặc định là `DEFAULT_TIME_BUDGET_MS=10000` cho snapshot dưới 300 request. Từ 300 request, ngân sách dùng `LARGE_SCENARIO_TIME_BUDGET_MS=2000` và request gửi ngân sách cao hơn bị chặn ở mức này. Khi số request cần giải vượt `DECOMPOSE_THRESHOLD=250`, optimizer chuyển sang LLF trên toàn cụm. Tách MILP theo trạm sẽ làm mất ràng buộc trần cụm giữa các phần; LLF giữ trần đó và kết quả vẫn qua Validator. Vì vậy đây là fallback có kiểm soát, không phải bằng chứng MILP giải được 10.000 request.

Benchmark nhận một trong hai nguồn dữ liệu: snapshot inline hoặc scenario_id tương ứng với `ai_engine/data/scenarios/<id>.json`. Ví dụ demo đã có sẵn. Các lượt chạy tuần tự trên cùng snapshot và cùng seed. Bảng `summary` có KPI trung bình, số lần vượt trần lớn nhất, thời gian trung bình và độ lệch chuẩn tổng thể. `actual_algorithms` cho biết nếu MILP đã rơi về LLF. ASAP được phép vượt giới hạn trạm và cụm để đo tác dụng của điều phối. NSGA_II trả NOT_IMPLEMENTED.

### Số đo trên dữ liệu scenario đã commit

Chạy lại bằng một lệnh:

```sh
python -m ai_engine.scripts.benchmark_real --dataset-ref 3b4b6c6
```

Script gọi POST `/ai/benchmark` qua FastAPI TestClient với seed 42. Mỗi cụm được gửi riêng vì snapshot API chỉ nhận một cụm; kết quả gộp bằng tổng shortfall, chi phí, `solve_ms` và số lần vượt trần, tỷ lệ đúng hạn có trọng số theo request, còn đỉnh lấy từ tổng tải hai cụm ở từng slot. Các mốc 100, 500 và 1.000 chạy đủ bảy thuật toán; mốc 10.000 chỉ chạy LLF, EDF, FCFS, EQUAL_SHARE và ASAP. `benchmark_real.json` giữ các KPI và status đầy đủ, không làm tròn.

Scenario được sinh với seed 42 ở commit `9391fe6`; benchmark đọc scenario và catalog cuối ở commit dữ liệu `3b4b6c6`. Tổng nhu cầu/trần cấp trong 24 giờ/tỷ lệ tải/số request đỗ ít nhất 8 giờ:

| Request | Nhu cầu (kWh) | Trần (kWh) | Tỷ lệ tải | Đỗ ≥8 giờ |
|---:|---:|---:|---:|---:|
| 100 | 2916.9462000000003 | 20400.0 | 0.14298755882352943 | 60 |
| 500 | 16319.999999999967 | 20400.0 | 0.7999999999999984 | 300 |
| 1.000 | 16320.00000000003 | 20400.0 | 0.8000000000000014 | 600 |
| 10.000 | 16319.999999999905 | 20400.0 | 0.7999999999999954 | 6000 |

Mốc 100 giữ nguyên số dòng và vì vậy chỉ đạt 14.298755882352943% tải. Ở mốc 10.000, hai cụm có 5.882 và 4.118 request. LLF đạt `status=FEASIBLE`; với giá cố định, `solve_ms=669.5902999997543`, `on_time_rate=0.2622`, `total_shortfall_kwh=12428.5622`, `total_cost_vnd=7782875.599999985`, `peak_power_kw=573.9696000000002`, `cap_violations=0`. Với TOU 1.600/2.400/4.000 VND/kWh, `solve_ms=786.8831999999202`, `on_time_rate=0.2622`, `total_shortfall_kwh=12428.5622`, `total_cost_vnd=9925629.200000094`, `peak_power_kw=573.9696000000002`, `cap_violations=0`. Có 1.241 request ở mốc này không khớp đầu nối đang ACTIVE tại trạm; benchmark giữ nguyên chuẩn xe và các request này được tính vào KPI thiếu điện.

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
| scripts/benchmark_real.py | Gọi `/ai/benchmark` trên CSV theo Git ref và xuất kết quả đo |
| data/scenarios/demo.json | Snapshot ví dụ cho benchmark theo ID |
| benchmark_real.json | KPI đo được trên các scenario CSV 100, 500, 1.000 và 10.000 request |
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

Compose gắn thư mục `./models` vào container. Trên Linux, cấp quyền ghi thư mục này cho UID 10001 để lưu mô hình. Có thể đặt `WORKERS` (1), `LOG_LEVEL` (info), `DEFAULT_TIME_BUDGET_MS` (10000), `LARGE_SCENARIO_TIME_BUDGET_MS` (2000) và `DECOMPOSE_THRESHOLD` (250) trước khi khởi động. `/health` trả các giá trị này cùng ngưỡng request nhỏ 300. Để kiểm thử ngoài Docker, cài `python -m pip install -r ai_engine/requirements-dev.txt` từ thư mục cha.

## Chạy trên Windows

Các script và pytest tự cấu hình đầu ra UTF-8. Có thể chạy từ thư mục gốc bằng `python -m ai_engine.scripts.acceptance_check`. Trong PowerShell, khuyến nghị đặt `$env:PYTHONUTF8 = "1"` để các công cụ Python khác cũng dùng UTF-8. Biến này là tùy chọn.
