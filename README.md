# EV ShareGrid

Nền tảng điều phối sạc xe điện và tối ưu lịch sạc cho TP. Đà Nẵng (Smart Campus 2026 – ISSCEI).
App Flutter gồm 3 phân hệ: **USER** (app người dùng), **HOST** (cổng chủ trạm), **ADMIN** (quản trị).
Giai đoạn hiện tại: giao diện chạy với dữ liệu mẫu (nhãn *Mô phỏng*), chưa nối backend/AI Engine.

## Chạy local

```bash
flutter pub get
flutter run -d chrome
```

Đường dẫn chính (web):

| Đường dẫn | Màn |
|---|---|
| `/` | Onboarding → Đăng nhập → Trang chủ |
| `/home`, `/map`, `/station`, `/booking`, `/schedule`, `/sessions`, `/notifications`, `/garage`, `/profile` | App USER |
| `/host/stations`, `/host/ports`, `/host/schedule` | Cổng chủ trạm |
| `/admin/clusters`, `/admin/review`, `/admin/tariff`, `/admin/solver`, `/admin/benchmark`, `/admin/forecast` | Quản trị |

## Kiểm tra

```bash
dart format lib test
flutter analyze
flutter test
```

## Build & deploy (Firebase Hosting)

```bash
flutter build web --release
firebase deploy --only hosting
```

CI/CD: `.github/workflows/pr-check.yml` kiểm tra quy ước + format/analyze/test cho mọi PR; `.github/workflows/deploy-hosting.yml` build và deploy khi có commit lên `main` (cần secret `FIREBASE_SERVICE_ACCOUNT` trên GitHub).

## Tài liệu

- `CLAUDE.md` – tổng hợp nghiệp vụ, phạm vi, thuật toán, dữ liệu.
- `AGENTS.md`, `git.md` – cấu trúc code và quy trình Git.
- `docs/source/` – báo cáo thiết kế 10k và hướng dẫn triển khai (nguồn sự thật).
