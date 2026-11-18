# CLAUDE.md – EV ShareGrid

> Nguồn sự thật (ưu tiên cao nhất, cập nhật 18/11/2026):
> 1. `EV_ShareGrid_Bao_cao_tong_the_10k.pdf` – Báo cáo phân tích & thiết kế "Điều phối sạc và tối ưu lịch – mở rộng 10.000 người dùng đồng thời" (v1.0, 17/11/2026, 30 trang).
> 2. `huong_dan.md` – Hướng dẫn triển khai toàn diện (Data, Web/App, Backend, AI Engine).
>
> Mọi tài liệu cũ hơn (kế hoạch ban đầu `.docx`, `EV_ShareGrid_Mo_ta_du_an.pdf`, `EV_ShareGrid_Dac_ta_AI.pdf`) **bị thay thế** ở những điểm mâu thuẫn. Đặc biệt các nội dung cũ về **điện mặt trời, tải thiết yếu (bơm nước), chế độ thời tiết, WEFE-solar** KHÔNG còn thuộc phạm vi.

---

## 1. Dự án là gì

EV ShareGrid là nền tảng **điều phối sạc xe điện và tối ưu lịch sạc** cho các trạm sạc (công cộng và trạm chia sẻ của chủ trạm). Người dùng đặt lịch (xe, trạm, giờ đến/đi, % pin), **bộ lập lịch AI** xếp **cổng – khung 15 phút – công suất** cho toàn bộ yêu cầu đang hoạt động trong cùng cụm, dưới **trần công suất cố định** của trạm và cụm, rồi trả lịch + chi phí + phần thiếu + lời giải thích.

- Bối cảnh: cuộc thi Smart Campus 2026 (ISSCEI, Đà Nẵng), lĩnh vực b) Năng lượng xanh & Giao thông thông minh. Thành phố trọng điểm: **Đà Nẵng**, có thể mở rộng toàn quốc.
- Mục tiêu thiết kế tải: **10.000 người dùng đồng thời**; dữ liệu thử: **100.000 tài khoản** giả lập.
- Slot lập lịch: **15 phút** (Δt = 0,25 h). CSDL: **PostgreSQL + PostGIS**. Lõi: **LP/MILP + MPC**, fallback **LLF**.

## 2. Phạm vi – ĐƯỢC và KHÔNG

**Trong phạm vi**
- Ràng buộc công suất chỉ gồm 2 trần cố định: `station_power_kw` (trạm) và `grid_limit_kw` (cụm).
- Biểu giá điện theo khung giờ (TOU EVN) để dời sạc sang giờ rẻ.
- Request mới và request cũ còn hoạt động được tối ưu **chung một pool** theo cụm + horizon.
- Mô phỏng phiên sạc (simulator) để demo/đánh giá.
- Model phụ: **dự báo số lượt request theo giờ**.

**Ngoài phạm vi (không được đưa vào input/UI như dữ liệu thật)**
- Điện mặt trời (`solar_kw`), tải thiết yếu (`critical_load_kw`), tải toàn khu theo giờ, thời tiết, profile tải lưới biến thiên.
- Dự báo kW/phụ tải; forecast KHÔNG tự cộng vào công suất solver.
- Mua bán điện giữa hộ, đấu nối lưới, phần cứng IoT. Phát lệnh trạm thật chỉ khi có OCPP adapter + credential + kiểm thử.
- Ưu tiên theo tuổi tài khoản (user cũ/mới bình đẳng).

## 3. Kiến trúc & luồng tổng quan

```
App/Web (USER, HOST, ADMIN)
   │ HTTP REST (JSON) + SSE/WebSocket hoặc polling có backoff
   ▼
Backend API (stateless, scale ngang, auth JWT/Google, phân quyền, validate, transaction)
   │ POST /requests → lưu request + outbox_event cùng 1 transaction → trả 202 {request_id, job_id}
   ▼
PostgreSQL + PostGIS (19 bảng) ── outbox relay ──► Broker (Kafka, key = cluster_id)
                                                     ▼
                                     optimization_job (coalesce theo cụm, lease/fencing)
                                                     ▼
                         AI Engine / Optimizer Worker (Python, FastAPI/worker)
                         snapshot → LLF warm-start → (Master LP + Station workers) → Validator
                                                     ▼
Backend commit (transaction ngắn, advisory lock theo cụm, kiểm tra input_version) → schedule version mới
                                                     ▼
                                Notification worker → App/Web
```

