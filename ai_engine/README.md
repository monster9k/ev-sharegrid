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

Optimize trả 422 khi payload sai schema. Với payload hợp lệ, đọc `status` trong body HTTP 200. Khi solver lỗi, service thử LLF rồi kiểm tra lịch. Worker chạy trong tiến trình riêng. Khi vượt hạn `time_budget_ms + 500` ms tính từ lúc handler bắt đầu, service dừng worker và trả `ERROR`. `algorithm=null` khi không có kết quả để công bố. KPI trong phản hồi ERROR là giá trị giữ chỗ. Trường `fallback_reason` ghi `THRESHOLD_EXCEEDED`, `TIME_BUDGET_EXHAUSTED`, `SEED_NOT_IMPROVED`, `SOLVER_ERROR` hoặc `NONE`. `solve_ms` của nghiệm thành công đo thời gian chuẩn hóa, giải và kiểm tra trong worker. Tổng độ trễ HTTP còn có thời gian khởi động Python, mã hóa phản hồi và truyền mạng. Header X-Request-ID dùng để đối chiếu với log.

Solver hiện dùng SCIP cho biến nguyên, GLOP khi miền nghiệm tuyến tính chính xác. `LP_MPC` có thể dùng SCIP nếu còn cổng đóng/ngắt, có công suất sàn hoặc hai xe có khả năng tranh cổng. Trường algorithm phản ánh backend thực tế. Slot đã chạy được giữ nguyên khi có previous_schedule. Điện năng còn lại phải bao gồm toàn bộ điện của slot freeze nếu gửi slot đó trong lịch cũ. Bản này chưa tích hợp Master LP với các worker theo trạm.

Ngân sách mặc định là `DEFAULT_TIME_BUDGET_MS=10000` cho snapshot dưới 300 request. Từ 300 request, ngân sách dùng `LARGE_SCENARIO_TIME_BUDGET_MS=2000` và request gửi ngân sách cao hơn bị chặn ở mức này. Khi số request cần giải vượt `DECOMPOSE_THRESHOLD=250`, optimizer chuyển sang LLF trên toàn cụm. Tách MILP theo trạm sẽ làm mất ràng buộc trần cụm giữa các phần; LLF giữ trần đó và kết quả vẫn qua Validator. Vì vậy đây là fallback có kiểm soát, không phải bằng chứng MILP giải được 10.000 request.

Benchmark nhận một trong hai nguồn dữ liệu: snapshot inline hoặc scenario_id tương ứng với `ai_engine/data/scenarios/<id>.json`. Ví dụ demo đã có sẵn. Các lượt chạy tuần tự trên cùng snapshot và cùng seed. Bảng `summary` có KPI trung bình, số lần vượt trần lớn nhất, thời gian trung bình và độ lệch chuẩn tổng thể. `actual_algorithms` cho biết nếu MILP đã rơi về LLF. ASAP được phép vượt giới hạn trạm và cụm để đo tác dụng của điều phối. NSGA_II trả NOT_IMPLEMENTED.

### Số đo trên dữ liệu scenario đã commit

Chẩn đoán trước khi sửa MILP trên CSV tại `b0fc3f7`, seed 42 và ngân sách 10.000 ms mỗi cụm. Cả bốn lượt đều trả `LLF / FALLBACK / SEED_NOT_IMPROVED`.

| Biểu giá | Cụm 1 (59 request), solve_ms | Cụm 2 (41 request), solve_ms |
|---|---:|---:|
| Cố định 2.000 đ/kWh | 3063.4715000051074 | 3230.1406000042334 |
| TOU giả định | 3334.9094000004698 | 3041.2056000059238 |

Tầng điện thiếu tìm được nghiệm khả thi nhưng chưa cải thiện seed trong dung sai. Code cũ kết thúc ngay ở tầng này.

`benchmark_real.json` được đo lại từ CSV tại `b0fc3f7`, với seed 42 cho sinh dữ liệu và benchmark. JSON lưu SHA-256 của từng CSV. Chạy lại từ thư mục gốc:

```sh
python -m ai_engine.scripts.benchmark_real --dataset-ref b0fc3f7
```

Mỗi cụm dùng một lượt `POST /ai/benchmark` qua FastAPI TestClient cho mỗi biểu giá. Script cộng chi phí, điện thiếu, số lần vượt trần và `solve_ms` của hai cụm. Tỷ lệ đúng hạn được tính theo số request. Đỉnh lấy từ tổng tải hai cụm ở cùng slot. `solve_ms` gồm thời gian chuẩn hóa, giải và kiểm tra, phụ thuộc máy và tải khi chạy. JSON giữ cấu trúc `milestones → tariffs → algorithms`, ghi thuật toán thực tế, trạng thái và lý do fallback cho từng cụm. Mã biểu giá TOU được giữ để tương thích. Các mức 1.600/2.400/4.000 đ/kWh là biểu giá giả định.

