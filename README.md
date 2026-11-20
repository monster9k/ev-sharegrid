# EV ShareGrid

EV ShareGrid là nguyên mẫu điều phối sạc xe điện tại Đà Nẵng cho Smart Campus 2026 – ISSCEI. Hệ thống xếp lịch sạc theo cửa sổ đỗ xe, công suất cổng, trần công suất cụm và biểu giá.

Trong chủ đề WEFE, dự án tập trung vào năng lượng và giao thông thông minh. Việc điều phối giờ sạc giúp đánh giá khả năng giảm đỉnh tải và tận dụng khung giờ giá thấp hơn trên hạ tầng hiện có.

## Trạng thái tích hợp

| Thành phần | Trạng thái hiện tại |
|---|---|
| Flutter | Đăng nhập, tải xe và trạm, đặt lịch, xem lịch, xác nhận và hủy lịch qua API. Các màn như bản đồ, lịch sử phiên sạc, quản lý cổng của HOST và dự báo của ADMIN vẫn có dữ liệu mô phỏng. |
| Admin Benchmark | Màn ADMIN đọc `GET /api/v1/admin/benchmark`. Trong Compose, backend đọc [báo cáo benchmark](ai_engine/benchmark_real.json) được mount chỉ đọc. |
| Backend FastAPI | JWT và phân quyền USER/HOST/ADMIN. CORS cho Flutter Web tại `http://localhost` với cổng tùy chọn. `POST /api/v1/requests` trả HTTP 422 nếu khung sạc vượt cửa sổ tối ưu 24 giờ và HTTP 409 nếu trùng `idempotency_key`. |
| AI Engine FastAPI | Backend gửi snapshot qua `/ai/optimize`. Solver dùng OR-Tools SCIP cho biến nguyên, GLOP cho bài toán đủ điều kiện tuyến tính và LLF khi cần fallback. [Ca kiểm chuẩn Trang 20](ai_engine/samples/page20_input.json) trả `MILP_MPC / OPTIMAL`, chi phí 5.500 đ, thiếu điện 0 kWh. |
| PostgreSQL/PostGIS | [Schema 19 bảng](database/schema_19_tables.sql). Backend lưu yêu cầu, lần tối ưu và lịch theo slot 15 phút, rồi trả lịch cho Flutter. |

