import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A3 – Biểu giá điện (`tariff_window`): khung giờ theo cụm/loại ngày, tự kiểm
/// tra phủ kín 24 h, không chồng, giá > 0.
class AdminTariffScreen extends StatefulWidget {
  const AdminTariffScreen({super.key});
  @override
  State<AdminTariffScreen> createState() => _AdminTariffScreenState();
}

class _Row {
  _Row(this.band, this.start, this.end, this.price);
  TariffBand band;
  String start;
  String end;
  String price;
}

class _AdminTariffScreenState extends State<AdminTariffScreen> {
  int _dayType = 0;
  String _cluster = '1 · Hải Châu – Trung tâm';
  late final List<_Row> _rows = [
    for (final w in Mock.tariff)
      _Row(w.band, _hhmm(w.start), _hhmm(w.end), vnInt(w.price)),
  ];

  static String _hhmm(double h) =>
      '${h.floor().toString().padLeft(2, '0')}:${((h % 1) * 60).round().toString().padLeft(2, '0')}';

  static double? _parse(String s) {
    final p = s.trim().split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null || h < 0 || h > 24 || m < 0 || m >= 60) {
      return null;
    }
    return h + m / 60;
  }

  /// Trả về (phủ kín?, chồng lấn?, giá hợp lệ?).
  (bool, bool, bool) _validate() {
    final spans = <(double, double)>[];
    for (final r in _rows) {
      final a = _parse(r.start), b = _parse(r.end);
      if (a == null || b == null || b <= a) return (false, true, true);
      spans.add((a, b));
    }
    spans.sort((x, y) => x.$1.compareTo(y.$1));
    var overlap = false, covered = spans.isNotEmpty && spans.first.$1 == 0;
    for (var i = 1; i < spans.length; i++) {
      if (spans[i].$1 < spans[i - 1].$2) overlap = true;
      if (spans[i].$1 > spans[i - 1].$2) covered = false;
    }
    if (spans.isEmpty || spans.last.$2 != 24) covered = false;
    final priceOk = _rows.every(
      (r) => (int.tryParse(r.price.replaceAll('.', '')) ?? 0) > 0,
    );
    return (covered, overlap, priceOk);
  }

  @override
  Widget build(BuildContext context) {
    final (covered, overlap, priceOk) = _validate();
    final dayName = const ['WEEKDAY', 'WEEKEND', 'HOLIDAY'][_dayType];
    return WebShell(
      portal: Portal.admin,
      route: '/admin/tariff',
      eyebrow: 'Quản trị · tariff_window',
      title: 'Biểu giá điện theo khung giờ',
      actions: [
        const WebBtn('Sao chép từ cụm khác'),
        WebBtn(
          'Lưu & áp dụng',
          primary: true,
          onTap: () => showSnack(
            context,
            covered && !overlap && priceOk
                ? 'Đã lưu biểu giá $dayName · ghi audit, áp dụng ở lần chạy kế tiếp'
                : 'Chưa lưu được: biểu giá phải phủ kín 24 h, không chồng lấn và giá > 0',
          ),
        ),
      ],
      children: [
        WebCard(
          children: [
            AutoGrid(
              minWidth: 170,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MutedText('Cụm', size: 12, weight: FontWeight.w700),
                    const Gap(6),
                    DropdownButtonFormField<String>(
                      initialValue: _cluster,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final c in const [
                          '1 · Hải Châu – Trung tâm',
                          '2 · Sơn Trà – Ven biển',
                        ])
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _cluster = v!),
                    ),
                  ],
                ),
                const WebField('Hiệu lực từ', '01/01/2026'),
                const WebField('Đến', '31/12/2026'),
                const WebField('Nguồn tham chiếu', 'EVN_TOU_2026'),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 360,
                child: Segmented(
                  items: const ['WEEKDAY', 'WEEKEND', 'HOLIDAY'],
                  selected: _dayType,
                  onChanged: (i) => setState(() => _dayType = i),
                ),
              ),
            ),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                const LegendDot(AppColors.offPeak, 'OFF_PEAK'),
                const LegendDot(AppColors.normal, 'NORMAL'),
                const LegendDot(AppColors.peak, 'PEAK'),
                MutedText(
                  'đ/kWh · số liệu mẫu, cần đối chiếu biểu giá chính thức',
                  size: 12,
                ),
              ],
            ),
            const TariffStepChart(height: 170, nowHour: null),
          ],
        ),
        AutoGrid(
          minWidth: 420,
          gap: 20,
          children: [
            WebCard(
              title: 'Các khung giờ · $dayName',
              trailing: WebBtn(
                '+ Thêm khung',
                onTap: () => setState(
                  () => _rows.add(_Row(TariffBand.normal, '', '', '2.400')),
                ),
              ),
              children: [
                SimpleTable(
                  columns: const [
                    '#',
                    'Band',
                    'Bắt đầu',
                    'Kết thúc',
                    'Giá đ/kWh',
                  ],
                  flex: const [2, 6, 5, 5, 6],
                  rows: [
                    for (var i = 0; i < _rows.length; i++)
                      [
                        cellText('${i + 1}'),
                        _bandPill(_rows[i].band),
                        _cellInput(
                          _rows[i].start,
                          'Bắt đầu khung ${i + 1}',
                          (v) => setState(() => _rows[i].start = v),
                        ),
                        _cellInput(
                          _rows[i].end,
                          'Kết thúc khung ${i + 1}',
                          (v) => setState(() => _rows[i].end = v),
                        ),
                        _cellInput(
                          _rows[i].price,
                          'Giá khung ${i + 1}',
                          (v) => setState(() => _rows[i].price = v),
                        ),
                      ],
                  ],
                ),
              ],
            ),
            WebCard(
              title: 'Kiểm tra tự động',
              children: [
                Column(
                  children: [
                    CheckLine(
                      covered ? CheckState.ok : CheckState.fail,
                      dayName,
                      covered
                          ? 'phủ kín 24/24 giờ, không có khoảng hở.'
                          : 'chưa phủ kín 00:00–24:00, còn khoảng hở.',
                    ),
                    CheckLine(
                      overlap ? CheckState.fail : CheckState.ok,
                      'Chồng lấn',
                      overlap
                          ? 'có khung chồng lên nhau hoặc giờ không hợp lệ.'
                          : 'không có khung chồng lấn.',
                    ),
                    CheckLine(
                      priceOk ? CheckState.ok : CheckState.fail,
                      'Đơn giá',
                      priceOk
                          ? 'mọi đơn giá > 0; ngày hiệu lực hợp lệ.'
                          : 'có đơn giá trống hoặc ≤ 0.',
                    ),
                    const CheckLine(
                      CheckState.warn,
                      'WEEKEND (bản nháp)',
                      'hở khung 22:00–24:00. Không thể lưu cho tới khi bổ sung.',
                    ),
                  ],
                ),
                const InfoNote(
                  'Bộ lập lịch dùng giá theo từng slot 15 phút để dời phần sạc linh hoạt sang khung rẻ hơn khi vẫn kịp giờ lấy xe. Giá ghi đè của trạm (nếu có) được ưu tiên. Thay đổi biểu giá được ghi audit và áp dụng ở lần chạy kế tiếp.',
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _bandPill(TariffBand b) => switch (b) {
    TariffBand.offPeak => const Pill(
      'OFF_PEAK',
      bg: Color(0xFFE8EEF9),
      fg: Color(0xFF2F55A4),
      radius: 6,
    ),
    TariffBand.normal => const Pill(
      'NORMAL',
      bg: Color(0xFFE8EEF9),
      fg: AppColors.blue,
      radius: 6,
    ),
    TariffBand.peak => const Pill(
      'PEAK',
      bg: AppColors.warningBg,
      fg: AppColors.warning,
      radius: 6,
    ),
  };

  Widget _cellInput(String v, String label, ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          label: label,
          child: TextFormField(
            initialValue: v,
            onChanged: onChanged,
            style: AppFonts.body(size: 13, weight: FontWeight.w600),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      );
}
