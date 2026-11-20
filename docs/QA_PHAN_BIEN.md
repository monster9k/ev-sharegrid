# Hỏi đáp phản biện về điều phối sạc

## Vì sao chi phí giảm khoảng 0,25%–0,48%?

Trong kịch bản **mô phỏng 100 yêu cầu** với biểu giá TOU giả định, MILP_MPC giảm chi phí **0,2546% so với LLF** và **0,4846% so với ASAP**. Tỷ lệ đúng hạn và điện thiếu bằng nhau ở độ chính xác hiển thị trong báo cáo. [Số liệu benchmark](../ai_engine/benchmark_real.json) · [Bảng tổng hợp](../README.md#benchmark-thực-đo)

Trần công suất trạm và cụm là ràng buộc cứng. Trong tập nghiệm khả thi, bộ giải giảm điện thiếu có trọng số rồi tối đa hóa mức đáp ứng thấp nhất trong từng nhóm, theo thứ tự ưu tiên. Chi phí điện được tối ưu trong phần không gian nghiệm còn lại sau các mục tiêu đó.

Trong kịch bản **mô phỏng 500 yêu cầu**, phương án điều phối dùng LLF ở cụm 1 và MILP_MPC ở cụm 2, ghi **0 vi phạm trần công suất**. ASAP ghi **53 vi phạm** trên hai cụm ở mỗi biểu giá. Chỉ số này đếm các lần vượt trần trạm hoặc cụm theo slot 15 phút. [Số liệu benchmark](../ai_engine/benchmark_real.json)

## Có thể cải thiện gì sau cuộc thi?

- Chuẩn hóa công suất đỉnh (kW) và số lần đóng/ngắt về cùng thang đo trước khi gán trọng số ở tầng ổn định lịch. Đo lại chi phí, đỉnh tải và số lần đóng/ngắt để chọn trọng số.
- Dùng nhóm tiến trình worker khởi tạo sẵn thay cho việc gọi `subprocess.Popen` cho từng yêu cầu để giảm chi phí nạp Python và OR-Tools. Giữ cách ly bộ nhớ và thay worker khi vượt thời hạn.
