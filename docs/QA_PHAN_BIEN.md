# Hỏi đáp phản biện về điều phối sạc

## Mức giảm chi phí thay đổi thế nào khi lịch phải liền mạch?

Với **100 yêu cầu mô phỏng** và giá TOU EVN, MILP_MPC, LLF và ASAP đều có chi phí **8.276.432,26 đ**, đạt **94% đúng hạn** và thiếu **17,5719 kWh** ở độ chính xác hiển thị. Đỉnh của MILP thấp hơn ASAP **92,5612 kW**.

Với **500 yêu cầu mô phỏng**, lịch gộp chạy LLF ở cụm 1 và MILP_MPC ở cụm 2. So với ASAP, phương án này có chi phí TOU cao hơn **16,29%**, giảm điện thiếu từ **4.777,7031** xuống **2.549,0329 kWh** và giảm vi phạm trần từ **53** xuống **0**. Cả hai lịch đều có 0 lần bật lại trong bản đo mới. [Số liệu benchmark](../ai_engine/benchmark_real.json) · [Bảng tổng hợp](../README.md#benchmark-thực-đo)

**Điểm cần chốt khi phản biện.** Biên chi phí **0,2546%–0,4846%** ở mốc 100 thuộc lần đo biểu giá mô phỏng cũ. Ở lần đo TOU EVN mới, chênh chi phí so với ASAP ở mốc này là **0%**. Riêng cụm 2 ở mốc 500, MILP giảm chi phí **0,3055%** so với LLF, từ **0,4817%** ở bản đo đã công bố trước đó. Tỷ lệ đúng hạn của cụm 2 trong lượt mới là **63,59%** với MILP và **66,02%** với LLF. Khi trình bày, đặt chi phí cạnh lượng điện cấp, điện thiếu và vi phạm trần.

Trần công suất trạm và cụm là ràng buộc cứng cho lịch điều phối. Bộ giải giảm điện thiếu có trọng số rồi tối đa hóa mức đáp ứng thấp nhất theo từng nhóm ưu tiên. Chi phí được tối ưu trên phần nghiệm còn lại.

## Vì sao sạc liền mạch?

Mỗi yêu cầu nhận một khối sạc liền mạch trên tối đa một cổng. MILP có thể dịch thời điểm bắt đầu để tận dụng giờ giá thấp nếu xe còn đủ thời gian đỗ. Trong khối sạc, cổng `CONTINUOUS` cho phép điều chỉnh công suất trong dải của cổng, còn cổng `ON_OFF_SWITCH` cấp đúng công suất định mức khi bật. LLF ưu tiên giữ mức công suất sàn cho các xe đang sạc. Nếu không đủ công suất hoặc thời gian để hoàn thành khối, lịch ghi phần điện thiếu.

Mục tiêu vận hành là tránh các lần ngừng rồi bật lại giữa phiên và giảm thao tác đóng cắt contactor. Phần demo kiểm tra tính liền mạch của lịch mô phỏng. Tuổi thọ pin, độ bền contactor và lệnh điều khiển OCPP trên thiết bị cần được kiểm chứng riêng.

## Hai điểm cần nói rõ khi đối chiếu PDF

1. Ví dụ ở trang 20 xếp xe A vào 17:15 và 17:45. Bản chạy demo xếp lại các slot để mỗi xe nhận một khối liền mạch. Ca kiểm chuẩn giữ chi phí **5.500 đ**, 0 kWh thiếu và không vượt trần 3 kW.
2. Trang 19 mô tả Master LP và worker theo trạm, còn trang 23 nêu kế hoạch kiểm thử ở mốc 10.000. Benchmark hiện tại đo các thuật toán nhanh ở mốc 10.000, với LLF làm đường xử lý khi cụm vượt 250 yêu cầu. Các số đo này mô tả bản demo hiện tại. [Báo cáo PDF](EV_ShareGrid_Bao_cao_tong_the_10k.pdf)

## Có thể cải thiện gì sau cuộc thi?

- Ràng buộc liền mạch đã loại lượt bật lại giữa phiên. Hạng đóng/ngắt ở tầng ổn định vẫn được giữ để tính các lần chuyển trạng thái của cổng. Có thể đo lại tác động của hạng này và chuẩn hóa đơn vị trước khi chọn trọng số.
- Dùng nhóm tiến trình worker khởi tạo sẵn thay cho việc gọi `subprocess.Popen` cho từng yêu cầu để giảm chi phí nạp Python và OR-Tools. Giữ cách ly bộ nhớ và thay worker khi vượt thời hạn.