- App/Web **không** chạy AI, **không** nối thẳng DB, **không** nói chuyện trực tiếp với nhau; mọi thứ qua Backend.
- AI chỉ **đề xuất** lịch; Backend chịu trách nhiệm quyền, kiểm tra cuối, giao dịch, phản hồi.
- Không giữ transaction/lock DB trong lúc solver chạy. Kết quả stale (có event mới hơn) bị loại khi commit.

### Endpoint
| Endpoint | Ai gọi | Mục đích |
|---|---|---|
| `POST /requests` (idempotency_key) | App | Tạo yêu cầu sạc → 202 + request_id/job_id |
| `GET /stations?lat&lng&connector_type…` | App | Tìm trạm ACTIVE + verified, số cổng trống, giá hiện tại |
| `POST /ai/optimize` | Backend → AI | Input Snapshot JSON → Output Schedule JSON |
| `POST /ai/benchmark` | Backend → AI | Chạy các thuật toán trên cùng scenario/seed |
| `POST /ai/forecast` | Backend → AI | Dự báo `pred_arrivals` 24 h tới |

## 4. Vai trò & chức năng

Phân quyền: **USER** chỉ quản lý xe/request của mình · **HOST** chỉ sửa trạm của mình (`owner_id = user_id`), không viết lịch cho xe, không tự duyệt PENDING→ACTIVE · **ADMIN** quản lý cụm, biểu giá, duyệt trạm, xem toàn hệ thống; không trực tiếp viết lịch.

### 4.1 USER (App/Web) – 7 chức năng
1. **Đăng ký / Đăng nhập** – Email/SĐT hoặc Google. Trả `user_id`, `role`.
2. **Garage – Hồ sơ xe** – Danh sách xe; thêm xe: chọn hãng + mẫu từ `vehicle_model` (tự lấy `connector_type`, `battery_kwh`, `max_kw`), biển số, tên gợi nhớ, `default_soc_target`, xe mặc định. **Không cho tự nhập thông số hãng.**
3. **Bản đồ & tìm trạm** – Lọc theo loại xe (CAR/MOTORBIKE), đầu nối (CCS2/Type2/CHAdeMO/AC_HOME), giờ mở cửa, khoảng cách; hiện số cổng trống và giá khung hiện tại.
4. **Chi tiết trạm** – Tên, địa chỉ, giờ mở/đóng, `service_fee_vnd`, danh sách cổng (`port_code`, đầu nối, kW, ACTIVE/MAINTENANCE), biểu đồ giá điện theo khung giờ trong ngày.
5. **Form đặt lịch** – Chọn xe, `arrival_time`, `departure_time`, `soc_now`, `soc_target` → "Gửi yêu cầu & Xếp lịch". Backend kiểm tra 4 điều kiện: (a) đầu nối/loại xe khớp trạm (sai → báo + gợi ý trạm khác); (b) `soc_now < soc_target ≤ 100`, `departure > arrival`, trong giờ mở cửa & `max_session_minutes`; (c) xe không có request trùng giờ; (d) tính `energy_needed_kwh`, đẩy vào hàng đợi cụm.
6. **Kết quả lịch & giải thích** – Trạng thái giải (OPTIMAL/FEASIBLE/FALLBACK…), **cổng được gán**, **Gantt 15 phút** (kW mỗi slot), `expected_soc`, `shortfall_kwh`, `estimated_cost_vnd`, hộp `explanation`; nút **Xác nhận lịch / Sửa / Hủy**.
7. **Theo dõi phiên sạc & Thông báo** – % pin, kWh đã nạp, thời gian còn lại; nút demo **Check-in**, **Đến trễ 15 phút**, **Rời sớm/Dừng sạc**; danh sách thông báo khi lịch đổi `version`.

