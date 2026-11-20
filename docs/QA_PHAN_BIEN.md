# Hỏi đáp phản biện về điều phối sạc

## Mức giảm chi phí thay đổi thế nào khi dùng biểu giá EVN?

Trong kịch bản **mô phỏng 100 yêu cầu** với TOU EVN hạ áp, MILP_MPC, LLF và ASAP đều có chi phí **8.276.432,26 đ**, đạt **94% đúng hạn** và thiếu **17,5719 kWh** ở độ chính xác hiển thị. Đỉnh công suất MILP thấp hơn LLF **3,0176 kW** và thấp hơn ASAP **92,5612 kW**. [Số liệu benchmark](../ai_engine/benchmark_real.json) · [Bảng tổng hợp](../README.md#benchmark-thực-đo)

**Điểm cần chốt khi phản biện.** Biên giảm **0,2546%–0,4846%** ở mốc 100 là số của biểu giá mô phỏng cũ. Ở biểu giá EVN, chênh chi phí ở mốc này là **0%**. Tại mốc 500, riêng cụm 2 dùng MILP_MPC giảm chi phí **0,4817%** so với LLF và ghi nhận ít điện thiếu hơn.

Trần công suất trạm và cụm là ràng buộc cứng. Trong tập nghiệm khả thi, bộ giải giảm điện thiếu có trọng số rồi tối đa hóa mức đáp ứng thấp nhất trong từng nhóm, theo thứ tự ưu tiên. Chi phí điện được tối ưu trong phần không gian nghiệm còn lại sau các mục tiêu đó.

Trong kịch bản **mô phỏng 500 yêu cầu**, phương án điều phối dùng LLF ở cụm 1 và MILP_MPC ở cụm 2, ghi **0 vi phạm trần công suất**. ASAP ghi **53 vi phạm** trên hai cụm ở mỗi biểu giá. Chỉ số này đếm các lần vượt trần trạm hoặc cụm theo slot 15 phút. [Số liệu benchmark](../ai_engine/benchmark_real.json)

## Có thể cải thiện gì sau cuộc thi?

- Chuẩn hóa công suất đỉnh (kW) và số lần đóng/ngắt về cùng thang đo trước khi gán trọng số ở tầng ổn định lịch. Đo lại chi phí, đỉnh tải và số lần đóng/ngắt để chọn trọng số.
- Dùng nhóm tiến trình worker khởi tạo sẵn thay cho việc gọi `subprocess.Popen` cho từng yêu cầu để giảm chi phí nạp Python và OR-Tools. Giữ cách ly bộ nhớ và thay worker khi vượt thời hạn.
