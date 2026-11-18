# Ánh xạ POST /ai/optimize

Đối chiếu DDL trong *EV ShareGrid – Phân công và thiết kế dữ liệu*. BE đọc các bảng tại cùng một snapshot, giữ thời gian ISO-8601 có offset +07:00. Các ID trong response là chuỗi. ID A–D trong mẫu chỉ là mã fixture; khi ghi DB phải ánh xạ về request_id BIGINT có thật.

## DB → request

Trong dòng có nhiều trường, thứ tự các cột tương ứng từ trái sang phải.

| Trường JSON | Bảng.cột hoặc cách lấy |
|---|---|
| cluster_id, grid_limit_kw | grid_cluster.cluster_id, grid_cluster.grid_limit_kw |
| input_version | BE cấp phiên bản snapshot để đối chiếu khi ghi lịch; DDL chưa có cột riêng. Lưu trong optimization_run.input_json. |
| snapshot_time | Thời điểm chốt dữ liệu do BE cấp; lưu trong input_json. Khác started_at của run. |
| slot_minutes | Cấu hình 15 phút; ghi optimization_run.slot_minutes. |
| horizon_slots, time_budget_ms | Cấu hình BE, đơn vị slot và ms; lưu trong input_json. |
| stations[] | charging_station theo cluster_id; BE lọc trạm ACTIVE. |
| stations[].station_id, station_power_kw | charging_station.station_id, charging_station.station_power_kw |
| stations[].open_time, close_time | charging_station.open_time, close_time là TIME. BE ghép ngày theo grid_cluster.timezone; đóng sau nửa đêm dùng ngày kế. Với is_24h, gửi khoảng bao phủ cả horizon. |
| stations[].ports[] | port theo port.station_id |
| ports[].port_id, connector_type | port.port_id, port.connector_type |
| ports[].control_type | port.control_type: SMART_CONTINUOUS → CONTINUOUS; ON_OFF_SWITCH giữ nguyên. |
| ports[].min_power_kw, max_power_kw | port.min_power_kw, port.max_power_kw; ON_OFF_SWITCH gửi min = max = công suất bật. |
| ports[].status | port.status: AVAILABLE → ACTIVE; OCCUPIED → ACTIVE **kèm phiên đang sạc và locked_port_id**. Nếu thiếu phiên, BE phải đối soát trước khi cho cổng tham gia. MAINTENANCE/OFFLINE giữ nguyên. |
| tariffs[].start_time, end_time, price_vnd_kwh | tariff_window.start_time, end_time, price_vnd_kwh. Lọc theo cluster_id, day_type, valid_from/valid_to cho từng ngày; xuất các khoảng không chồng lấn phủ horizon. |
| requests[].request_id, station_id | charging_request.request_id, charging_request.station_id; ràng buộc cùng cluster_id. |
| requests[].connector_type | DDL chưa chụp đầu nối trên request. Join charging_request.vehicle_id → vehicle.model_id → vehicle_model.connector_type. |
| requests[].vehicle_max_kw, battery_capacity_kwh | charging_request.max_kw_snapshot, charging_request.battery_kwh_snapshot. Dung lượng pin là trường API tùy chọn. |
| requests[].arrival_time, departure_time | charging_request.arrival_time, charging_request.departure_time; thời điểm rời không thuộc cửa sổ sạc. |
| requests[].current_soc_pct | SOC tại snapshot, tùy chọn. Có thể dùng charging_request.soc_now lúc bắt đầu phiên. Sau khi sạc cần SOC cập nhật; nếu không có số đo/ước tính tin cậy thì bỏ trường. |
| requests[].energy_needed_kwh | charging_request.energy_needed_kwh là cột GENERATED: ((soc_target − soc_now)/100 × battery_kwh_snapshot) / eta. Đây là nhu cầu **toàn phiên**. |
| requests[].energy_delivered_kwh | charging_session.energy_kwh của cùng request tại snapshot; chưa có phiên thì 0. Engine tự tính remaining = max(0, needed − delivered). |
| requests[].priority_weight, status | charging_request.priority_weight, charging_request.status |
| requests[].locked_port_id | charging_session.port_id của phiên ACTIVE; chưa khóa thì null. |
| requests[].previous_port_id | Tùy chọn. Truy từ phiên bản lịch trước khi chuyển cổng. charging_request chưa có cột này. |
| previous_schedule[].request_id, port_id, slot_start, power_kw | schedule.request_id, port_id, slot_start, power_kw của lịch đã công bố, cùng cụm, version phù hợp và is_active=true. Nếu gửi slot đang chạy, số điện đã nạp phải chốt nhất quán với việc engine tính đủ 0,25 giờ cho dòng freeze. |

## Response → DB

BE tạo optimization_run.run_id rồi dùng khóa này cho toàn bộ run_request và schedule. Lưu run, kết quả xe và các slot trong cùng giao dịch. Dù xe không có dòng schedule, vẫn lưu run_request.

| Trường JSON | Đích ghi và lưu ý |
|---|---|
| status, algorithm | optimization_run.status, optimization_run.algorithm. Lưu thuật toán thực tế, kể cả LLF khi FALLBACK. Nếu ERROR và algorithm=null, cột algorithm hiện NOT NULL: cần quy ước BE hoặc migration, không suy diễn tên solver. |
| solve_ms | optimization_run.solve_ms (INTEGER); thống nhất làm tròn mili giây khi ghi. |
| kpi.total_shortfall_kwh, total_cost_vnd, peak_power_kw | optimization_run.kpi_json với đúng tên khóa; đơn vị kWh, VND, kW. |
| kpi.on_time_rate, cap_violations, fairness | optimization_run.kpi_json với đúng tên khóa; tỷ lệ 0–1, số vi phạm, chỉ số Jain 0–1. Khi status=ERROR, KPI giữ chỗ không dùng để thống kê. |
| request_results[].request_id | run_request.request_id, khóa cùng run_id. |
| request_results[].allocated_kwh, shortfall_kwh | run_request.allocated_kwh, run_request.shortfall_kwh; điện phân bổ thêm và phần thiếu của lần chạy. |
| request_results[].expected_soc | run_request.expected_soc (%), xem cách diễn giải dưới đây. DDL NOT NULL; nếu nhận null từ kết quả cũ cần xử lý riêng, không tự đổi thành 0. |
| request_results[].estimated_cost_vnd, explanation | run_request.estimated_cost_vnd, run_request.explanation; lưu nguyên văn tiếng Việt. |
| schedules[].request_id, port_id, slot_start, power_kw | schedule.request_id, port_id, slot_start, power_kw. Chỉ lưu dòng công suất dương. BE cấp run_id, version và is_active. |

**Nhãn SOC trên FE.** Response chỉ có expected_soc. Nếu request gửi đủ current_soc_pct và battery_capacity_kwh, engine tính min(100, current_soc_pct + 100 × allocated_kwh / battery_capacity_kwh), giả định hiệu suất nạp thêm 100%. Nếu thiếu một trong hai, hiển thị **“Đáp ứng nhu cầu (%)”**: min(100, 100 × (energy_delivered_kwh + allocated_kwh) / energy_needed_kwh); nhu cầu bằng 0 thì trả 100%. Giữ snapshot input để FE/BE biết công thức nào đã dùng.