**Người dùng lần đầu**: đăng ký → bắt buộc thêm ≥1 xe → tìm trạm tương thích → nhập giờ/SOC → request vào pool chung → nhận lịch.
**Người dùng quay lại**: đăng nhập → tải xe mặc định, trạm yêu thích, request đang mở → kiểm tra trùng giờ cùng xe → tạo mới hoặc sửa/hủy tương lai → giải lại pool (kể cả request người khác) → so version, báo người bị ảnh hưởng.

### 4.2 HOST (Web Portal) – 4 chức năng
1. **Đăng ký & cấu hình trạm**: tên, địa chỉ, vị trí bản đồ (lat/lng), giờ mở/đóng, loại xe, `station_power_kw`, `service_fee_vnd` (giá ghi đè nếu được phép) → trạng thái **PENDING** chờ ADMIN.
2. **Quản lý cổng**: `port_code` (P1, P2…), `connector_type`, `control_type` (CONTINUOUS / ON_OFF_SWITCH), `min_power_kw`, `max_power_kw`.
3. **Báo hỏng / bảo trì**: chuyển cổng/trạm sang MAINTENANCE/OFFLINE + thời gian dự kiến → Backend phát `RE_OPTIMIZE` → giữ slot đã chạy, chuyển lịch tương lai sang cổng khác tương thích; nếu hết cổng → tính shortfall + thông báo khẩn.
4. **Lịch đặt chỗ & doanh thu**: biểu đồ sử dụng cổng theo slot 15 phút, tổng kWh, phí dịch vụ.

### 4.3 ADMIN (Dashboard) – 6 chức năng
1. **Cụm điều phối** (`grid_cluster`): tạo/sửa cụm, ranh giới (`boundary`/`h3_index`), **trần cố định `grid_limit_kw`** (không phải tải lưới theo thời điểm).
2. **Kiểm duyệt trạm & quy ước dữ liệu**: rà trạm HOST/OSM, nhãn `REAL/SURVEY/SIMULATED`, kiểm tra công suất (không nhầm tổng danh định cổng với trần trạm), đặt `verified = TRUE`, `status = ACTIVE`, hoặc từ chối/khóa.
3. **Biểu giá** (`tariff_window`): theo cụm/loại ngày/khung; tự kiểm tra **không chồng, không hở** 24 h; ngày hiệu lực.
4. **Giám sát vận hành & hàng đợi**: `optimization_run` và `optimization_job` – `solve_ms`, status, n_requests theo cụm, queue depth, fallback.
5. **Mô phỏng & Benchmark Lab**: chọn scenario (100…10.000 active requests, profile Balanced/Hot-spot), chọn thuật toán, chạy, so KPI.
6. **Audit log & Dự báo nhu cầu**: lịch sử thay đổi (ai, khi nào, cũ→mới); biểu đồ `demand_forecast` có nhãn cấu hình / dự báo / mô phỏng.

## 5. Trạng thái request & quy tắc khóa lịch

| Status | Khi tối ưu lại |
|---|---|
| PENDING | Vào pool nếu còn trong cửa sổ và hợp lệ |
| SCHEDULED / CONFIRMED | Vào pool; slot tương lai chưa cam kết có thể xếp lại → tăng version + thông báo |
| CHARGING | Giữ kWh đã nạp + slot hiện tại/lệnh đang chạy; chỉ xếp phần còn lại |
| DONE | Đóng, giữ lịch sử, không vào run mới |
| CANCELLED / FAILED | Không xếp; lịch tương lai `is_active=false`, giải phóng tài nguyên |
| NO_SHOW / hết departure | Đánh dấu theo grace period, giải phóng slot, thông báo |

- **Khóa**: slot đã qua, slot hiện tại đang cấp điện, lệnh đã gửi & cổng xác nhận.
- Nếu sản phẩm hứa cứng khung giờ sau CONFIRMED → đặt `commit_until`, coi là ràng buộc cứng; không âm thầm đổi.
- Hai request cùng xe giao nhau → từ chối hoặc yêu cầu sửa/hủy cái cũ.
- Tối ưu lại **không xóa lịch sử**: lịch cũ inactive để truy vết; chỉ version hiện hành được phát lệnh.

## 6. AI Engine

