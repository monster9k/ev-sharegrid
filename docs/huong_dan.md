# HƯỚNG DẪN TRIỂN KHAI TOÀN DIỆN DỰ ÁN EV SHAREGRID (DATA, WEB/APP, BACKEND & AI ENGINE)

Tài liệu này hệ thống hóa toàn bộ công việc cần làm, cách thực hiện từng bước, cấu trúc bảng dữ liệu Excel/CSV/PostgreSQL, danh sách màn hình và luồng chức năng Web/App, kiến trúc kết nối hệ thống và cơ chế vận hành thuật toán AI dựa trên thiết kế **EV ShareGrid — Điều phối sạc và tối ưu lịch (Mở rộng 10.000 người dùng đồng thời)** và ghi chú yêu cầu của nhóm.

Các bảng giá giả định dưới đây minh họa thiết kế ban đầu. Biểu giá dùng trong bản demo hiện tại được ghi trong [README](../README.md#giới-hạn-đã-biết-và-nguồn-dữ-liệu).

## 1. BỨC TRANH TỔNG THỂ: HỆ THỐNG GỒM NHỮNG GÌ VÀ KẾT NỐI RA SAO?

Nhiều bạn khi mới ghép nối từ UI sang hệ thống thực tế thường thắc mắc: *"App và Web kết nối với nhau qua đâu? AI nằm ở chỗ nào trong App?"*. Câu trả lời cốt lõi là: **App/Web không chạy thuật toán AI trực tiếp và cũng không nối thẳng vào Database hay nói chuyện trực tiếp với nhau**. Mọi thứ đi qua **Backend API** và **Database trung tâm**.

### 1.1. Sơ đồ khối và luồng kết nối giữa các thành phần

1. **Tầng Giao diện (Client — App Mobile & Web Portal):**

   * **App / Web Người dùng (USER):** Tìm trạm sạc trên bản đồ, đặt lịch sạc (chọn xe, trạm, giờ đến, giờ đi, % pin hiện tại và mục tiêu), theo dõi tiến độ sạc và nhận thông báo khi lịch thay đổi.

   * **Web Chủ trạm (HOST):** Đăng ký trạm sạc, khai báo các cổng sạc (công suất, loại đầu nối, chế độ điều khiển), cập nhật trạng thái bảo trì/lỗi cổng.

   * **Web Quản trị viên (ADMIN):** Quản lý cụm lưới điện (`grid_cluster`) và trần công suất cố định (`grid_limit_kw`), duyệt trạm của HOST, cài đặt biểu giá điện theo khung giờ (`tariff_window`), xem Dashboard KPI và chạy Benchmark thuật toán.

   * **Cách App và Web kết nối với nhau:** Cả App Mobile và Web đều gọi chung vào một **Backend Server** thông qua giao thức **HTTP REST API** (gửi/nhận dữ liệu dạng JSON) và nhận cập nhật thời gian thực qua **SSE (Server-Sent Events) / WebSocket** hoặc **Polling**. Khi HOST đổi trạng thái cổng trên Web hoặc ADMIN duyệt trạm, Backend lưu vào Database; ngay lập tức App của USER truy vấn cùng Backend đó sẽ thấy trạng thái mới.

2. **Tầng Trung tâm điều phối (Backend API Server):**

   * Đóng vai trò "người gác cổng": Xác thực tài khoản (JWT/Google Auth), kiểm tra quyền hạn (`USER`, `HOST`, `ADMIN`), kiểm tra tính hợp lệ của dữ liệu đặt lịch, quản lý giao dịch Database (Transaction) và điều phối gọi AI.

   * Khi có yêu cầu đặt lịch mới (`POST /requests`), Backend lưu yêu cầu ở trạng thái `PENDING` kèm sự kiện vào bảng `outbox_event` / hàng đợi (`optimization_job`), trả mã phản hồi nhanh (`202 Accepted` kèm `request_id` và `job_id`) để UI không bị đơ chờ đợi.

3. **Tầng Cơ sở dữ liệu (Database — PostgreSQL + PostGIS):**

   * Lưu trữ **19 bảng chuẩn hóa** (17 bảng lõi nghiệp vụ/thử nghiệm + 2 bảng hàng đợi vận hành đồng thời).

   * Dùng tiện ích mở rộng **PostGIS** (hoặc chỉ mục không gian H3) để lưu tọa độ trạm sạc (`lat`, `lng`), ranh giới cụm điện (`boundary`) giúp tìm trạm gần người dùng và gom cụm điều phối.

4. **Tầng Trí tuệ nhân tạo & Tối ưu hóa (AI Engine / Optimizer Worker):**

   * **AI nằm ở đâu?** AI **không nằm trong giao diện App/Web**, mà là một **Service / Worker độc lập viết bằng Python** (thường bọc bằng FastAPI hoặc chạy dạng Background Worker lắng nghe hàng đợi Kafka/Redis/Database Job).

   * **Cách AI kết nối với App:**

     * **Bước 1:** User bấm "Đặt lịch" trên App -> App gửi JSON lên Backend (`POST /requests`).

     * **Bước 2:** Backend gom toàn bộ dữ liệu hiện tại của cụm đó (các yêu cầu cũ đang chờ/đang sạc + yêu cầu mới + danh sách cổng khả dụng + trần công suất trạm/cụm + biểu giá điện) đóng gói thành một gói JSON gọi là **Input Snapshot** và gửi sang **AI Engine**.

     * **Bước 3:** AI Engine chạy thuật toán tối ưu (MILP/LP + MPC), kiểm tra qua bộ **Validator** độc lập, rồi trả kết quả JSON (gồm lịch phân bổ từng khung 15 phút, lượng điện thiếu `shortfall_kwh`, chi phí dự kiến, trạng thái solver và lời giải thích `explanation`) về cho **Backend**.

     * **Bước 4:** Backend lưu lịch mới vào Database (tăng `version`, khóa hoặc chuyển lịch cũ tương lai sang `is_active = false`), sau đó đẩy thông báo kết quả về màn hình **App/Web** cho người dùng xem.

## 2. PHẦN DATA: CẦN LÀM NHỮNG GÌ, TÌM THÔNG TIN GÌ, TẠO BẢNG EXCEL/CSV RA SAO?

Nhóm làm Data là nền móng của cả dự án: nếu chưa có bộ dữ liệu chuẩn thì Backend không có gì hiển thị lên bản đồ và AI không có đầu vào để chạy thuật toán hay chấm điểm Benchmark.

### 2.1. Tổng hợp 5 đầu việc chính của nhóm Data

1. **Thu thập dữ liệu thực tế & khảo sát (`REAL` / `SURVEY`):**

   * Danh mục các dòng xe điện phổ biến tại Việt Nam (VinFast, Hyundai, Kia, BYD, Tesla, xe máy điện...).

   * Dữ liệu các trạm sạc trong thành phố (ví dụ Đà Nẵng / Hà Nội / TP.HCM) và mở rộng ra toàn quốc.

   * Biểu giá điện sinh hoạt/kinh doanh theo khung giờ thấp điểm – bình thường – cao điểm tại Việt Nam.

2. **Thiết kế và tạo bộ file Excel / CSV chuẩn hóa (Seed Data):**

   * Tạo các sheet Excel (và xuất ra `.csv`) khớp **100% tên cột và kiểu dữ liệu** với 19 bảng trong ERD để nhóm Backend import thẳng vào PostgreSQL.

3. **Sinh dữ liệu giả lập quy mô lớn (`SIMULATED`) để test tải & Benchmark:**

   * Viết script Python sinh **100.000 tài khoản (`app_user`)** và phương tiện (`vehicle`) trong danh mục.

   * Sinh các kịch bản yêu cầu sạc hoạt động đồng thời (`active_requests`: 50, 100, 500, 1.000, 2.500, 5.000, 10.000 requests) theo phân bố giờ cao điểm/thấp điểm để nhóm AI chạy thực nghiệm các thuật toán.

4. **Sinh dữ liệu lịch sử đặt lịch theo giờ (Time-series Data):**

   * Tạo dữ liệu lịch sử số lượt xe đến đặt sạc theo từng giờ, thứ trong tuần, ngày lễ (tối thiểu 3–6 tháng giả lập) để huấn luyện **Model phụ (Forecast Model)** dự báo nhu cầu.

5. **Kiểm tra ràng buộc dữ liệu (Data Cleaning & Validation):**

   * Đảm bảo không có lỗi logic trước khi bàn giao: `departure_time > arrival_time`, `0 <= soc_now < soc_target <= 100`, khung giờ biểu giá (`tariff_window`) phủ kín 24/24h không bị hở hay chồng lấn, tổng công suất hiệu dụng không âm.

### 2.2. Nguồn tìm kiếm thông tin thực tế cho từng loại dữ liệu

| Nhóm dữ liệu | Cần tìm những thông tin gì? | Nguồn tra cứu & Công cụ lấy dữ liệu | 
| ----- | ----- | ----- | 
| **1. Mẫu xe điện (`vehicle_model`)** | Hãng xe (`brand`), tên mẫu (`model_name`), loại xe (`CAR` / `MOTORBIKE`), chuẩn đầu nối (`CCS2`, `Type2`, `CHAdeMO`, `AC_HOME`), dung lượng pin (`battery_kwh`), công suất sạc tối đa xe nhận được (`max_kw`). | Website thông số kỹ thuật của VinFast (VF e34, VF 5, VF 6, VF 7, VF 8, VF 9, Feliz S, Klara S, Evo200), EV Database (`ev-database.org`), brochure hãng BYD, Hyundai Ioniq 5, Kia EV6. | 
| **2. Trạm sạc (`charging_station`) & Cụm điện (`grid_cluster`)** | Tên trạm, địa chỉ, tỉnh/thành phố, tọa độ (`lat`, `lng`), giờ mở cửa (`open_time`, `close_time`), loại xe hỗ trợ, trần công suất trạm (`station_power_kw`), phí dịch vụ. | **OpenStreetMap (Overpass Turbo API)** với tag `amenity=charging_station`, bản đồ trạm sạc công cộng, Google Maps API, kết hợp phân cụm địa lý bằng thư viện **Uber H3** hoặc chia theo Quận/Huyện. | 
| **3. Cổng sạc (`port`)** | Mã cổng trong trạm (`port_code`: P1, P2...), chuẩn đầu nối (`connector_type`), loại điều khiển (`CONTINUOUS` điều chỉnh kW liên tục hoặc `ON_OFF_SWITCH` bật/tắt mức cố định), `min_power_kw`, `max_power_kw`. | Tài liệu trụ sạc AC (3.3 kW, 7.4 kW, 11 kW, 22 kW) và trụ DC (30 kW, 60 kW, 150 kW). Với trạm dân sinh chia sẻ (ShareGrid), cấu hình trụ AC 2.2 kW – 7.4 kW (ON/OFF hoặc liên tục). | 
| **4. Biểu giá điện (`tariff_window`)** | Loại ngày (`WEEKDAY`, `WEEKEND`, `HOLIDAY`), khung bậc (`OFF_PEAK`, `NORMAL`, `PEAK`), giờ bắt đầu/kết thúc, đơn giá (`price_vnd_kwh`). | **Biểu giá TOU giả định theo khung giờ cao/thấp điểm** (giờ thấp điểm 00:00–04:00 và 22:00–24:00; giờ cao điểm 09:30–11:30 và 17:00–20:00). Đây là giả định cho mô phỏng, chưa xác thực là biểu giá chính thức. |

### 2.3. Cách thiết kế các Sheet trong file Excel (Data Dictionary chuẩn 19 bảng)

Khi tạo file Excel mẫu (ví dụ `EV_ShareGrid_Dataset_Master.xlsx`), nhóm Data nên chia thành **3 nhóm Sheet** tương ứng với 19 bảng của hệ thống. Dưới đây là cấu trúc cột chi tiết và ví dụ dữ liệu mẫu cho từng Sheet để bạn tạo bảng ngay:

#### Nhóm Sheet 1: Danh mục gốc và Tài nguyên (7 bảng — Bắt buộc phải tạo dữ liệu tĩnh trước)

**Sheet 1: `grid_cluster` (Cụm lưới điện điều phối)**

* **Vai trò:** Chia nhỏ thành phố/toàn quốc thành các cụm độc lập. Mỗi cụm có một mức trần công suất cố định (`grid_limit_kw`) mà tổng tất cả các trạm trong cụm tại một khung 15 phút không được vượt qua.

* **Các cột cần tạo trong Excel:**

| cluster_id | name | province | timezone | status | h3_index | centroid_lat | centroid_lng | grid_limit_kw | created_at | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 1 | Cụm Hải Châu - Trung tâm | Đà Nẵng | Asia/Ho_Chi_Minh | ACTIVE | 87652636affffff | 16.067780 | 108.220830 | 500.000 | 2026-11-01T00:00:00+07:00 | 
| 2 | Cụm Sơn Trà - Ven biển | Đà Nẵng | Asia/Ho_Chi_Minh | ACTIVE | 87652636bffffff | 16.071200 | 108.235500 | 350.000 | 2026-11-01T00:00:00+07:00 | 
| 3 | Cụm Cầu Giấy | Hà Nội | Asia/Ho_Chi_Minh | ACTIVE | 87652004affffff | 21.036200 | 105.790500 | 800.000 | 2026-11-01T00:00:00+07:00 | 
| 4 | Cụm Quận 1 | TP. Hồ Chí Minh | Asia/Ho_Chi_Minh | ACTIVE | 8765a0c2affffff | 10.775600 | 106.701900 | 1000.000 | 2026-11-01T00:00:00+07:00 | 

**Sheet 2: `vehicle_model` (Danh mục mẫu xe điện)**

* **Vai trò:** Lưu thông số kỹ thuật chuẩn của từng dòng xe để tính điện năng cần sạc và kiểm tra tương thích cổng sạc. Не tự suy diễn thông số hãng ngoài danh mục.

* **Các cột cần tạo trong Excel:**

| model_id | brand | model_name | vehicle_type | connector_type | battery_kwh | max_kw | source_type | source_ref | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 1 | VinFast | VF 5 Plus | CAR | CCS2 | 37.230 | 7.400 | REAL | https://www.google.com/search?q=vinfastauto.com/vn_vi/vf-5-plus | 
| 2 | VinFast | VF e34 | CAR | CCS2 | 41.900 | 11.000 | REAL | vinfastauto.com/vn_vi/vf-e34 | 
| 3 | VinFast | VF 8 Eco | CAR | CCS2 | 87.700 | 11.000 | REAL | vinfastauto.com/vn_vi/vf-8 | 
| 4 | VinFast | Feliz S | MOTORBIKE | AC_HOME | 3.500 | 1.000 | REAL | https://www.google.com/search?q=vinfastauto.com/vn_vi/xe-may-dien-feliz-s | 
| 5 | BYD | Atto 3 | CAR | Type2 | 60.480 | 7.000 | REAL | https://www.google.com/search?q=byd.com/vn/car/atto-3 | 
| 6 | Hyundai | Ioniq 5 | CAR | CCS2 | 72.600 | 11.000 | REAL | hyundai.thanhcong.vn/ioniq-5 | 

**Sheet 3: `app_user` (Tài khoản người dùng, chủ trạm, quản trị)**

* **Vai trò:** Lưu thông tin người dùng. Lưu ý: Tuổi đời tài khoản (`created_at` cũ hay mới) **không** tạo ra đặc quyền ưu tiên khi lập lịch.

* **Các cột cần tạo trong Excel:**

| user_id | role | full_name | email | phone | reliability_score | status | created_at | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 1 | ADMIN | Quản trị Hệ thống | admin@sharegrid.vn | 0901000001 | 100.00 | ACTIVE | 2026-01-01T08:00:00+07:00 | 
| 2 | HOST | Nguyễn Văn Chủ Trạm | host1@sharegrid.vn | 0901000002 | 98.50 | ACTIVE | 2026-02-15T08:00:00+07:00 | 
| 3 | USER | Trần Thị Khách Cũ | user_old@gmail.com | 0905111222 | 95.00 | ACTIVE | 2026-03-10T09:00:00+07:00 | 
| 4 | USER | Lê Hoàng Khách Mới | user_new@gmail.com | 0905333444 | 95.00 | ACTIVE | 2026-11-17T08:30:00+07:00 | 

**Sheet 4: `vehicle` (Xe cụ thể của từng người dùng)**

* **Các cột cần tạo trong Excel:**

| vehicle_id | user_id | model_id | plate_number | nickname | default_soc_target | is_default | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 101 | 3 | 1 | 43A-123.45 | VF5 Đi làm | 80.00 | TRUE | 
| 102 | 4 | 2 | 43A-678.90 | VFe34 Gia đình | 85.00 | TRUE | 
| 103 | 4 | 4 | 43-K1 555.66 | Xe máy Feliz | 90.00 | FALSE | 

**Sheet 5: `charging_station` (Trạm sạc)**

* **Vai trò:** Lưu vị trí, giờ mở cửa và trần công suất của toàn trạm (`station_power_kw`). Tổng công suất các cổng đang phát tại trạm không được vượt `station_power_kw` (kể cả khi cộng công suất danh định các cổng lớn hơn trần trạm).

* **Các cột cần tạo trong Excel:**

| station_id | cluster_id | owner_id | name | address | province | supported_vehicle_type | status | lat | lng | open_time | close_time | is_24h | verified | station_power_kw | service_fee_vnd | price_override_vnd_kwh | max_session_minutes | source_type | source_ref | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 10 | 1 | 2 | Trạm ShareGrid Bạch Đằng | 120 Bạch Đằng, Hải Châu | Đà Nẵng | ALL | ACTIVE | 16.068100 | 108.224500 | 06:00 | 23:00 | FALSE | TRUE | 22.000 | 5000.00 | NULL | 240 | SURVEY | Khao_sat_DN_01 | 
| 11 | 1 | 2 | Trạm ShareGrid Nguyễn Văn Linh | 85 Nguyễn Văn Linh, Hải Châu | Đà Nẵng | CAR | ACTIVE | 16.060500 | 108.215200 | 00:00 | 23:59 | TRUE | TRUE | 40.000 | 10000.00 | NULL | 360 | REAL | osm_node_99281 | 

**Sheet 6: `port` (Cổng sạc vật lý trong trạm)**

* **Vai trò:** Đơn vị tài nguyên nhỏ nhất được gán lịch. Chú ý cột `control_type`:

  * `CONTINUOUS`: Điều chỉnh công suất liên tục trong khoảng `[min_power_kw, max_power_kw]` (hoặc bằng 0 khi tắt).

  * `ON_OFF_SWITCH`: Chỉ có 2 trạng thái: Tắt (`0 kW`) hoặc Bật ở mức cố định (`max_power_kw`).

* **Các cột cần tạo trong Excel:**

| port_id | station_id | port_code | connector_type | control_type | status | min_power_kw | max_power_kw | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 1001 | 10 | P1 | CCS2 | CONTINUOUS | ACTIVE | 1.400 | 7.400 | 
| 1002 | 10 | P2 | CCS2 | CONTINUOUS | ACTIVE | 1.400 | 7.400 | 
| 1003 | 10 | P3 | AC_HOME | ON_OFF_SWITCH | ACTIVE | 2.200 | 2.200 | 
| 1004 | 10 | P4 | Type2 | CONTINUOUS | MAINTENANCE | 1.400 | 11.000 | 

**Sheet 7: `tariff_window` (Biểu giá điện theo khung giờ)**

* **Vai trò:** Giúp thuật toán AI dời lịch sạc sang các khung giờ điện rẻ nếu thời gian đỗ xe của khách cho phép.

* **Các cột cần tạo trong Excel:**

| tariff_id | cluster_id | day_type | band | start_time | end_time | price_vnd_kwh | valid_from | valid_to | source_ref | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| 1 | 1 | WEEKDAY | OFF_PEAK | 00:00 | 04:00 | 1600.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |
| 2 | 1 | WEEKDAY | NORMAL | 04:00 | 09:30 | 2400.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |
| 3 | 1 | WEEKDAY | PEAK | 09:30 | 11:30 | 4000.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |
| 4 | 1 | WEEKDAY | NORMAL | 11:30 | 17:00 | 2400.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |
| 5 | 1 | WEEKDAY | PEAK | 17:00 | 20:00 | 4000.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |
| 6 | 1 | WEEKDAY | NORMAL | 20:00 | 22:00 | 2400.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |
| 7 | 1 | WEEKDAY | OFF_PEAK | 22:00 | 24:00 | 1600.00 | 2026-01-01 | 2026-12-31 | biểu giá TOU giả định theo khung giờ cao/thấp điểm |

#### Nhóm Sheet 2: Vận hành Đặt lịch, Giải tối ưu & Phiên sạc (6 bảng lõi + 2 bảng hàng đợi đồng thời)

Các bảng này trong thực tế sẽ do Backend và AI tự sinh ra khi chạy ứng dụng, nhưng **nhóm Data cần tạo dữ liệu kịch bản mẫu (Seed / Test Scenarios)** để kiểm thử thuật toán và hiển thị lên UI:

| Tên Bảng / Sheet | Các cột chính | Quy tắc tính toán & Ghi chú cho nhóm Data | 
| ----- | ----- | ----- | 
| **8. `charging_request`** | `request_id`, `user_id`, `vehicle_id`, `cluster_id`, `station_id`, `scenario_id`, `idempotency_key`, `arrival_time`, `departure_time`, `soc_now`, `soc_target`, `battery_kwh_snapshot`, `max_kw_snapshot`, `eta`, `energy_needed_kwh`, `shortfall_kwh`, `priority_weight`, `status`, `created_at` | Công thức tính điện năng cần cấp tại lúc đặt:  `energy_needed_kwh = ((soc_target - soc_now) / 100.0) * battery_kwh_snapshot / eta`  (Trong đó `eta` là hiệu suất sạc, thường lấy `0.90` hoặc `0.92`, hoặc `1.00` nếu tính quy chuẩn đầu vào).  Trạng thái `status` thuộc: `PENDING`, `SCHEDULED`, `CONFIRMED`, `CHARGING`, `DONE`, `CANCELLED`, `NO_SHOW`, `FAILED`. | 
| **9. `optimization_run`** | `run_id`, `cluster_id`, `scenario_id`, `job_id`, `input_version`, `algorithm`, `trigger_type`, `status`, `code_version`, `started_at`, `solve_ms`, `seed`, `slot_minutes`, `n_requests`, `weights_json`, `input_json`, `kpi_json` | Lưu thông tin một lần chạy bộ lập lịch. `slot_minutes = 15`. `status` thuộc: `OPTIMAL`, `FEASIBLE`, `FALLBACK`, `INFEASIBLE`, `ERROR`. | 
| **10. `run_request`** | `run_id`, `request_id`, `allocated_kwh`, `shortfall_kwh`, `expected_soc`, `estimated_cost_vnd`, `explanation` | Bảng trung gian nối kết quả của từng `request_id` trong lần chạy `run_id`. Lưu rõ lý do giải thích (`explanation`). | 
| **11. `schedule`** | `schedule_id`, `run_id`, `request_id`, `port_id`, `slot_start`, `power_kw`, `version`, `is_active` | Lưu chi tiết từng khung 15 phút (`slot_start` căn chẵn `:00`, `:15`, `:30`, `:45`), xe nào cắm cổng nào với công suất bao nhiêu kW. Chỉ bản mới nhất có `is_active = TRUE`. | 
| **12. `charging_session`** | `session_id`, `request_id`, `port_id`, `start_time`, `end_time`, `energy_kwh`, `soc_start`, `soc_end`, `cost_energy_vnd`, `cost_service_vnd`, `total_vnd`, `stop_reason`, `status`, `is_simulated` | Ghi nhận lượng điện thực tế đã nạp (`energy_kwh`). Dùng để tính phần điện còn thiếu khi tái lập lịch:  `remaining_kwh = max(0, energy_needed_kwh - energy_kwh)`. | 
| **13. `notification`** | `notif_id`, `user_id`, `request_id`, `type`, `title`, `body`, `channel`, `created_at`, `sent_at`, `read_at` | Lưu thông báo đẩy cho người dùng khi có lịch mới hoặc khi lịch tương lai bị đổi do tái tối ưu. | 
| **14. `outbox_event`** *(Phụ lục C)* | `event_id`, `cluster_id`, `aggregate_type`, `aggregate_id`, `event_type`, `payload_json`, `dedupe_key`, `created_at`, `published_at`, `attempts`, `status` | Lưu sự kiện đặt/hủy lịch trong cùng Transaction DB để chống mất sự kiện khi tải cao 10.000 users. | 
| **15. `optimization_job`** *(Phụ lục C)* | `job_id`, `cluster_id`, `target_version`, `status`, `events_count`, `attempt_count`, `queued_at`, `started_at`, `finished_at`, `lease_expires_at`, `worker_id` | Gom nhiều sự kiện đặt lịch liên tiếp trong cùng cụm (Coalescing) thành 1 job giải tối ưu duy nhất. | 

#### Nhóm Sheet 3: Dự báo nhu cầu & Benchmark thuật toán (4 bảng)

| Tên Bảng / Sheet | Các cột chính | Mục đích sử dụng | 
| ----- | ----- | ----- | 
| **16. `forecast_model`** | `model_id`, `name`, `version`, `algorithm`, `artifact_path`, `status`, `trained_until`, `metrics_json` | Lưu thông tin model dự báo số lượt đặt sạc (`HOURLY_MEAN`, `RANDOM_FOREST`, `XGBOOST`) và sai số `MAE`, `RMSE`. | 
| **17. `demand_forecast`** | `forecast_id`, `cluster_id`, `model_id`, `generated_at`, `hour_start`, `pred_arrivals` | Lưu kết quả dự báo số lượt yêu cầu đến theo từng giờ (`pred_arrivals`). Lưu ý: chỉ dự báo số lượt request, không tự cộng vào công suất solver. | 
| **18. `simulation_scenario`** | `scenario_id`, `name`, `source_type`, `seed`, `registry_users`, `active_requests`, `config_json`, `created_at` | Định nghĩa các kịch bản test (ví dụ: `registry_users = 100000`, còn `active_requests` lần lượt là `100`, `500`, `1000`, `5000`, `10000`). | 
| **19. `benchmark_result`** | `benchmark_id`, `scenario_id`, `run_id`, `algorithm`, `repeat_no`, `metrics_json`, `measured_at` | Lưu bảng điểm so sánh giữa các thuật toán (`MILP_MPC`, `LP_MPC`, `LLF`, `EDF`, `FCFS`, `EQUAL_SHARE`, `ASAP`, `NSGA_II`) trên cùng một kịch bản. | 

### 2.4. Hướng dẫn viết Script Python sinh bộ dữ liệu 100.000 Users & Mở rộng Toàn quốc

Theo ghi chú của nhóm bạn (*"Dữ liệu trạm sạc trong thành phố => mở rộng thêm toàn quốc"*, *"Data user 100000 test"*), bạn **không thể gõ tay 100.000 dòng trong Excel** (và lưu ý: 1 file Excel chỉ nên chứa các bảng danh mục gốc vài nghìn dòng để dễ xem, còn tập 100.000 users và requests phải xuất ra file `.csv` hoặc `.parquet` để nạp nhanh vào PostgreSQL bằng lệnh `COPY`).

Cách làm chuẩn cho nhóm Data:

1. **Bước 1 — Trạm sạc từ Thành phố ra Toàn quốc:**

   * Giai đoạn 1 (Cấp Thành phố): Tạo 3–5 `grid_cluster` tại 1 thành phố trọng điểm (ví dụ Đà Nẵng hoặc Hà Nội/TP.HCM), mỗi cụm có 5–15 trạm sạc (`charging_station`), mỗi trạm 4–10 cổng (`port`).

   * Giai đoạn 2 (Mở rộng Toàn quốc): Lấy danh sách tọa độ các trạm sạc trên toàn quốc từ OpenStreetMap (hoặc phân bố theo 63 tỉnh/thành phố), dùng thư viện `h3` (mức phân giải `resolution = 6` hoặc `7`) để tự động gán mỗi trạm vào một `cluster_id` dựa theo tọa độ `(lat, lng)`.

2. **Bước 2 — Sinh 100.000 Users + Vehicles (`registry_users = 100000`):**

   * Dùng thư viện `Faker` hoặc `numpy.random.Generator(seed=42)` trong Python để sinh 100.000 dòng `app_user` và 120.000 dòng `vehicle` (nối khóa ngoại `model_id` ngẫu nhiên theo tỷ lệ thị phần xe thực tế).

3. **Bước 3 — Sinh các tập `charging_request` theo kịch bản (`simulation_scenario`):**

   * Phân biệt rõ: **100.000 là tổng số tài khoản đăng ký trong hệ thống**, còn số lượng đưa vào bộ lập lịch mỗi lần chạy là **số request đang hoạt động (`active_requests`)**.

   * Tạo sẵn 6 bộ file CSV kịch bản chuẩn với `active_requests` = `100`, `500`, `1000`, `2500`, `5000`, `10000` (chia làm 2 profile: *Balanced* — rải đều các cụm, và *Hot-spot* — dồn tải vào 1 cụm trung tâm vào giờ cao điểm 17:00–20:00).

## 3. PHẦN WEB / APP: DANH SÁCH CHỨC NĂNG, MÀN HÌNH UI & LUỒNG HOẠT ĐỘNG CHI TIẾT

Nếu bạn đã thiết kế UI cơ bản nhưng chưa rõ cần bao nhiêu chức năng và luồng đi như thế nào, hãy chia ứng dụng theo **3 phân quyền (Role)** rõ rệt: **USER (Người đi xe điện)**, **HOST (Chủ trạm sạc)** và **ADMIN (Quản trị hệ thống)**.

### 3.1. Phân hệ 1: Giao diện Người dùng (USER App / Web) — 7 Màn hình & Chức năng chính

| STT | Tên màn hình / Chức năng | Các thành phần cần có trên UI | Luồng xử lý dưới Backend khi User thao tác | 
| ----- | ----- | ----- | ----- | 
| **1** | **Đăng ký / Đăng nhập** | Form Email/SĐT hoặc nút Đăng nhập Google. | Xác thực token, trả về thông tin `user_id`, `role`. Lưu ý: User mới hay cũ có quyền bình đẳng khi xếp lịch sạc. | 
| **2** | **Quản lý Hồ sơ Xe (Garage của tôi)** | Danh sách xe của user; Form thêm xe: Chọn hãng & mẫu xe có sẵn từ dropdown (`vehicle_model`), nhập biển số (`plate_number`), tên gợi nhớ, mức pin mục tiêu mặc định (`default_soc_target`, ví dụ 80%). | Khi chọn mẫu xe từ danh mục, tự động lấy `connector_type`, `battery_kwh`, `max_kw`. Không cho phép người dùng tự bịa thông số hãng chưa kiểm chứng. | 
| **3** | **Bản đồ & Tìm kiếm Trạm sạc** | Bản đồ (Leaflet/Mapbox/Google Maps) hiển thị các trạm sạc; Bộ lọc theo: Loại xe (`CAR`/`MOTORBIKE`), Đầu nối (`CCS2`, `Type2`, `AC_HOME`), Giờ mở cửa, Khoảng cách. | Gọi API `GET /stations?lat=...&lng=...&connector_type=...`. Backend đọc từ Cache/DB các trạm có `status = ACTIVE` và `verified = TRUE`, hiển thị số cổng trống và khung giá điện hiện tại. | 
| **4** | **Chi tiết Trạm sạc** | Hiển thị tên trạm, địa chỉ, giờ mở/đóng cửa, phí dịch vụ (`service_fee_vnd`), danh sách các cổng (`port_code`, đầu nối, công suất kW, trạng thái `ACTIVE`/`MAINTENANCE`), biểu đồ giá điện theo khung giờ trong ngày. | Giúp người dùng nắm rõ thông tin trạm trước khi bấm nút **"Đặt lịch sạc"**. | 
| **5** | **Form Đặt lịch sạc (Booking Request)** | 1\. Chọn xe của mình.  2\. Chọn giờ dự kiến đến (`arrival_time`) và giờ dự kiến lấy xe (`departure_time`).  3\. Nhập % Pin hiện tại (`soc_now`) và % Pin mong muốn (`soc_target`).  4\. Nút **"Gửi yêu cầu & Xếp lịch"**. | Backend kiểm tra 4 điều kiện cứng:  \- Xe có cùng đầu nối (`connector_type`) và loại xe với trạm không? (Nếu lệch, báo lỗi và gợi ý trạm khác).  \- `soc_now < soc_target <= 100` và `departure_time > arrival_time` và nằm trong giờ mở cửa trạm?  \- Xe này có đang có request khác bị trùng khung giờ không? (Nếu trùng, từ chối hoặc yêu cầu hủy/sửa lịch cũ trước).  \- Tính `energy_needed_kwh` và đẩy vào hàng đợi tối ưu của cụm. | 
| **6** | **Kết quả Lịch sạc & Giải thích AI** | \- Trạng thái giải (`OPTIMAL`, `FEASIBLE`, `FALLBACK`).  \- Cổng sạc được gán (ví dụ: Cổng `P3`).  \- Biểu đồ thanh (Timeline/Gantt 15 phút): hiển thị từng khung 15 phút xe được cấp bao nhiêu kW.  \- Các chỉ số: Pin dự kiến đạt được (`expected_soc` %), Điện năng thiếu nếu có (`shortfall_kwh`), Tổng chi phí dự kiến (`estimated_cost_vnd`).  \- **Hộp giải thích (`explanation`):** Ví dụ *"Được xếp vào khung 10:00–11:15 ở cổng P3 vì giá điện thấp (2.400đ/kWh) và kịp trước giờ rời 12:00"*. | Nhận dữ liệu từ bảng `run_request` và `schedule` (với `is_active = TRUE`). Có nút **"Xác nhận lịch"** hoặc **"Sửa / Hủy yêu cầu"**. | 
| **7** | **Theo dõi Phiên sạc (Live Session) & Thông báo** | \- Tiến độ sạc hiện tại: % Pin hiện tại, số kWh đã nạp, thời gian còn lại.  \- Nút giả lập cho mục đích Demo: *"Báo đã đến trạm (Check-in)"*, *"Đến trễ 15 phút"*, *"Rời trạm sớm / Dừng sạc"*.  \- Danh sách Thông báo (`notification`) khi lịch tương lai được cập nhật phiên bản mới (`version`). | Khi user bấm hủy, đổi giờ, hoặc đến trễ, Backend khóa phần điện năng và các slot đã thực thi, cập nhật `remaining_kwh` và kích hoạt bộ điều khiển **MPC** giải lại các slot tương lai. | 

#### Sự khác biệt giữa Luồng Người dùng lần đầu và Người dùng quay lại (Trang 4 Báo cáo)

* **Người dùng lần đầu:** Đăng ký -> Bắt buộc thêm ít nhất 1 xe vào hồ sơ -> Tìm trạm tương thích với đầu nối của xe vừa thêm -> Nhập giờ đến/đi và SOC -> Backend tạo request và đưa vào pool tối ưu chung cùng các xe đang active khác -> Nhận lịch.

* **Người dùng quay lại:** Đăng nhập -> Hệ thống tự động tải xe mặc định, trạm yêu thích và phiên sạc/lịch hẹn đang mở -> Nếu tạo request mới, hệ thống kiểm tra trùng giờ với chính xe đó -> Nếu sửa/hủy request đang có, hệ thống giữ nguyên phần lịch đã chạy (`CHARGING`), chỉ giải lại phần tương lai và gửi thông báo cho các xe có lịch bị thay đổi phiên bản.

### 3.2. Phân hệ 2: Giao diện Chủ trạm (HOST Web Portal) — 4 Chức năng chính

Chủ trạm là người sở hữu điểm sạc chia sẻ, chỉ có quyền thao tác trên các trạm thuộc quyền sở hữu của mình (`owner_id = user_id`), **không được tự ý viết lịch cho từng xe và không được tự duyệt trạm từ `PENDING` sang `ACTIVE`**:

1. **Đăng ký & Cấu hình Trạm sạc mới:**

   * Nhập tên trạm, địa chỉ, chọn vị trí trên bản đồ (`lat`, `lng`), giờ mở/đóng cửa (`open_time`, `close_time`), loại xe hỗ trợ, trần công suất tối đa của đường dây trạm (`station_power_kw`), phí dịch vụ (`service_fee_vnd`).

   * Sau khi lưu, trạng thái trạm là `PENDING` (chờ ADMIN kiểm chứng).

2. **Quản lý Danh sách Cổng sạc (`port`) trong trạm:**

   * Thêm/sửa các cổng sạc: Mã cổng (`P1`, `P2`...), chuẩn đầu nối (`CCS2`, `Type2`, `AC_HOME`), loại điều khiển (`CONTINUOUS` hay `ON_OFF_SWITCH`), công suất `min_power_kw` và `max_power_kw`.

3. **Báo hỏng / Chuyển trạng thái Bảo trì (`MAINTENANCE` / `OFFLINE`):**

   * Khi một cổng sạc hoặc cả trạm gặp sự cố, HOST bấm chuyển trạng thái sang `MAINTENANCE` hoặc `OFFLINE` và nhập thời gian dự kiến.

   * **Luồng tự động:** Ngay khi HOST bấm nút này, Backend phát sự kiện `RE_OPTIMIZE` cho cụm đó -> AI Engine giữ nguyên các slot đã chạy, tự động tìm cổng khác còn trống trong trạm (nếu quy tắc cho phép và tương thích đầu nối) để chuyển lịch tương lai cho khách; nếu hết cổng, tính lại `shortfall_kwh` và bắn thông báo khẩn cho các khách bị ảnh hưởng.

4. **Theo dõi Lịch đặt chỗ & Doanh thu tại trạm:**

   * Xem biểu đồ lịch sử dụng các cổng của trạm mình theo từng khung 15 phút trong ngày và thống kê tổng kWh, phí dịch vụ thu được.

### 3.3. Phân hệ 3: Giao diện Quản trị viên (ADMIN Dashboard) — 6 Chức năng chính

1. **Quản lý Cụm điều phối (`grid_cluster`):**

   * Tạo/cập nhật các cụm địa lý, vẽ hoặc gán vùng ranh giới (`boundary` / `h3_index`), và thiết lập **trần công suất sạc cố định của cụm (`grid_limit_kw`)**.

2. **Kiểm duyệt Trạm sạc & Quy ước Dữ liệu:**

   * Rà soát các trạm do HOST gửi lên hoặc dữ liệu thu thập từ bản đồ (`source_type`: `REAL`, `SURVEY`, `SIMULATED`).

   * Kiểm tra công suất trạm có hợp lý không (tránh nhầm lẫn giữa tổng công suất danh định các cổng và công suất trần thực tế của trạm), đánh dấu `verified = TRUE` và chuyển `status = ACTIVE`.

3. **Quản lý Biểu giá điện (`tariff_window`):**

   * Thiết lập bảng giá điện theo cụm, loại ngày và khung giờ. Hệ thống tự động kiểm tra không cho phép các khung giờ bị chồng chéo hoặc bỏ trống giờ trong ngày.

4. **Giám sát Vận hành & Hàng đợi Tối ưu (System & Solver Monitor):**

   * Xem danh sách các phiên giải (`optimization_run`) và hàng đợi công việc (`optimization_job`): thời gian giải (`solve_ms`), trạng thái (`OPTIMAL`, `FEASIBLE`, `FALLBACK`), số lượng request trong mỗi cụm.

5. **Trung tâm Mô phỏng & Benchmark Thuật toán (Simulation & Benchmark Lab):**

   * Màn hình cực kỳ quan trọng để demo đồ án/báo cáo: Cho phép chọn kịch bản (`simulation_scenario`: 100, 500, 1.000, 10.000 requests), chọn các thuật toán cần chạy đối sánh (`MILP_MPC`, `LP`, `LLF`, `FCFS`, `EDF`, `Equal Share`, `ASAP`), bấm chạy và hiển thị bảng/biểu đồ so sánh KPI (Tổng điện thiếu `shortfall`, Tỷ lệ đúng hạn `on-time rate`, Tổng chi phí điện, Thời gian chạy `solve_ms`, Chỉ số công bằng `fairness`, Số vi phạm trần công suất).

6. **Nhật ký Kiểm toán (Audit Log) & Dự báo Nhu cầu (Demand Forecast View):**

   * Xem biểu đồ dự báo số lượng yêu cầu đặt sạc theo giờ sắp tới từ `demand_forecast` (ghi nhãn rõ đâu là số cấu hình, đâu là số dự báo và đâu là dữ liệu mô phỏng) và lịch sử thay đổi cấu hình hệ thống.

## 4. PHẦN AI & THUẬT TOÁN: VAI TRÒ, CÁCH TRIỂN KHAI & KẾT NỐI VỚI APP

Trong dự án EV ShareGrid, **AI không phải là một mô hình ngôn ngữ (LLM/Chatbot) tự suy đoán lịch**, mà được chia thành **2 khối rõ ràng**:

1. **Model chính (Core Decision Engine — Bộ lập lịch tối ưu có ràng buộc):** Dùng Vận trù học / Tối ưu hóa tổ hợp (**LP / MILP / CP-SAT** kết hợp điều khiển dự báo theo khung trượt **MPC - Model Predictive Control** và thuật toán dự phòng **LLF - Least Laxity First**).

2. **Model phụ (Auxiliary Model — Dự báo nhu cầu):** Dùng Machine Learning (**Hourly Mean Baseline, Random Forest, XGBoost**) để ước lượng số lượt đặt sạc theo giờ trong tương lai (`pred_arrivals`), phục vụ cảnh báo sớm trên Dashboard (không tự động cộng ảo vào công suất solver).

### 4.1. Cách AI kết nối với Backend & App (Kiến trúc API / Worker)

Để dễ triển khai nhất cho nhóm sinh viên nhưng vẫn đúng chuẩn kiến trúc mở rộng 10.000 người dùng trong báo cáo, bạn hãy tách code thành 2 service giao tiếp qua JSON:

* **Backend Service (Node.js / NestJS / Spring Boot hoặc Python FastAPI):** Quản lý Auth, CRUD trạm/xe/request, kết nối PostgreSQL.

* **AI Engine Service (Python 3.10+ với thư viện `ortools`, `scipy`, `scikit-learn`, `xgboost`, `fastapi`):**

  * Cung cấp 3 endpoint nội bộ cho Backend gọi sang (hoặc lắng nghe qua Worker Queue):

    1. `POST /ai/optimize`: Nhận **Input Snapshot JSON** của 1 cụm -> Chạy bộ lập lịch (`MILP/LP` hoặc `LLF`) + `Validator` -> Trả về **Output Schedule JSON**.

    2. `POST /ai/benchmark`: Nhận kịch bản `scenario_id` -> Chạy đồng loạt các thuật toán (`MILP_MPC`, `LP`, `LLF`, `FCFS`, `EDF`, `Equal Share`, `ASAP`, `NSGA-II`) trên cùng một seed/input -> Trả về bảng điểm KPI.

    3. `POST /ai/forecast`: Nhận lịch sử đặt chỗ theo giờ -> Trả về dự báo `pred_arrivals` cho 24 giờ tiếp theo.

#### Mẫu JSON giao tiếp thực tế giữa Backend và AI Engine (`POST /ai/optimize`)

**Đầu vào Backend gửi cho AI Engine (Input Snapshot JSON):**

Ví dụ này truyền `time_budget_ms=2000` trực tiếp. Khi bỏ trường này, AI Engine mặc định dùng 10.000 ms cho snapshot dưới 300 request và 2.000 ms từ 300 request. Với snapshot từ 300 request, ngân sách gửi vào cũng bị giới hạn ở 2.000 ms.

```
{
  "cluster_id": 1,
  "input_version": 105,
  "snapshot_time": "2026-11-18T17:00:00+07:00",
  "slot_minutes": 15,
  "horizon_slots": 16,
  "grid_limit_kw": 3.0,
  "time_budget_ms": 2000,
  "stations": [
    {
      "station_id": 10,
      "station_power_kw": 4.0,
      "open_time": "06:00",
      "close_time": "23:00",
      "ports": [
        {"port_id": 101, "connector_type": "CCS2", "control_type": "CONTINUOUS", "min_power_kw": 0.0, "max_power_kw": 2.0, "status": "ACTIVE"},
        {"port_id": 102, "connector_type": "CCS2", "control_type": "CONTINUOUS", "min_power_kw": 0.0, "max_power_kw": 2.0, "status": "ACTIVE"}
      ]
    },
    {
      "station_id": 11,
      "station_power_kw": 2.0,
      "open_time": "00:00",
      "close_time": "23:59",
      "ports": [
        {"port_id": 201, "connector_type": "AC_HOME", "control_type": "ON_OFF_SWITCH", "min_power_kw": 1.0, "max_power_kw": 1.0, "status": "ACTIVE"},
        {"port_id": 202, "connector_type": "AC_HOME", "control_type": "ON_OFF_SWITCH", "min_power_kw": 1.0, "max_power_kw": 1.0, "status": "ACTIVE"}
      ]
    }
  ],
  "tariffs": [
    {"start_time": "17:00", "end_time": "17:15", "price_vnd_kwh": 4000},
    {"start_time": "17:15", "end_time": "18:00", "price_vnd_kwh": 2000}
  ],
  "requests": [
    {
      "request_id": 501,
      "station_id": 10,
      "connector_type": "CCS2",
      "vehicle_max_kw": 2.0,
      "arrival_time": "2026-11-18T16:30:00+07:00",
      "departure_time": "2026-11-18T18:00:00+07:00",
      "energy_needed_kwh": 1.50,
      "energy_delivered_kwh": 0.50,
      "priority_weight": 1.0,
      "status": "CHARGING",
      "locked_port_id": 101
    }
  ]
}

```

**Đầu ra AI Engine trả về cho Backend (Output Result JSON):**

```
{
  "status": "OPTIMAL",
  "algorithm": "MILP_MPC",
  "solve_ms": 142,
  "kpi": {
    "total_shortfall_kwh": 0.0,
    "total_cost_vnd": 5500.0,
    "peak_power_kw": 3.0,
    "on_time_rate": 1.0,
    "cap_violations": 0
  },
  "request_results": [
    {
      "request_id": 501,
      "allocated_kwh": 1.00,
      "shortfall_kwh": 0.00,
      "expected_soc": 80.0,
      "estimated_cost_vnd": 2000.0,
      "explanation": "Giữ 0.50 kWh đã nạp; xếp 1.00 kWh còn lại vào các khung 17:15-17:30 và 17:45-18:00 ở cổng 101 với giá thấp (2.000 VND/kWh), đảm bảo kịp rời trạm lúc 18:00."
    }
  ],
  "schedules": [
    {"request_id": 501, "port_id": 101, "slot_start": "2026-11-18T17:15:00+07:00", "power_kw": 2.0},
    {"request_id": 501, "port_id": 101, "slot_start": "2026-11-18T17:45:00+07:00", "power_kw": 2.0}
  ]
}

```

### 4.2. Chi tiết mô hình Toán học của Bộ lập lịch (LP / MILP)

Mỗi khung thời gian (slot $t$) có độ dài $\Delta t = 0.25$ giờ (15 phút).

#### 1. Các biến quyết định (Decision Variables):

* $x_{i,j,t} \in \{0, 1\}$: Biến nhị phân bằng $1$ nếu yêu cầu sạc $i$ được gán vào cổng sạc $j$ tại khung thời gian $t$, ngược lại bằng $0$.

* $p_{i,j,t} \ge 0$: Công suất điện (kW) cấp cho xe của yêu cầu $i$ tại cổng $j$ trong khung thời gian $t$.

* $\text{shortfall}_i \ge 0$: Lượng điện năng còn thiếu (kWh) không thể đáp ứng kịp trước giờ rời đi của yêu cầu $i$ (biến bù mềm để bài toán luôn tìm được nghiệm khả thi khi quá tải trạm/cụm).

#### 2. Các ràng buộc cứng (Hard Constraints — Tuyệt đối không được vi phạm):

1. **Ràng buộc năng lượng còn lại:**
   

   $$
   E_{\text{remaining}, i} = \max\left(0, E_{\text{needed}, i} - E_{\text{delivered}, i}\right)
   $$

   $$
   \sum_{j} \sum_{t} p_{i,j,t} \cdot \Delta t + \text{shortfall}_i = E_{\text{remaining}, i}, \quad \forall i
   $$

2. **Không trùng cổng và không phân thân xe:**

   * Mỗi cổng $j$ tại một slot $t$ chỉ phục vụ tối đa 1 xe: $\sum_{i} x_{i,j,t} \le 1, \quad \forall j, t$.

   * Mỗi xe $i$ tại một slot $t$ chỉ cắm tối đa 1 cổng: $\sum_{j} x_{i,j,t} \le 1, \quad \forall i, t$.
     *(Lưu ý: Trong bản Prototype, khuyến nghị giữ cố định 1 cổng xuyên suốt phiên sạc của 1 xe để người dùng không phải rút dây cắm sang cổng khác giữa chừng).*

3. **Ràng buộc tương thích và cửa sổ thời gian:**

   * $x_{i,j,t} = 0$ và $p_{i,j,t} = 0$ nếu: cổng $j$ không cùng trạm khách đặt, sai chuẩn đầu nối (`connector_type`), cổng đang `MAINTENANCE`/`OFFLINE`, hoặc slot $t$ nằm ngoài khoảng `[arrival_time, departure_time)` hay ngoài giờ mở cửa của trạm.

4. **Ràng buộc công suất theo loại cổng (`CONTINUOUS` vs `ON_OFF_SWITCH`):**

   * Với cổng điều khiển liên tục (`CONTINUOUS`):
     

     $$
     P_{\min, j} \cdot x_{i,j,t} \le p_{i,j,t} \le \min(P_{\max, j}, P_{\text{vehicle}, i}) \cdot x_{i,j,t}
     $$

   * Với cổng bật/tắt cố định (`ON_OFF_SWITCH` có công suất bật cố định $P_{\text{on}, j}$):
     

     $$
     p_{i,j,t} = P_{\text{on}, j} \cdot x_{i,j,t}
     $$

5. **Ràng buộc trần công suất Trạm (`station_power_kw`) và Cụm (`grid_limit_kw`):**

   * Tại mỗi trạm $s$ và mỗi slot $t$:
     

     $$
     \sum_{j \in \text{Ports}(s)} \sum_{i} p_{i,j,t} \le C_{\text{station}}(s)
     $$

   * Tại toàn cụm $c$ và mỗi slot $t$:
     

     $$
     \sum_{s \in \text{Stations}(c)} \sum_{j \in \text{Ports}(s)} \sum_{i} p_{i,j,t} \le C_{\text{cluster}}(c)
     $$

#### 3. Hàm mục tiêu đa mục tiêu theo thứ tự ưu tiên từ điển (Lexicographic Multi-Objective)

Thay vì cộng thẳng tiền VND với số kWh thiếu (dễ dẫn đến việc thuật toán hy sinh 1 kWh pin của khách chỉ để tiết kiệm vài trăm đồng tiền điện), báo cáo thiết kế sử dụng **tối ưu nhiều lượt theo thứ tự ưu tiên (hoặc chuẩn hóa trọng số chặt chẽ)**:

* **Ưu tiên 1 (Quan trọng nhất):** Tối thiểu hóa tổng lượng điện thiếu có trọng số ưu tiên:
  

  $$
  \min f_1 = \sum_{i} w_i \cdot \text{shortfall}_i
  $$

* **Ưu tiên 2 (Công bằng — Fairness):** Trong các nghiệm có cùng mức thiếu điện tối thiểu, cân bằng tỷ lệ đáp ứng năng lượng (Max-Min Fulfillment hoặc giảm độ lệch tỷ lệ hoàn thành) giữa các yêu cầu có cùng mức độ ưu tiên.

* **Ưu tiên 3 (Kinh tế — Chi phí điện):** Tối thiểu hóa tổng tiền điện theo biểu giá khung giờ:
  

  $$
  \min f_3 = \sum_{i, j, t} \text{price}_t \cdot p_{i,j,t} \cdot \Delta t
  $$

* **Ưu tiên 4 (Ổn định vận hành):** Giảm công suất đỉnh (`peak_power_kw`), hạn chế số lần đóng/ngắt cổng `ON_OFF_SWITCH` và hạn chế thay đổi các slot tương lai đã thông báo cho người dùng.

### 4.3. Vòng lặp MPC 15 phút, LLF, Validator và thiết kế Master-Worker

Mục này mô tả luồng lập lịch trong Báo cáo (Mục 16.3 & 17) cùng cách AI Engine hiện xử lý hết hạn và tải lớn.

1. **Chốt Snapshot & Gom sự kiện (Coalescing):** Gom các thao tác đặt/hủy mới trong cùng một cụm (`cluster_id`), gán mã `input_version`.

2. **Đóng băng lịch đã chạy (MPC Freeze):** Các khung giờ đã qua, khung 15 phút hiện tại đang cấp điện, hoặc lệnh phần cứng đã gửi xuống cổng sẽ bị **khóa cứng**. Chỉ các slot tương lai chưa khóa mới được đưa vào giải lại.

3. **Lọc Candidate (Pruning):** Chỉ tạo biến cho các cặp `(request, port, slot)` hợp lệ (đúng trạm, đúng đầu nối, trong giờ đỗ xe), giúp giảm 80–90% số biến thừa.

4. **Tạo nghiệm ban đầu cực nhanh bằng LLF (Least Laxity First):**

   * Tính độ gấp (Slack / Laxity) của từng xe:
     

     $$
     \text{Slack}_i = (\text{departure\_time}_i - t_{\text{now}}) - \frac{E_{\text{remaining}, i}}{P_{\text{feasible, max}, i}}
     $$

   * Xe nào có $\text{Slack}_i$ nhỏ nhất (sắp đến giờ lấy xe mà còn thiếu nhiều điện) được xếp cổng và cấp công suất trước dưới trần trạm/cụm. Nếu worker hết hạn, AI Engine dừng worker nếu còn chạy và chạy LLF trong tiến trình phục vụ API. Lịch qua Validator được trả với `FALLBACK` và `fallback_reason=TIME_BUDGET_EXHAUSTED`. Trong trường hợp hết hạn, API chỉ trả `ERROR` khi LLF thất bại hoặc lịch không qua kiểm tra.

5. **Phương án thiết kế Master – Worker khi tải lớn (10.000 active requests):**

   * Bản hiện tại chuyển sang LLF trên toàn cụm khi số request sau chuẩn hóa vượt `DECOMPOSE_THRESHOLD` (mặc định 250). Hai gạch đầu dòng tiếp theo mô tả phương án thiết kế trong Báo cáo.

   * Thay vì nhét 10.000 xe vào 1 bài toán MILP khổng lồ làm treo máy, **Master LP** chia ngân sách công suất $b(s, t)$ cho từng trạm $s$ ở từng slot $t$ sao cho $\sum_s b(s, t) \le \text{grid\_limit\_kw}$.

   * Các **Station Workers** chạy song song giải bài toán MILP/CP-SAT hoặc Min-Cost Flow cục bộ tại từng trạm dưới ngân sách $b(s, t)$, sau đó điều phối viên (Coordinator) cập nhật giá nghẽn (Congestion Price) trong vài vòng lặp cho đến khi hội tụ hoặc hết `time_budget`.

6. **Kiểm tra độc lập bằng Validator:**

   * Trước khi trả kết quả, một hàm `validate_schedule()` độc lập kiểm tra lại toàn bộ: Có slot nào 2 xe chung 1 cổng không? Tổng kW của trạm có vượt `station_power_kw` không? Tổng cụm có vượt `grid_limit_kw` không? Có xe nào bị cấp điện ngoài giờ đỗ không? Nếu vi phạm dù chỉ 1 điều kiện, chặn ngay và dùng nghiệm LLF an toàn.

### 4.4. Danh sách các Thuật toán Lập lịch Đa mục tiêu cần lập trình để Thử nghiệm & Benchmark

Theo ghi chú của bạn (*"Liệt kê thuật toán lập lịch đa mục tiêu thử nghiệm"* và *"Model chính + model phụ đang triển khai"*), nhóm AI cần viết một bộ khung (`BenchmarkRunner`) chạy cùng một đầu vào (`simulation_scenario`) qua **7 thuật toán lập lịch** sau để xuất bảng so sánh trong báo cáo:

| Nhóm | Tên thuật toán | Nguyên lý hoạt động (Cách code) | Vai trò trong báo cáo | 
| ----- | ----- | ----- | ----- | 
| **1. Model chính** | **MILP + MPC (hoặc CP-SAT + MPC)** | Giải bài toán quy hoạch nguyên thực hỗn hợp đa mục tiêu với biến nhị phân chọn cổng/bật-tắt và biến liên tục công suất, cập nhật cuốn chiếu mỗi 15 phút. | **Phương pháp đề xuất chính:** Tối ưu cả thiếu điện, công bằng, chi phí theo biểu giá và xử lý chính xác cổng `ON_OFF_SWITCH`. | 
| **2. Biến thể nhanh** | **LP + MPC (Linear Programming)** | Khi cổng đã cố định và toàn bộ các cổng đều điều khiển liên tục (`CONTINUOUS`), bỏ biến nguyên để giải quy hoạch tuyến tính thuần túy. | Chứng minh tốc độ giải cực nhanh ở các trạm sạc thông minh điều khiển dòng liên tục. | 
| **3. Dự phòng thời gian thực** | **LLF (Least Laxity First)** | Tại mỗi slot $t$, tính độ trễ dư $\text{Slack}_i$ của từng xe; ưu tiên cấp điện cho xe có $\text{Slack}_i$ nhỏ nhất trước trong giới hạn trần trạm/cụm. | Làm **Fallback** khi MILP quá thời gian (`timeout`) và tạo nghiệm khởi tạo ban đầu (Warm-start). | 
| **4. Baseline cơ sở 1** | **FCFS (First-Come, First-Served)** | Xe nào có `arrival_time` (hoặc `created_at`) sớm hơn thì được cấp tối đa công suất khả dụng trước cho đến khi chạm trần trạm/cụm. | Đường cơ sở truyền thống: Dễ hiểu nhưng gây thiệt thòi cho xe đến sau có deadline gấp và không tối ưu giá điện. | 
| **5. Baseline cơ sở 2** | **EDF (Earliest Deadline First)** | Ưu tiên xe có giờ rời đi (`departure_time`) sớm nhất trước, bất kể lượng điện cần sạc nhiều hay ít. | Đối조 với LLF và MILP về tỷ lệ giao xe đúng hạn (`on-time rate`). | 
| **6. Baseline cơ sở 3** | **Equal Share (Chia đều công suất)** | Tại mỗi slot $t$, chia đều ngân sách công suất của trạm/cụm cho tất cả các xe đang đỗ tại đó (có cắt ngọn theo `max_kw` của từng xe/cổng). | Đối chiếu về độ công bằng tức thời nhưng kém hiệu quả với xe sắp rời trạm hoặc cổng bật/tắt rời rạc. | 
| **7. Baseline cơ sở 4 & Đa mục tiêu phụ** | **ASAP (Sạc ngay không điều phối) & NSGA-II (Tiến hóa đa mục tiêu)** | \- **ASAP:** Cắm xe vào là sạc max công suất ngay lập tức (dùng để chỉ ra mức độ vượt trần `cap_violations` và chi phí đắt đỏ nếu không có EV ShareGrid).  \- **NSGA-II:** Thuật toán di truyền tìm biên Pareto giữa `(Shortfall, Cost, Peak Power)` cho các kịch bản cỡ nhỏ. | \- **ASAP:** Làm mốc tham chiếu "khi chưa có hệ thống điều phối".  \- **NSGA-II:** Minh họa trực quan đường cong đánh đổi (Trade-off Pareto Front) trong báo cáo nghiên cứu. | 

## 5. LỘ TRÌNH PHÂN CÔNG & CÁC BƯỚC TRIỂN KHAI TỪ CON SỐ 0 ĐẾN HOÀN THIỆN

Để nhóm không bị rối, hãy chia lộ trình làm việc thành **4 Giai đoạn (Sprints)** rõ ràng giữa 3 mảng: **Data**, **Backend + Web/App**, và **AI Engine**:

### Giai đoạn 1: Chốt Schema Database & Tạo bộ Data Chuẩn (Tuần 1)

* **Nhóm Data:**

  1. Tạo file `EV_ShareGrid_Seed_Data.xlsx` gồm 7 sheet danh mục gốc (`grid_cluster`, `vehicle_model`, `app_user`, `vehicle`, `charging_station`, `port`, `tariff_window`) tại 1 thành phố trước (ví dụ Đà Nẵng: 3 cụm, 15 trạm, 60 cổng, 10 mẫu xe thực tế, biểu giá TOU giả định theo khung giờ cao/thấp điểm).

  2. Viết script Python `generate_synthetic_data.py` để sinh dữ liệu mở rộng toàn quốc, tập 100.000 `app_user` và các kịch bản `charging_request` (`100`, `500`, `1000`, `10000` active requests) xuất ra `.csv`.

* **Nhóm Backend / Web:**

  1. Khởi tạo PostgreSQL + PostGIS (dùng Docker Compose là nhanh nhất).

  2. Chạy script SQL tạo 19 bảng theo đúng Phụ lục B và Phụ lục C của báo cáo.

* **Nhóm AI:**

  1. Định nghĩa chuẩn cấu trúc file `input_snapshot.json` và `output_schedule.json`.

  2. Viết bộ `Validator` độc lập bằng Python để kiểm tra mọi ràng buộc cứng.

### Giai đoạn 2: Xây dựng Lõi Thuật toán AI & Luồng Đặt lịch Cơ bản (Tuần 2)

* **Nhóm AI:**

  1. Cài đặt các thuật toán Baseline (`FCFS`, `EDF`, `Equal Share`, `LLF`, `ASAP`) bằng Python.

  2. Cài đặt bộ giải chính `LP` và `MILP` bằng thư viện **Google OR-Tools** (`ortools.linear_solver.pywraplp` hoặc `cp_model`).

  3. Bọc bộ giải vào một FastAPI server nhỏ có endpoint `POST /ai/optimize`.

* **Nhóm Backend & UI:**

  1. Hoàn thiện các màn hình UI của **USER**: Đăng nhập, Hồ sơ xe, Bản đồ trạm sạc, Form đặt lịch và Màn hình hiển thị kết quả lịch sạc (biểu đồ thanh 15 phút + hộp giải thích `explanation`).

  2. Nối luồng: UI gửi `POST /requests` -> Backend lưu DB -> Gọi `POST /ai/optimize` -> Lưu bảng `optimization_run`, `run_request`, `schedule` -> Trả kết quả về UI.

### Giai đoạn 3: Hoàn thiện Vòng lặp MPC (Tái lập lịch), Phân hệ HOST/ADMIN & Model Dự báo (Tuần 3)

* **Nhóm AI:**

  1. Bổ sung logic **MPC**: Khóa các slot đã thực thi, tính `remaining_kwh` cho các yêu cầu đang `CHARGING`, giải lại phần tương lai khi có xe mới đặt, xe hủy hoặc cổng lỗi.

  2. Huấn luyện **Model phụ (Forecast Model)**: Chạy `Hourly Mean` và `Random Forest` / `XGBoost` trên dữ liệu lịch sử do nhóm Data sinh ra, lưu kết quả vào bảng `demand_forecast`.

* **Nhóm Backend & UI:**

  1. Xây dựng màn hình **HOST** (Thêm trạm/cổng, nút báo bảo trì cổng kích hoạt tái tối ưu tự động).

  2. Xây dựng màn hình **ADMIN** (Duyệt trạm, cấu hình `grid_limit_kw`, cấu hình biểu giá `tariff_window`, xem thông báo đổi phiên bản lịch `version`).

### Giai đoạn 4: Mở rộng Tải 10.000 Users, Chạy Benchmark & Hoàn thiện Báo cáo (Tuần 4)

* **Nhóm AI & Data:**

  1. Cài đặt cơ chế phân rã **Master LP – Station Worker** để giải kịch bản `10.000 active requests`.

  2. Chạy toàn bộ **Ma trận 9 Case kiểm chứng độ bao phủ** (Trang 16 báo cáo: *New joins old, Old charging, Terminal excluded, Cross-cluster, Tie-break, Capacity conflict, Concurrent booking, Solver timeout, Schedule change*).

  3. Chạy Benchmark các thuật toán, lưu số liệu thực đo vào bảng `benchmark_result` và vẽ biểu đồ so sánh KPI.

* **Nhóm Backend & UI:**

  1. Tích hợp cơ chế bất đồng bộ (`outbox_event`, `optimization_job`, gom sự kiện theo `cluster_id`, khóa `pg_advisory_xact_lock` theo cụm khi commit lịch).

  2. Hiển thị Dashboard Benchmark & Mô phỏng trên trang ADMIN để phục vụ Demo trực tiếp.