Khi worker tối ưu hết hạn, AI Engine dừng worker nếu còn chạy và thử LLF trong tiến trình phục vụ API. Nếu lịch qua kiểm tra, API trả `FALLBACK` kèm `TIME_BUDGET_EXHAUSTED`. Trường hợp này chỉ trả `ERROR` nếu LLF thất bại hoặc lịch không qua kiểm tra. [Hành vi của AI Engine](ai_engine/README.md#gọi-api-bằng-curl-bash)

```mermaid
flowchart LR
    U["Flutter Web / Mobile"] -->|"JWT, REST"| B["Backend FastAPI · 8000"]
    B -->|"POST /ai/optimize · snapshot cụm"| A["AI Engine FastAPI · 8001"]
    A -->|"Lịch, KPI, trạng thái solver"| B
    B <-->|"Yêu cầu, lịch 15 phút, phân quyền"| D[("PostgreSQL / PostGIS · 19 bảng")]
    R["benchmark_real.json"] -->|"Mount chỉ đọc"| B
```

## Chạy demo cục bộ bằng Docker Compose

Bản nộp chấm thi chạy bằng **Docker Compose và Flutter Web trên máy local**. Firebase Hosting chỉ dùng để xem trước giao diện.

Cài Docker Engine với Docker Compose plugin, Python, Flutter và Chrome. Nếu Python local chưa có [thư viện backend](backend/requirements.txt), cài bằng `python -m pip install -r backend/requirements.txt`. Mở terminal tại thư mục gốc rồi chạy [script tạo môi trường](scripts/make_demo_env.py):

```sh
python scripts/make_demo_env.py
```

Script sinh cấu hình PostgreSQL và JWT, hỏi mật khẩu ẩn rồi ghi hash vào `.env`. Dùng `--generate-passwords` nếu muốn script sinh và in mật khẩu demo một lần. Git bỏ qua `.env`. Giữ `.env` đã dùng để khởi tạo volume PostgreSQL hiện có vì tạo mật khẩu mới trong file không đổi mật khẩu của DB.

Script nạp catalog tạo các tài khoản sau. Dùng mật khẩu đã chọn hoặc do script tạo lúc chuẩn bị `.env`.

| Vai trò | Email demo |
|---|---|
| USER | `user1@sharegrid.vn` |
| HOST | `host1@sharegrid.vn` |
| ADMIN | `admin@sharegrid.vn` |

```sh
docker compose config --quiet
docker compose up --build -d
docker compose ps -a
```

Chờ `postgres`, `ai-engine` và `backend` báo `healthy`. `catalog-seed` thoát mã 0 sau khi nạp catalog. Xem Swagger của [AI Engine](http://localhost:8001/docs) và [backend](http://localhost:8000/docs). Dùng `docker compose down` để dừng.

### Cập nhật biểu giá trên volume PostgreSQL cũ

Schema mới được nạp tự động khi tạo DB trống. Với volume đã có dữ liệu, chạy đoạn SQL sau trong DB `ev_sharegrid` trước khi seed lại.

```sql
BEGIN;
ALTER TABLE tariff_window
  DROP CONSTRAINT IF EXISTS tariff_window_day_type_check,
  ADD CONSTRAINT tariff_window_day_type_check
    CHECK (day_type IN ('WEEKDAY', 'WEEKEND', 'HOLIDAY', 'MON_SAT', 'SUNDAY'));
COMMIT;
```

Sau đó dùng hai lệnh dưới đây nếu chỉ muốn nạp biểu giá. Các khung cũ được giữ làm lịch sử và phục vụ fallback. Để hoàn tác trên DB đã có lịch sử, gỡ các dòng `MON_SAT` và `SUNDAY` của cụm demo 1–4 có `valid_from = '2026-11-01'` và `source_ref` đúng giá trị trong [script seed](scripts/import_catalog.py).

```sh
docker compose build catalog-seed
docker compose run --rm --no-deps catalog-seed python scripts/import_catalog.py --tariffs-only
```

### Chạy Flutter Web kết nối backend local

```sh
flutter pub get
flutter run -d chrome --web-hostname=localhost --web-port=7357 --no-web-resources-cdn --dart-define=API_BASE=http://localhost:8000 --dart-define=DEMO_OFFLINE=true
```

Mở [Flutter Web local](http://localhost:7357). Dùng hostname `localhost` cho trang Flutter để khớp cấu hình CORS. Hai tùy chọn dành cho demo offline dùng tài nguyên Flutter và font đã đóng gói cục bộ. Hãy chuẩn bị trước image Docker, các thư viện Python và Flutter nếu máy chấm sẽ chạy offline.

Đăng nhập bằng tài khoản USER để đặt lịch và xem các slot sạc. Đăng nhập bằng ADMIN để xem báo cáo tại `/admin/benchmark`. API đọc lịch trả trạng thái yêu cầu, các slot sạc và, khi đã có kết quả tối ưu, các trường `solver_status`, `algorithm`, `solve_ms` và `explanation`.

## Benchmark thực đo

[Báo cáo benchmark](ai_engine/benchmark_real.json) ghi kết quả ngày 20/11/2026 với seed 42, dùng CSV tại commit `14cec6f`. So với mốc cũ `b0fc3f7`, đầu vào khác duy nhất là CSV biểu giá. Script gọi `POST /ai/benchmark` theo từng cụm với giá cố định 2.000 đ/kWh và TOU EVN hạ áp **1.620 / 2.700 / 4.212 đ/kWh** trước VAT. Đây là kịch bản mô phỏng nhu cầu sạc. Bảng gộp hai cụm, tính đỉnh từ tổng tải theo slot và cộng `solve_ms` của hai lượt đo.

| Request | Giá | Thuật toán thực chạy | Đúng hạn | Thiếu (kWh) | Chi phí (đ) | Đỉnh (kW) | Vượt trần | solve_ms |
|---:|---|---|---:|---:|---:|---:|---:|---:|
| 100 | TOU EVN | MILP_MPC | 94% | 17,5719 | 8.276.432,26 | 681,0700 | 0 | 16.496,86 |
| 100 | TOU EVN | LLF | 94% | 17,5719 | 8.276.432,26 | 684,0876 | 0 | 17,23 |
| 100 | TOU EVN | ASAP | 94% | 17,5719 | 8.276.432,26 | 773,6312 | 0 | 23,08 |
| 500 | TOU EVN | LLF (cụm 1) + MILP_MPC (cụm 2) | 68,4% | 2.613,4802 | 42.054.657,06 | 850 | 0 | 11.421,22 |
| 500 | TOU EVN | LLF | 68% | 2.614,1306 | 42.133.018,13 | 850 | 0 | 98,56 |
| 1.000 | TOU EVN | LLF | 52,2% | 5.184,4282 | 34.134.439,81 | 850 | 0 | 122,53 |
| 10.000 | Cố định | LLF | 1,74% | 224.282,5779 | 42.161.966,00 | 850 | 0 | 1.052,56 |
| 10.000 | TOU EVN | LLF | 1,74% | 224.282,5779 | 58.341.803,90 | 850 | 0 | 2.327,44 |

- **100 request.** Cả hai cụm chạy `MILP_MPC / FEASIBLE`. MILP, LLF và ASAP có cùng chi phí TOU, tỷ lệ đúng hạn và điện thiếu ở độ chính xác hiển thị. Đỉnh của MILP thấp hơn LLF **3,0176 kW** và thấp hơn ASAP **92,5612 kW**.
- **500 request.** Cụm 1 có 294 request, vượt ngưỡng 250 nên dùng LLF (`THRESHOLD_EXCEEDED`). Cụm 2 có 206 request và trả `MILP_MPC / FEASIBLE`. Tại cụm 2, MILP giảm chi phí TOU **0,4817%** so với LLF, cùng đỉnh 350 kW. Với giá cố định, MILP cấp thêm 0,6504 kWh và chi phí tăng 1.300,80 đ so với LLF ở cụm này.
- **Thông lượng.** Báo cáo chỉ đo nhóm thuật toán nhanh ở mốc 1.000 và 10.000 request. Mốc 10.000 mang nhãn `LLF_THROUGHPUT_ONLY`. Đầu vào cần 245.363,5609 kWh trên khả năng cấp 20.400 kWh trong 24 giờ.
- **Vượt trần.** Các lượt MILP và LLF ghi 0 vi phạm. ASAP ở mốc 500 ghi 53 vi phạm trên hai cụm ở mỗi biểu giá. Đối chiếu chi phí với điện thiếu và số vi phạm công suất khi đọc KPI này.

Chạy lệnh dưới đây từ thư mục gốc để tái đo với cùng dữ liệu. Thời gian giải và nghiệm khả thi khi hết ngân sách có thể thay đổi theo máy.

```sh
python -m ai_engine.scripts.benchmark_real --dataset-ref 14cec6f
```

## Liên hệ chủ đề WEFE (Smart Campus 2026)

Trong trụ cột **Năng lượng xanh và Giao thông thông minh**, lịch sạc là một phụ tải có thể điều phối. Bảng dùng TOU EVN hạ áp và chỉ so sánh các cụm thực sự chạy `MILP_MPC`. `FCFS` là baseline phục vụ theo thứ tự đến (FIFO).

| Phạm vi | Baseline | Chi phí baseline → MILP (đ) | Giảm chi phí | Đỉnh baseline → MILP (kW) | Giảm đỉnh (kW) |
|---|---|---:|---:|---:|---:|
| 100, cả hai cụm | LLF | 8.276.432,26 → 8.276.432,26 | 0,0000% | 684,0876 → 681,0700 | 3,0176 |
| 100, cả hai cụm | FCFS | 8.276.432,26 → 8.276.432,26 | 0,0000% | 773,6312 → 681,0700 | 92,5612 |
| 500, chỉ cụm 2 | LLF | 16.266.140,79 → 16.187.779,72 | 0,4817% | 350,0000 → 350,0000 | 0,0000 |
| 500, chỉ cụm 2 | FCFS | 14.751.488,70 → 16.187.779,72 | -9,7366% | 350,0000 → 350,0000 | 0,0000 |

Chi phí và đỉnh lấy từ [benchmark_real.json](ai_engine/benchmark_real.json). Mức giảm là `(baseline − MILP) / baseline × 100%` cho chi phí và `đỉnh baseline − đỉnh MILP` cho công suất.

Ở mốc 100, MILP, LLF và FCFS đều đạt 94% đúng hạn. Ở mốc 500, so với FCFS tại cụm 2, MILP giảm điện thiếu **604,6444 kWh** và tăng chi phí tổng **1.436.291,03 đ**.

Đây là kết quả **mô phỏng các yêu cầu sạc sinh từ catalog trạm và mẫu xe khảo sát dùng cho kịch bản Đà Nẵng**. Giảm đỉnh và dời giờ sạc có thể giảm áp lực lên lưới và tạo dư địa phối hợp với nguồn tái tạo. Chưa có dữ liệu phát điện theo giờ hoặc hệ số phát thải xác minh cho kịch bản, nên chưa quy đổi sang CO₂ hay lượng năng lượng tái tạo sử dụng.

## Kiểm thử tự động

Kết quả chạy ngày 20/11/2026 trên Windows với mã nguồn bản demo local.

| Thành phần | Lệnh tại thư mục gốc | Kết quả |
|---|---|---:|
| AI Engine | `python -m pytest ai_engine/tests -q` | 193 đạt |
| Backend | `python -m pytest backend/tests -q` | 57 đạt |
| Flutter | `flutter test` | 59 đạt |

Cài dependency theo [requirements AI Engine](ai_engine/requirements.txt) và [requirements backend](backend/requirements.txt) trong hai môi trường Python riêng, cùng với `pytest`. Với Flutter, chạy `flutter pub get` trước khi kiểm tra. `dart format --output=none --set-exit-if-changed lib test` kiểm tra 39 file, không đổi file. `flutter analyze` báo `No issues found!`.

## Giới hạn đã biết và nguồn dữ liệu

- Catalog có **19 mẫu xe và 107/107 trạm có tọa độ tham khảo**. Dữ liệu demo giữ **15 trạm `ACTIVE`** và **92 trạm `PENDING` có `verified=False`**. Xem [catalog trạm](data/charging_station_cleaned.csv). Công suất, phân cụm, giờ hoạt động và các trường suy ra được ghi trong ghi chú dữ liệu. `rating` để trống.
- Tọa độ tham khảo chưa được xác minh thực địa. Cột `qa_notes` trong Excel vẫn giữ ghi chú cũ về tọa độ thiếu và có thể khác dữ liệu hiện tại.
- Cửa sổ tối ưu dài **24 giờ**, gồm 96 slot 15 phút tính từ mốc 15 phút ngay trước hoặc bằng thời điểm lập snapshot. Toàn bộ khung sạc phải nằm trong cửa sổ này. Lịch vượt mốc kết thúc nhận HTTP 422 trước bước ghi yêu cầu.
- Cụm demo **1–4** dùng giả định hạ áp `UP_TO_1KV`. Giá trước VAT từ 01/11/2026 là **1.620 / 2.700 / 4.212 đ/kWh** theo thứ tự thấp điểm, bình thường và cao điểm. Theo giờ Việt Nam, thấp điểm là 00:00–06:00 mỗi ngày. `MON_SAT` (thứ Hai đến thứ Bảy) có cao điểm từ 17:30 đến 22:30, các giờ còn lại là bình thường. `SUNDAY` (Chủ nhật) dùng giá bình thường từ 06:00 đến 24:00. Backend dùng `WEEKDAY` hoặc `WEEKEND` khi thiếu biểu giá EVN có hiệu lực cho ngày cần tính. Cấp điện áp và hợp đồng tại điểm đo cần được xác minh trước khi áp dụng ngoài demo. [Biểu giá đã nạp](data/tariff_window_cleaned.csv) · [Khung giờ của EVN](https://evn.com.vn/d/vi-VN/news/Ap-dung-bieu-gia-ban-le-dien-rieng-cho-sac-xe-dien-60-3557-510231)
- AI Engine mặc định dùng `HOURLY_MEAN` cho cụm có dưới 336 giờ quan sát (14 ngày) hoặc chưa có mô hình đã huấn luyện phù hợp.
- Một số màn USER, HOST và ADMIN vẫn hiển thị dữ liệu mô phỏng. Các KPI benchmark lấy từ báo cáo JSON của AI Engine.

## Ảnh chụp màn hình

| Màn hình | Ảnh |
|---|---|
| Đăng nhập | Chờ bổ sung |
| Bản đồ trạm sạc | Chờ bổ sung |
| Đặt lịch bằng AI | Chờ bổ sung |
| Admin Benchmark | Chờ bổ sung |

**Video demo** — TODO(demo) thêm URL video sau khi quay.

## Checklist nộp Smart Campus 2026

- [x] Có báo cáo benchmark tái lập, ghi rõ thuật toán thực chạy, fallback và phạm vi so sánh.
- [x] Ghi số lượng test đã chạy và cách chạy demo cục bộ.
- [ ] Đối chiếu biểu mẫu, hạn nộp và trường bắt buộc trên cổng ISSCEI.
- [ ] Chuẩn bị slide, ảnh màn hình và video demo dự phòng.
- [ ] Đối chiếu tọa độ tham khảo ngoài thực địa.

## Tài liệu và quy trình

- [CLAUDE.md](CLAUDE.md) mô tả nghiệp vụ và phạm vi hệ thống.
- [AGENTS.md](AGENTS.md) và [git.md](git.md) mô tả cấu trúc repo và quy ước Git.
- [README của AI Engine](ai_engine/README.md) có hướng dẫn chạy riêng và phân tích benchmark theo cụm.
- [Workflow kiểm tra PR](.github/workflows/pr-check.yml) mô tả các bước kiểm tra tự động.