### 6.1 Hai khối
- **Model chính – Bộ lập lịch tối ưu có ràng buộc**: MILP (hoặc CP-SAT) + **MPC** (rolling horizon, mỗi 15 phút hoặc khi có event); **LP** là biến thể nhanh khi cổng cố định & điều khiển liên tục; **LLF** tạo nghiệm ban đầu và làm fallback; **Validator** độc lập.
- **Model phụ – Dự báo nhu cầu**: Hourly Mean baseline → Random Forest / XGBoost; output `pred_arrivals` (số lượt/giờ). Đánh giá MAE/RMSE, time-series split. Không điều khiển công suất.

AI **không**: xác thực user, thu tiền, duyệt HOST, sửa DB tùy ý, dự báo solar/tải, đảm bảo mọi xe đủ pin khi thiếu công suất, phát lệnh trạm thật khi chưa có adapter. Không phải LLM; explanation sinh từ lý do thực tế.

### 6.2 Mô hình toán (slot Δt = 0,25 h)
Biến: `x(i,j,t) ∈ {0,1}` (request i dùng cổng j ở slot t); `p(i,j,t) ≥ 0` (kW); `shortfall_i ≥ 0` (kWh).

Ràng buộc cứng:
1. `E_remaining,i = max(0, E_needed,i − E_delivered,i)`; `Σ_j Σ_t p·Δt + shortfall_i = E_remaining,i`.
2. Mỗi cổng/slot ≤ 1 xe; mỗi xe/slot ≤ 1 cổng (prototype: giữ 1 cổng suốt phiên).
3. `x = p = 0` nếu sai trạm, sai đầu nối, cổng MAINTENANCE/OFFLINE, ngoài `[arrival, departure)` hoặc ngoài giờ mở cửa.
4. CONTINUOUS: `P_min,j·x ≤ p ≤ min(P_max,j, P_vehicle,i)·x`. ON_OFF_SWITCH: `p = P_on,j·x` (số slot bật tối thiểu `ceil(E_remaining/(P_on·Δt))`).
5. `Σ p` theo trạm ≤ `station_power_kw`; `Σ p` theo cụm ≤ `grid_limit_kw` – **mọi slot**.

Mục tiêu **lexicographic** (không cộng thẳng kWh với VND):
1. Không vi phạm ràng buộc cứng.
2. Min `Σ w_i·shortfall_i` (theo bậc priority).
3. Công bằng (max-min fulfillment) trong nhóm tương đương.
4. Min chi phí `Σ price_t·p·Δt` (phí dịch vụ cộng ở bước hóa đơn).
5. Giảm đỉnh công suất, số lần bật/tắt, thay đổi slot đã thông báo.
Nếu dùng weighted sum: chuẩn hóa từng mục tiêu, ghi hệ số/tolerance vào `weights_json`.

Slack/laxity: `Slack_i = (departure_i − t_now) − E_remaining,i / P_feasible,max,i`. Tie-break: priority → slack → deadline → `arrival_time` → `request_id` (ổn định, không dựa tuổi tài khoản).

### 6.3 Quy trình một run (10 bước)
1. Chốt snapshot & coalesce event theo `cluster_id`, gán `input_version`.
2. Lọc + đóng băng (MPC freeze), tính `E_remaining`.
3. Sinh candidate hợp lệ (pruning, không tạo tích Descartes).
4. LLF warm-start theo bậc priority → có nghiệm FEASIBLE sớm.
5. **Master LP** chia ngân sách `b(s,t)`: `Σ_s b ≤ grid_limit_kw`, `b ≤ station cap`.
6. **Station workers** song song: LP/min-cost flow (liên tục) hoặc CP-SAT/MILP (bật/tắt, chọn cổng).
7. Coordinator cân bằng ngân sách bằng **giá nghẽn** trong số vòng/time budget; không nới trần.
8. Gán về từng request (priority, slack, deadline, arrival, request_id).
9. **Validator** kiểm tra lại mọi slot/cổng/connector/deadline/kWh/station cap/cluster cap; lỗi → sửa cục bộ hoặc LLF.
10. Commit (kiểm tra `input_version`/fencing token) trong transaction ngắn + thông báo.

### 6.4 Trạng thái solver
`OPTIMAL` (tối ưu trong model/tolerance) · `FEASIBLE` (hợp lệ, chưa chứng minh tối ưu) · `FALLBACK` (LLF, ghi algorithm=LLF) · `INFEASIBLE` (trả lý do cứng hoặc dùng shortfall) · `ERROR` (không phát lệnh). **Không bao giờ nới trần** để ép có lịch.

