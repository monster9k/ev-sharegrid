import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A6 – Dự báo nhu cầu (model phụ, pred_arrivals) & nhật ký kiểm toán.
class AdminForecastScreen extends StatefulWidget {
  const AdminForecastScreen({super.key});
  @override
  State<AdminForecastScreen> createState() => _AdminForecastScreenState();
}

class _AdminForecastScreenState extends State<AdminForecastScreen> {
  String _entity = 'Tất cả';
  String _actor = 'Tất cả';

  static const _audit = [
    (
      '18/11 09:02',
      'admin@sharegrid.vn',
      'grid_cluster #1',
      'grid_limit_kw',
      '500 → 550',
      'Áp dụng ở run kế tiếp',
      'ADMIN',
    ),
    (
      '18/11 08:40',
      'host1@sharegrid.vn',
      'port #1002 (P2)',
      'status',
      'ACTIVE → MAINTENANCE',
      'RE_OPTIMIZE · run #1045',
      'HOST',
    ),
    (
      '18/11 08:12',
      'admin@sharegrid.vn',
      'tariff_window cụm 2',
      'WEEKEND (nháp)',
      '—',
      'Bị chặn: hở 22–24h',
      'ADMIN',
    ),
    (
      '17/11 21:40',
      'host1@sharegrid.vn',
      'charging_station',
      'tạo mới',
      '— → PENDING',
      'Chờ duyệt',
      'HOST',
    ),
    (
      '17/11 10:05',
      'admin@sharegrid.vn',
      'charging_station #11',
      'verified, status',
      'false, PENDING → true, ACTIVE',
      'Nhận đặt lịch',
      'ADMIN',
    ),
  ];

  Widget _effect(String e) {
    if (e.startsWith('Áp dụng')) {
      return Pill(e, bg: const Color(0xFFE8EEF9), fg: const Color(0xFF2F55A4));
    }
    if (e.startsWith('RE_OPT')) return Pill.warning(e);
    if (e.startsWith('Bị chặn')) return Pill.danger(e);
    if (e.startsWith('Nhận')) return Pill.success(e);
    return Pill.neutral(e);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _audit.where(
      (a) =>
          (_entity == 'Tất cả' || a.$3.startsWith(_entity)) &&
          (_actor == 'Tất cả' || a.$7 == _actor),
    );
    final hours = [for (var h = 0; h < 24; h++) '${h}h'];
    final chart = WebCard(
      title: 'Số lượt đặt sạc theo giờ · cụm Hải Châu',
      children: [
        const Wrap(
          spacing: 14,
          children: [
            LegendDot(AppColors.ink, 'Đã đo'),
            LegendDot(AppColors.blue, 'Dự báo (XGBoost v1.2)', dashed: true),
          ],
        ),
        LineChart(
          series: [
            const LineSeries(
              Mock.arrivalsMeasured,
              color: AppColors.ink,
              dots: true,
            ),
            LineSeries(
              [Mock.arrivalsMeasured.last, ...Mock.arrivalsForecast.skip(1)],
              color: AppColors.blue,
              dashed: true,
              startIndex: Mock.arrivalsMeasured.length - 1,
            ),
          ],
          xLabels: hours,
          maxY: 80,
          yTicks: const [0, 20, 40, 60, 80],
          dividerAt: 9,
          dividerLabel: 'Bây giờ',
          height: 230,
          semantics:
              'Số lượt đặt theo giờ: đã đo đến 9h, dự báo đến 24h, đỉnh 70 lượt lúc 19h',
        ),
        const InfoNote(
          'Model phụ chỉ dự báo số lượt yêu cầu mỗi giờ (pred_arrivals), không dự báo kW và không tự cộng vào công suất của bộ lập lịch. Dùng để cảnh báo sớm và chuẩn bị vận hành.',
        ),
      ],
    );
    final models = WebCard(
      title: 'Mô hình dự báo',
      children: [
        SimpleTable(
          columns: const ['Model', 'MAE', 'RMSE'],
          flex: const [10, 3, 3],
          rows: [
            [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cellText('HOURLY_MEAN v1'),
                  MutedText('baseline', size: 11),
                ],
              ),
              cellText('6,8'),
              cellText('9,4'),
            ],
            [cellText('RANDOM_FOREST v1.1'), cellText('5,1'), cellText('7,2')],
            [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  cellText('XGBOOST v1.2', bold: true),
                  Pill.blue('đang dùng'),
                ],
              ),
              cellText('4,6', bold: true),
              cellText('6,5', bold: true),
            ],
          ],
        ),
        MutedText(
          'Huấn luyện đến 30/11 · tách train/test theo thời gian (không rò rỉ tương lai) · đặc trưng: giờ, thứ, ngày lễ, lag. Sai số là số minh hoạ.',
          size: 12,
        ),
        const InfoNote(
          'Cảnh báo sớm: dự báo 63–70 lượt/giờ lúc 17–19h tại Hải Châu, gần mức đã chạm trần hôm qua.',
          warn: true,
        ),
      ],
    );

    return WebShell(
      portal: Portal.admin,
      route: '/admin/forecast',
      eyebrow: 'Quản trị · demand_forecast & audit',
      title: 'Dự báo nhu cầu & nhật ký',
      actions: [
        const Pill(
          'Dữ liệu mô phỏng',
          bg: AppColors.border,
          fg: AppColors.muted,
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 900
              ? Column(children: [chart, const Gap(20), models])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: chart),
                    const Gap(20),
                    Expanded(child: models),
                  ],
                ),
        ),
        WebCard(
          title: 'Nhật ký kiểm toán (audit)',
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _Filter('Đối tượng', _entity, const [
                  'Tất cả',
                  'grid_cluster',
                  'tariff_window',
                  'charging_station',
                  'port',
                ], (v) => setState(() => _entity = v)),
                _Filter('Người thao tác', _actor, const [
                  'Tất cả',
                  'ADMIN',
                  'HOST',
                ], (v) => setState(() => _actor = v)),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1000,
                child: SimpleTable(
                  columns: const [
                    'Thời điểm',
                    'Người thao tác',
                    'Đối tượng',
                    'Trường',
                    'Cũ → Mới',
                    'Ảnh hưởng',
                  ],
                  flex: const [6, 10, 10, 8, 12, 12],
                  rows: [
                    for (final a in rows)
                      [
                        cellText(a.$1),
                        cellText(a.$2, size: 12),
                        cellText(a.$3, size: 12, color: AppColors.blue800),
                        cellText(a.$4, size: 12),
                        cellText(a.$5, bold: true, size: 12),
                        _effect(a.$6),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter(this.label, this.value, this.items, this.onChanged);
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      MutedText(label, size: 12, weight: FontWeight.w700),
      const Gap(8),
      SizedBox(
        width: 190,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          isExpanded: true,
          items: [
            for (final i in items) DropdownMenuItem(value: i, child: Text(i)),
          ],
          onChanged: (v) => onChanged(v!),
        ),
      ),
    ],
  );
}
