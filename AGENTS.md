# Hướng dẫn cho AI agent

App Flutter (Web/Android/iOS) cho EV ShareGrid – điều phối sạc xe điện TP. Đà Nẵng. Bản web deploy lên Firebase Hosting. Nghiệp vụ, phạm vi, dữ liệu và thuật toán: xem **CLAUDE.md**. Chạy và deploy: xem **README.md**.

## Cấu trúc thư mục

```
lib/
  main.dart                 # khởi tạo app + router
  router.dart               # go_router: /, /login, /home, …, /host/*, /admin/*
  theme.dart                # màu (Blue 600, Sky 200/100, Navy…), font, kiểu glass
  data/
    models.dart             # model dữ liệu (trạm, cổng, xe, lịch, run…)
    mock_data.dart          # dữ liệu mẫu có nhãn Mô phỏng (chưa nối backend)
  widgets/
    common.dart             # nút, pill, thẻ, KPI, section…
    glass.dart              # thanh tab nổi kiểu liquid glass, thanh hành động đáy
    charts.dart             # biểu đồ CustomPainter (biểu giá, Gantt 15', đường, cột)
    danang_map.dart         # bản đồ Đà Nẵng vẽ tay kiểu Google Maps
    mobile_frame.dart       # khung điện thoại khi mở app USER trên màn rộng
    web_shell.dart          # khung sidebar cho cổng HOST và ADMIN
  screens/
    user/                   # 13 màn app người dùng (U1–U7)
    host/                   # 3 trang cổng chủ trạm (H1–H4)
    admin/                  # 6 trang quản trị (A1–A6)
test/                       # widget test
docs/                       # tài liệu nguồn, thiết kế, file xem trước màu
```

## Quy tắc

- Mọi màn bám theo canvas thiết kế (trang Tiếng Việt) và CLAUDE.md. Không đưa điện mặt trời / tải thiết yếu / thời tiết vào UI.
- Số liệu năng lượng, benchmark, KPI là dữ liệu mẫu: luôn có nhãn **Mô phỏng** hoặc **Minh hoạ**.
- Không đặt chữ xanh lên nền Sky 200 (`#C3E7F5`); chữ trên Sky 200 dùng `#0B3550`.

## Git

Trước mọi thao tác git, đọc và làm đúng **git.md** mục "7. Rule cho AI":

- Làm trên nhánh `feature/`, `fix/`, `chore/`, `docs/`, `refactor/` – không commit thẳng `main`/`develop`.
- Commit dạng `<type>(<scope>): <mô tả>` (tiếng Việt hoặc tiếng Anh). Mỗi màn hoàn chỉnh = 1 commit; xong một nhóm chức năng thì sang nhánh mới.
- Không ghi công cho AI (không `Co-Authored-By: <AI>`, không "Generated with …", không "🤖").
- Trước khi commit: `dart format lib test`, `flutter analyze`, `flutter test` đều sạch.
- Được push nhánh và tạo PR vào `develop`; không dùng `--no-verify`, không force push (chỉ `--force-with-lease` trên nhánh của mình).