### 6.5 Sự kiện MPC
Request mới · hủy/đổi giờ/SOC · đến muộn/về sớm · cổng/trạm offline · chu kỳ 15 phút → đóng băng phần đã chạy, cập nhật remaining, giải lại phần tương lai, version mới, thông báo.

### 6.6 Thuật toán benchmark (cùng scenario, seed, giá, giới hạn)
| Thuật toán | Vai trò |
|---|---|
| **MILP_MPC** (CP-SAT_MPC) | Phương pháp đề xuất chính |
| **LP_MPC** | Biến thể nhanh cho cổng liên tục |
| **LLF** | Fallback + warm-start |
| **FCFS** | Baseline: đến trước sạc trước |
| **EDF** | Baseline: deadline sớm nhất trước |
| **EQUAL_SHARE** | Baseline: chia đều công suất |
| **ASAP** | Mốc "không điều phối" (có thể vi phạm cap; chỉ để đối chiếu) |
| **NSGA_II** | Phụ: biên Pareto (shortfall, cost, peak) cho kịch bản nhỏ |

KPI: tổng shortfall, on-time rate, tổng chi phí, peak power, cap violations, fairness, fallback count, `solve_ms` (tách với API latency).

### 6.7 Output & giải thích
- `schedule[]`: request_id, port_id, slot_start, power_kw, version, is_active.
- `request_result`: allocated_kwh, shortfall_kwh, expected_soc, estimated_cost_vnd, explanation.
- Run status, algorithm, solve_ms; KPI; version/change (slot nào đổi, vì sao, thông báo đã gửi).
- Explanation phải trỏ tới dữ liệu cụ thể (deadline, giá, cổng, cap, priority, fallback). **Không viết "AI chọn vậy".** Dashboard phân biệt giá trị cấu hình / dự báo / đo được; dữ liệu giả lập phải có nhãn.

Mẫu: *"Được xếp 10:00–11:15 ở cổng P3 vì giá thấp (2.400 đ/kWh) và kịp trước giờ rời 12:00."* · *"Request 87 thiếu 0,20 kWh vì giới hạn cụm đã dùng hết trong các slot trước giờ rời."*

### 6.8 Ví dụ tính tay chuẩn (báo cáo mục 16.5)
Cụm `grid_limit_kw = 3`. S1 cap 4 kW, 2 cổng liên tục 2 kW; S2 cap 2 kW, 2 cổng ON_OFF 1 kW. A (cũ, 1,00 kWh, hạn 18:00), B (mới, 0,50, 17:45), C (cũ, 0,50, 17:30, S2), D (mới, 0,50, 18:00, S2). Giá 17:00–17:15 = 4.000; 17:15–18:00 = 2.000. Lịch: 17:00 C1 kW; 17:15 A2+C1; 17:30 B2+D1; 17:45 A2+D1 → tổng 2,50 kWh, đỉnh 3 kW, chi phí 5.500 VND, mọi deadline đạt.

## 7. Dữ liệu – 19 bảng

Quy ước: thời gian `TIMESTAMPTZ` (Asia/Ho_Chi_Minh), slot `[start,end)` căn :00/:15/:30/:45; công suất kW, năng lượng kWh, tiền VND dạng `NUMERIC` (không float); nhãn nguồn `REAL/SURVEY/SIMULATED` + `source_ref` + `verified`.

**Danh mục & tài nguyên (7)**: `grid_cluster` (cluster_id, name, province, timezone, status, h3_index, centroid_lat/lng, boundary, **grid_limit_kw**) · `vehicle_model` (brand, model_name, vehicle_type CAR/MOTORBIKE, connector_type CCS2/Type2/CHAdeMO/AC_HOME, battery_kwh, max_kw, source_type/ref) · `app_user` (role USER/HOST/ADMIN, full_name, email, phone, google_id, reliability_score, status) · `vehicle` (user_id, model_id, plate_number, nickname, default_soc_target, is_default) · `charging_station` (cluster_id, owner_id, name, address, province, supported_vehicle_type, status, lat/lng, open/close_time, is_24h, verified, **station_power_kw**, service_fee_vnd, price_override_vnd_kwh, max_session_minutes, rating, source) · `port` (station_id, port_code unique/trạm, connector_type, control_type, status ACTIVE/MAINTENANCE/OFFLINE, min/max_power_kw) · `tariff_window` (cluster_id, day_type WEEKDAY/WEEKEND/HOLIDAY, band OFF_PEAK/NORMAL/PEAK, start/end_time, price_vnd_kwh, valid_from/to).