MILP được yêu cầu ở mốc 100 và 500 theo ngân sách chuẩn và vẫn dùng ngưỡng 250. Solver giới hạn tổng điện thiếu và điện thiếu có trọng số theo seed LLF. Khi chưa chứng minh tối ưu toàn bộ các tầng, nó trả nghiệm MILP tốt nhất đã kiểm tra dưới trạng thái `FEASIBLE` nếu có. Các mốc 1.000 và 10.000 chỉ chạy LLF, EDF, FCFS, EQUAL_SHARE và ASAP để đo thông lượng.

`data/scenario_10000_llf_measurement.json` ghi một lần đo LLF riêng với giá cố định. CSV trong Git dùng LF (SHA-256 bắt đầu bằng `4539c0b7`). Đổi dấu xuống dòng sang CRLF cho đúng SHA-256 của lần đo riêng (`472f4cb5`). Benchmark này đo lại LLF ở cả hai biểu giá. Bộ 10.000 mang nhãn `LLF_THROUGHPUT_ONLY` vì nhu cầu vượt khả năng cấp 24 giờ.

### MILP so với LLF trên cùng request

Ở mốc 100, cả hai cụm đều trả nghiệm MILP ở trạng thái `FEASIBLE`. Ở mốc 500, cụm 1 (294 request) vượt ngưỡng 250 nên dùng LLF với `FALLBACK / THRESHOLD_EXCEEDED`. Cụm 2 (206 request) trả nghiệm MILP với `FEASIBLE / NONE`. Bảng so sánh chỉ tính những cụm có nghiệm MILP. Phần trăm giảm dùng LLF làm mẫu số. Chênh lệch đúng hạn tính bằng điểm phần trăm.

| Mốc và phạm vi | Giá (đ/kWh) | Giảm chi phí | Giảm đỉnh | Chênh đúng hạn |
|---|---|---:|---:|---:|
| 100, cả hai cụm | 2.000 | ≈0% | 0,4411% | 0 |
| 100, cả hai cụm | TOU | 0,2546% | 0,4411% | 0 |
| 500, chỉ cụm 2 | 2.000 | −0,0124% | ≈0% | +0,4854 |
| 500, chỉ cụm 2 | TOU | 0,3952% | ≈0% | +0,9709 |

Lượt đo ngày 19/11/2026 thấp hơn các mức giảm 22–25% chi phí và 64–66% đỉnh từng được báo cáo. Với giá cố định ở cụm 2 mốc 500, MILP cấp thêm 0,6504 kWh và chi phí tăng khoảng 1.301 đồng. Ở mốc 1.000 và 10.000, danh sách thuật toán đo thông lượng loại MILP ngay từ đầu.

### KPI của hai cụm gộp lại

Đơn vị giá cố định là 2.000 đ/kWh, TOU là 1.600/2.400/4.000 đ/kWh. Dòng “LLF + MILP” ghi kết quả khi yêu cầu MILP ở mốc 500, theo thứ tự cụm 1 rồi cụm 2. Tất cả các dòng dưới đây đều có 0 lần vượt trần. Bảng làm tròn khi hiển thị, JSON giữ nguyên kết quả đo.

| Request | Giá | Thực chạy | Đúng hạn | Thiếu (kWh) | Chi phí (đ) | Đỉnh (kW) | solve_ms |
|---:|---|---|---:|---:|---:|---:|---:|
| 100 | Cố định | MILP | 94% | 17,5719 | 4.909.489,60 | 681,0700 | 15.961,31 |
| 100 | Cố định | LLF | 94% | 17,5719 | 4.909.489,60 | 684,0876 | 12,43 |
| 100 | TOU | MILP | 94% | 17,5719 | 7.172.282,48 | 681,0700 | 15.708,39 |
| 100 | TOU | LLF | 94% | 17,5719 | 7.190.587,84 | 684,0876 | 10,14 |
| 500 | Cố định | LLF + MILP | 68,2% | 2.613,4802 | 27.413.039,20 | 850 | 10.441,34 |
| 500 | Cố định | LLF | 68% | 2.614,1306 | 27.411.738,40 | 850 | 70,17 |
| 500 | TOU | LLF + MILP | 68,4% | 2.613,4802 | 37.246.807,04 | 850 | 11.331,22 |
| 500 | TOU | LLF | 68% | 2.614,1306 | 37.302.182,96 | 850 | 59,23 |
| 1.000 | Cố định | LLF | 52,2% | 5.184,4282 | 22.271.142,20 | 850 | 77,56 |
| 1.000 | TOU | LLF | 52,2% | 5.184,4282 | 30.135.059,84 | 850 | 91,86 |
| 10.000 | Cố định | LLF | 1,74% | 224.282,5779 | 42.161.966,00 | 850 | 707,04 |
| 10.000 | TOU | LLF | 1,74% | 224.282,5779 | 54.107.690,00 | 850 | 939,15 |

Ở mốc 10.000, nhu cầu là 245.363,5609 kWh trên khả năng cấp 20.400 kWh trong 24 giờ. Tỷ lệ đúng hạn 1,74% đi kèm với mức quá tải này.

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
