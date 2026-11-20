# EV ShareGrid

EV ShareGrid là nguyên mẫu điều phối sạc xe điện tại Đà Nẵng cho Smart Campus 2026 – ISSCEI. Hệ thống xếp lịch sạc theo cửa sổ đỗ xe, công suất cổng, trần công suất cụm và biểu giá.

Trong chủ đề WEFE, dự án tập trung vào năng lượng và giao thông thông minh. Việc điều phối giờ sạc giúp đánh giá khả năng giảm đỉnh tải và tận dụng khung giờ giá thấp hơn trên hạ tầng hiện có.

## Trạng thái tích hợp

| Thành phần | Trạng thái hiện tại |
|---|---|
| Flutter | Đăng nhập, tải xe và trạm, đặt lịch, xem lịch, xác nhận và hủy lịch qua API. Các màn như bản đồ, lịch sử phiên sạc, quản lý cổng của HOST và dự báo của ADMIN vẫn có dữ liệu mô phỏng. |
| Admin Benchmark | Màn ADMIN đọc `GET /api/v1/admin/benchmark`. Trong Compose, backend đọc [báo cáo benchmark](ai_engine/benchmark_real.json) được mount chỉ đọc. |
| Backend FastAPI | JWT và phân quyền USER/HOST/ADMIN. CORS cho `https://ev-sharegrid.web.app` và `http://localhost` với cổng tùy chọn. `POST /api/v1/requests` trả HTTP 422 nếu khung sạc vượt cửa sổ tối ưu 24 giờ và HTTP 409 nếu trùng `idempotency_key`. |
| AI Engine FastAPI | Backend gửi snapshot qua `/ai/optimize`. Solver dùng OR-Tools SCIP cho `MILP_MPC`, GLOP cho `LP_MPC` và LLF khi cần fallback. Bài kiểm chuẩn Trang 20 trả `MILP_MPC / OPTIMAL`, chi phí 5.500 đ, thiếu điện 0 kWh. |
| PostgreSQL/PostGIS | [Schema 19 bảng](database/schema_19_tables.sql). Backend lưu yêu cầu, lần tối ưu và lịch theo slot 15 phút, rồi trả lịch cho Flutter. |

Trong hai lần đặt lịch đã kiểm tra qua backend local, solver trả `MILP_MPC / OPTIMAL` với `solve_ms` lần lượt là 177 ms và 616 ms. Bản mẫu Trang 20 gọi trực tiếp qua `/ai/optimize` trả `MILP_MPC / OPTIMAL`, 5.500 đ, thiếu điện 0 kWh và `solve_ms` khoảng 104,9 ms. Đây là thời gian của các lần chạy đã ghi nhận.

```mermaid
flowchart LR
    U["Flutter Web / Mobile"] -->|"JWT, REST"| B["Backend FastAPI · 8000"]
    B -->|"POST /ai/optimize · snapshot cụm"| A["AI Engine FastAPI · 8001"]
    A -->|"Lịch, KPI, trạng thái solver"| B
    B <-->|"Yêu cầu, lịch 15 phút, phân quyền"| D[("PostgreSQL / PostGIS · 19 bảng")]
    R["benchmark_real.json"] -->|"Mount chỉ đọc"| B
```

## Chạy nhanh bằng Docker Compose

Cài Docker Engine với Docker Compose plugin và mở terminal ở thư mục gốc của repo. Tạo `.env` từ [file mẫu](.env.example).

```powershell
Copy-Item .env.example .env
```

Trên macOS/Linux, dùng `cp .env.example .env`.

| Biến bắt buộc | Cách cấu hình |
|---|---|
| `POSTGRES_PASSWORD` | Thay chuỗi mẫu bằng mật khẩu riêng cho PostgreSQL local. |
| `JWT_SECRET` | Sinh khóa riêng bằng `python -c "import secrets; print(secrets.token_urlsafe(48))"` và dán giá trị vào `.env`. Backend yêu cầu tối thiểu 32 byte. |
| `AUTH_PASSWORD_HASHES_JSON` | Điền một JSON object ánh xạ email sang hash mật khẩu. Đặt JSON trong dấu nháy đơn ở `.env` để giữ nguyên ký tự `$` của hash. |

Script nạp catalog tạo các tài khoản sau. Mật khẩu do người chạy chọn khi tạo hash.

| Vai trò | Email demo |
|---|---|
| USER | `user1@sharegrid.vn` |
| HOST | `host1@sharegrid.vn` |
| ADMIN | `admin@sharegrid.vn` |

Nếu Python local chưa có thư viện backend, cài bằng `python -m pip install -r backend/requirements.txt`. Lệnh sau hỏi mật khẩu cho ba tài khoản và in ra dòng `AUTH_PASSWORD_HASHES_JSON=...` để dán vào `.env`.