**Vận hành (6)**: `charging_request` (… arrival/departure, soc_now/target, battery_kwh_snapshot, max_kw_snapshot, eta, energy_needed_kwh, shortfall_kwh, priority_weight, status, idempotency_key, scenario_id) · `optimization_run` (job_id, input_version, algorithm, trigger_type, status, code_version, solve_ms, seed, slot_minutes=15, n_requests, weights_json, input_json, kpi_json) · `run_request` (allocated_kwh, shortfall_kwh, expected_soc, estimated_cost_vnd, explanation) · `schedule` (run_id, request_id, port_id, slot_start, power_kw, version, is_active – partial unique index) · `charging_session` (start/end, energy_kwh, soc_start/end, cost_energy/service/total_vnd, stop_reason, status, is_simulated) · `notification` (type, title, body, channel, created/sent/read_at).

**Dự báo & thử nghiệm (4)**: `forecast_model` (HOURLY_MEAN/RANDOM_FOREST/XGBOOST, metrics_json MAE/RMSE) · `demand_forecast` (hour_start, pred_arrivals) · `simulation_scenario` (seed, **registry_users**, **active_requests**, config_json) · `benchmark_result` (scenario_id, run_id, algorithm, repeat_no, metrics_json – UNIQUE scenario/algorithm/repeat).

**Hạ tầng đồng thời (2)**: `outbox_event` (dedupe_key UNIQUE, payload_json, attempts, status) · `optimization_job` (target_version, status, events_count, attempt_count, lease_expires_at, worker_id).

Công thức: `energy_needed_kwh = (soc_target − soc_now)/100 × battery_kwh_snapshot / eta` (eta 0,90–0,92). `remaining_kwh = max(0, energy_needed_kwh − energy_kwh)`.

Biểu giá mẫu EVN (cụm 1, WEEKDAY): 00–04 OFF_PEAK 1.600 · 04–09:30 NORMAL 2.400 · 09:30–11:30 PEAK 4.000 · 11:30–17 NORMAL 2.400 · 17–20 PEAK 4.000 · 20–22 NORMAL 2.400 · 22–24 OFF_PEAK 1.600 (đ/kWh; số liệu mẫu, cần đối chiếu biểu giá chính thức).

Dữ liệu mẫu: cụm 1 "Hải Châu – Trung tâm" 500 kW, cụm 2 "Sơn Trà – Ven biển" 350 kW (Đà Nẵng); trạm 10 "ShareGrid Bạch Đằng" (22 kW, P1–P4), trạm 11 "ShareGrid Nguyễn Văn Linh" (40 kW, 24h). Mẫu xe: VF 5 Plus, VF e34, VF 8 Eco, Feliz S, BYD Atto 3, Ioniq 5.

Kiểm tra dữ liệu: `departure > arrival`, `0 ≤ soc_now < soc_target ≤ 100`, biểu giá phủ kín 24 h không chồng, công suất không âm. Nguồn: thông số hãng, ev-database.org, OSM Overpass (`amenity=charging_station`), H3 res 6–7, EVN TOU.

Kịch bản: `registry_users = 100.000` (tài khoản) tách bạch với `active_requests` = 50/100/500/1.000/2.500/5.000/10.000, profile **Balanced** và **Hot-spot** (dồn 1 cụm, 17:00–20:00). 100k user + 120k vehicle sinh bằng script (Faker/numpy seed 42), xuất CSV/parquet, nạp bằng `COPY`.

## 8. Mở rộng 10.000 người dùng

Báo cáo tách 5 mức tải: 10k tài khoản · 10k phiên đồng thời · 10k booking trong một burst · 10k active charging requests · 10k solver jobs (thường coalesce thành ít job/cụm).
- API stateless sau load balancer, cache danh mục có TTL, connection pooler, worker tách riêng (optimization, outbox, notification, benchmark), backpressure khi queue đầy.
- Idempotency key cho booking; outbox + Kafka partition theo `cluster_id`; tối đa 1 job mới nhất/cụm; lease + fencing.
- Kế hoạch test: phiên app/web (RPS, p50/p95/p99), booking burst (ACK latency, outbox lag, queue depth), tối ưu phân tán (solve wall time, coverage), cạnh tranh 1 cụm, độ bền (broker restart, worker chết), tái tối ưu khi đang solve.
- **Nghiệm thu**: 0 vi phạm trần/cổng, 0 request trùng do retry, 0 request active bị bỏ không giải thích, 0 kết quả stale được commit, 0 event mất.
- **Chưa có số đo nào chứng minh đạt 10k** – không ghi "đã đạt" khi chưa benchmark.

## 9. Ma trận 9 case kiểm chứng
New joins old · Old charging · Terminal excluded · Cross-cluster · Tie-break · Capacity conflict · Concurrent booking · Solver timeout (status FALLBACK/FEASIBLE, không OPTIMAL giả) · Schedule change (version mới, cũ inactive, có notification).

## 10. Lộ trình 4 giai đoạn
1. Schema + seed data (7 sheet danh mục; Đà Nẵng 3 cụm/15 trạm/60 cổng/10 mẫu xe), Docker PostgreSQL+PostGIS, JSON contract, Validator.
2. Baseline (FCFS, EDF, Equal Share, LLF, ASAP), LP/MILP OR-Tools, `POST /ai/optimize`; UI USER (đăng nhập, garage, bản đồ, đặt lịch, kết quả).
3. MPC (khóa slot, remaining_kwh), forecast model; UI HOST + ADMIN.
4. Master–Worker cho 10k, 9 case, benchmark lưu `benchmark_result`; outbox/job/advisory lock; dashboard benchmark.

## 11. Quyết định cần chốt trước khi code
Horizon & timeout · commit policy (khi nào không được đổi) · priority & tie-breaker · nguồn SOC/kWh (telemetry hay ước lượng + nhãn giả lập) · điều kiện chuyển cổng (khuyến nghị giữ 1 cổng) · bộ scenario benchmark bất biến.

## 12. Quy tắc khi làm việc với dự án này
- Ưu tiên báo cáo 10k + huong_dan.md; không tái đưa solar/tải thiết yếu/thời tiết vào thiết kế.
- Không bịa số hiệu năng hay cải thiện; số liệu demo phải gắn nhãn **Mô phỏng/Minh họa**, benchmark chỉ công bố khi đo thật (scenario + code_version).
- Mọi UI hiển thị lịch phải có: status solver, cổng, slot 15 phút, shortfall, chi phí, explanation, version.
- Thuật ngữ thống nhất: request, cụm (cluster), trạm (station), cổng (port), slot 15 phút, trần trạm/cụm, shortfall, version.

## 13. Tài sản thiết kế
- Canvas UI (Design artifact): https://claude.ai/artifact/NPphrAws68DHz64YvCZ3Yy – trang **Tiếng Việt** là bản chuẩn; trang **English** là bản dịch cũ (chưa đồng bộ với báo cáo 10k).
- Hệ thống thiết kế: phối màu **kết hợp** (chốt 18/11): nền trắng; Blue 600 `#3465D6` cho nút/icon/link (chữ trắng 5,3:1); Sky 200 `#C3E7F5` cho mảng nhấn lớn – thẻ nổi bật, chip, tab đang chọn – với chữ `#0B3550` (9,8:1), không đặt chữ xanh lên Sky 200; Sky 100 `#E3F4FB` cho nền nhấn nhỏ; Blue 800 `#284FB0`; Navy `#0B1B3F` (chữ, sidebar web); Red `#D8232A`; font Bricolage Grotesque (tiêu đề) + Plus Jakarta Sans (nội dung); liquid glass cho thanh tab nổi, thẻ, thanh hành động; icon "Sạc thông minh" = chip AI.
- Bản đồ: Đà Nẵng phong cách Google Maps (sông Hàn, cầu, biển Mỹ Khê).