```sh
python -c "import getpass,json; from backend.auth import hash_password; emails=('user1@sharegrid.vn','host1@sharegrid.vn','admin@sharegrid.vn'); hashes={e:hash_password(getpass.getpass(e+' password: ')) for e in emails}; print('AUTH_PASSWORD_HASHES_JSON='+chr(39)+json.dumps(hashes)+chr(39))"
```

```sh
docker compose up --build -d
docker compose ps -a
curl -fsS http://localhost:8001/health
curl -fsS http://localhost:8000/
```

Trong Windows PowerShell có thể gọi `curl.exe`. Khi sẵn sàng, PostgreSQL, AI Engine và backend chạy, còn `catalog-seed` thoát mã 0 sau khi nạp catalog. AI Engine có tài liệu API tại [localhost:8001/docs](http://localhost:8001/docs) và backend tại [localhost:8000/docs](http://localhost:8000/docs). Đăng nhập qua Flutter hoặc `POST /api/v1/auth/login` bằng email seed và mật khẩu đã chọn. File `.env` được Git ignore. Dùng `docker compose down` để dừng.

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
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
```

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

Một [lần đo thông lượng riêng](data/scenario_10000_llf_measurement.json) với giá cố định 2.000 đ/kWh ghi nhận LLF chạy **823,9 ms**, đỉnh **850 kW** và **0 vi phạm** ở mốc 10.000 yêu cầu. Bảng trên dùng lần đo ngày 20/11/2026.

Chạy lệnh dưới đây từ thư mục gốc để tái đo với cùng dữ liệu. Thời gian giải và nghiệm khả thi khi hết ngân sách có thể thay đổi theo máy.

```sh
python -m ai_engine.scripts.benchmark_real --dataset-ref 14cec6f
```

## Liên hệ chủ đề WEFE (Smart Campus 2026)

Trong trụ cột **Năng lượng xanh và Giao thông thông minh**, lịch sạc là một phụ tải có thể điều phối. Bảng dùng TOU EVN hạ áp và chỉ so sánh các cụm thực sự chạy `MILP_MPC`. `FCFS` là baseline phục vụ theo thứ tự đến (FIFO).

| Phạm vi | Baseline | Chi phí baseline → MILP (đ) | Giảm chi phí | Đỉnh baseline → MILP (kW) | Giảm đỉnh (kW) | Điện thấp điểm baseline → MILP (kWh) | Chênh thấp điểm (kWh) |
|---|---|---:|---:|---:|---:|---:|---:|
| 100, cả hai cụm | LLF | 8.276.432,26 → 8.276.432,26 | 0,0000% | 684,0876 → 681,0700 | 3,0176 | 0,0000 → 0,0000 | 0,0000 |
| 100, cả hai cụm | FCFS | 8.276.432,26 → 8.276.432,26 | 0,0000% | 773,6312 → 681,0700 | 92,5612 | 0,0000 → 0,0000 | 0,0000 |
| 500, chỉ cụm 2 | LLF | 16.266.140,79 → 16.187.779,72 | 0,4817% | 350,0000 → 350,0000 | 0,0000 | 480,6857 → 517,0828 | +36,3971 |
| 500, chỉ cụm 2 | FCFS | 14.751.488,70 → 16.187.779,72 | -9,7366% | 350,0000 → 350,0000 | 0,0000 | 369,1739 → 517,0828 | +147,9089 |

Chi phí và đỉnh lấy từ [benchmark_real.json](ai_engine/benchmark_real.json). Mức giảm là `(baseline − MILP) / baseline × 100%` cho chi phí và `đỉnh baseline − đỉnh MILP` cho công suất. Điện thấp điểm lấy từ lịch cùng lượt chạy, cộng `power_kw × 0,25 giờ` cho các slot 00:00–06:00 theo giờ Việt Nam.

Ở mốc 100, MILP, LLF và FCFS đều đạt 94% đúng hạn và có 0 kWh sạc trong khung thấp điểm mới. Ở mốc 500, cụm 2 cấp nhiều điện hơn khi dùng MILP. So với FCFS, MILP giảm điện thiếu **604,6444 kWh** và tăng chi phí tổng **1.436.291,03 đ**. Chênh điện thấp điểm ở cụm này gồm cả điện cấp thêm.

Đây là kết quả **mô phỏng các yêu cầu sạc sinh từ catalog trạm và mẫu xe khảo sát dùng cho kịch bản Đà Nẵng**. Giảm đỉnh và dời giờ sạc có thể giảm áp lực lên lưới và tạo dư địa phối hợp với nguồn tái tạo. Chưa có dữ liệu phát điện theo giờ hoặc hệ số phát thải xác minh cho kịch bản, nên chưa quy đổi sang CO₂ hay lượng năng lượng tái tạo sử dụng.

## Kiểm thử tự động

Kết quả chạy ngày 20/11/2026 trên Windows từ bản code `15c600b`.

| Thành phần | Lệnh tại thư mục gốc | Kết quả |
|---|---|---:|
| AI Engine | `python -m pytest ai_engine/tests -q` | 190 passed |
| Backend | `python -m pytest backend/tests -q` | 52 passed |
| Flutter | `flutter test` | 57 passed |

Cài dependency theo [requirements AI Engine](ai_engine/requirements.txt) và [requirements backend](backend/requirements.txt) trong hai môi trường Python riêng, cùng với `pytest`. Với Flutter, chạy `flutter pub get` trước khi kiểm tra. `dart format --output=none --set-exit-if-changed lib test` kiểm tra 39 file, không đổi file. `flutter analyze` báo `No issues found!`.

## Giới hạn đã biết và nguồn dữ liệu

- Catalog có **19 mẫu xe và 107 trạm**, trong đó **92 trạm thiếu tọa độ** ở trạng thái `PENDING` và 15 trạm `ACTIVE`. Danh sách cần xác minh nằm trong [stations_missing_coordinates.csv](data/stations_missing_coordinates.csv). Công suất, phân cụm, giờ hoạt động và các trường suy ra được ghi trong ghi chú dữ liệu. `rating` để trống.
- Cửa sổ tối ưu dài **24 giờ**, gồm 96 slot 15 phút tính từ mốc 15 phút ngay trước hoặc bằng thời điểm lập snapshot. Toàn bộ khung sạc phải nằm trong cửa sổ này. Lịch vượt mốc kết thúc nhận HTTP 422 trước bước ghi yêu cầu.
- Cụm demo **1–4** dùng giả định hạ áp `UP_TO_1KV`. Giá trước VAT từ 01/11/2026 là **1.620 / 2.700 / 4.212 đ/kWh** theo thứ tự thấp điểm, bình thường và cao điểm. Cấp điện áp và hợp đồng tại điểm đo cần được xác minh trước khi áp dụng ngoài demo. [Biểu giá và khung giờ của EVN](https://evn.com.vn/d/vi-VN/news/Ap-dung-bieu-gia-ban-le-dien-rieng-cho-sac-xe-dien-60-3557-510231)
- [ev-sharegrid.web.app](https://ev-sharegrid.web.app) là bản xem trước Flutter trên Firebase Hosting. Workflow hiện build web với `API_BASE` mặc định `http://localhost:8000` và chưa cấu hình URL backend công khai. Chạy Flutter cùng Compose cục bộ để demo luồng API.
- AI Engine mặc định dùng `HOURLY_MEAN` cho cụm có dưới 336 giờ quan sát (14 ngày) hoặc chưa có mô hình đã huấn luyện phù hợp.
- Một số màn USER, HOST và ADMIN vẫn hiển thị dữ liệu mô phỏng. Các KPI benchmark lấy từ báo cáo JSON của AI Engine.

## Ảnh chụp màn hình

| Màn hình | Ảnh |
|---|---|
| Đăng nhập | `docs/screenshots/01-login.png` (chờ bổ sung) |
| Bản đồ trạm sạc | `docs/screenshots/02-map.png` (chờ bổ sung) |
| Đặt lịch bằng AI | `docs/screenshots/03-booking-ai.png` (chờ bổ sung) |
| Admin Benchmark | `docs/screenshots/04-admin-benchmark.png` (chờ bổ sung) |

**Video demo** — TODO(demo) thêm URL video sau khi quay.

## Checklist nộp Smart Campus 2026

- [x] Có báo cáo benchmark tái lập, ghi rõ thuật toán thực chạy, fallback và phạm vi so sánh.
- [x] Ghi số lượng test đã chạy và cách chạy demo cục bộ.
- [ ] Đối chiếu biểu mẫu, hạn nộp và trường bắt buộc trên cổng ISSCEI.
- [ ] Chuẩn bị slide, ảnh màn hình và video demo dự phòng.
- [ ] Xác minh tọa độ 92 trạm và cập nhật nguồn biểu giá nếu có số, ngày văn bản EVN đã đối chiếu.
- [ ] Xác nhận backend HTTPS công khai và cấu hình `API_BASE` nếu demo qua Firebase Hosting.

## Tài liệu và quy trình

- [CLAUDE.md](CLAUDE.md) mô tả nghiệp vụ và phạm vi hệ thống.
- [AGENTS.md](AGENTS.md) và [git.md](git.md) mô tả cấu trúc repo và quy ước Git.
- [README của AI Engine](ai_engine/README.md) có hướng dẫn chạy riêng và phân tích benchmark theo cụm.
- [Workflow kiểm tra PR](.github/workflows/pr-check.yml) và [workflow Firebase Hosting](.github/workflows/deploy-hosting.yml) mô tả quy trình kiểm tra và triển khai web.
