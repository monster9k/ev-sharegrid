import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';

/// H4 – Lịch đặt chỗ & doanh thu: Gantt cổng theo slot 15 phút, tổng công
/// suất trạm so với trần, phiên gần đây.
class HostScheduleScreen extends StatefulWidget {
  const HostScheduleScreen({super.key});
  @override
  State<HostScheduleScreen> createState() => _HostScheduleScreenState();
}

class _HostScheduleScreenState extends State<HostScheduleScreen> {
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    return WebShell(
      portal: Portal.host,
      route: '/host/schedule',
      eyebrow: 'Trạm ShareGrid Nguyễn Văn Linh ▾ · Thứ Sáu 05/12/2026',
      title: 'Lịch đặt & doanh thu',
      actions: [
        SizedBox(
          width: 300,
          child: Segmented(
            items: const ['Hôm nay', '7 ngày', '30 ngày'],
            selected: _range,
            onChanged: (i) => setState(() => _range = i),
          ),
        ),
      ],
      children: [
        const AutoGrid(
          minWidth: 170,
          children: [
            WebKpi('Điện năng đã cấp', '486 kWh', note: '41 phiên'),
            WebKpi('Phí dịch vụ', '410.000 đ', note: '10.000 đ/phiên'),
            WebKpi('Tiền điện', '1.164.000 đ', note: 'Theo biểu giá cụm'),
            WebKpi('Sử dụng cổng', '62%', note: 'Slot có xe / slot mở'),
            WebKpi(
              'Đỉnh công suất trạm',
              '40 / 40 kW',
              note: 'Chạm trần lúc 08:30 & 13:00',
            ),
          ],
        ),
        WebCard(
          title: 'Lịch sử dụng cổng theo slot 15 phút',
          trailing: const SimTag(),
          children: [
            const Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                LegendDot(AppColors.blue800, 'Đã chạy (khóa)'),
                LegendDot(AppColors.blue, 'Đã xếp lịch'),
                LegendDot(AppColors.warning, 'Có điện thiếu'),
                LegendDot(Color(0xFFF0C48E), 'Bảo trì'),
                LegendDot(AppColors.red, 'Bây giờ 09:15'),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 900,
                child: PortGantt(
                  rows: [for (final p in Mock.nvlPorts) p.code],
                  blocks: Mock.hostGantt,
                ),
              ),
            ),
          ],
        ),
        AutoGrid(
          minWidth: 420,
          gap: 20,
          children: [
            WebCard(
              title: 'Tổng công suất trạm',
              children: [
                const Wrap(
                  spacing: 14,
                  children: [
                    LegendDot(AppColors.blue, 'Đã xếp (kW)'),
                    LegendDot(AppColors.red, 'Trần 40 kW', dashed: true),
                  ],
                ),
                BarChart(
                  values: Mock.stationLoad,
                  xLabels: [for (var h = 6; h <= 22; h++) '${h}h'],
                  maxY: 44,
                  cap: 40,
                  capLabel: 'Trần 40 kW',
                  showYAxis: true,
                  height: 200,
                  color: AppColors.blue,
                  colorFor: (i, v) =>
                      v >= 40 ? AppColors.blue800 : AppColors.blue,
                  semantics:
                      'Tổng công suất trạm theo giờ, chạm trần 40 kW lúc 8h và 13h',
                ),
              ],
            ),
            WebCard(
              title: 'Phiên gần đây',
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 560,
                    child: SimpleTable(
                      columns: const [
                        'Phiên',
                        'Cổng',
                        'Thời gian',
                        'kWh',
                        'Tổng tiền',
                        'Trạng thái',
                      ],
                      flex: const [14, 5, 10, 5, 9, 9],
                      rows: [
                        for (final (s, p, t, k, m, st) in const [
                          (
                            'S-8812 · R-5012',
                            'P3',
                            '08:00–',
                            '15,9',
                            '38.200 đ',
                            'CHARGING',
                          ),
                          (
                            'S-8809 · R-5033',
                            'P1',
                            '08:00–09:15',
                            '12,4',
                            '39.760 đ',
                            'DONE',
                          ),
                          (
                            'S-8801 · R-4990',
                            'P5',
                            '06:00–08:00',
                            '2,9',
                            '11.960 đ',
                            'DONE',
                          ),
                          (
                            'S-8790 · R-4981',
                            'P4',
                            '04/12 21:00',
                            '—',
                            '—',
                            'NO_SHOW',
                          ),
                        ])
                          [
                            cellText(s, bold: true),
                            cellText(p),
                            cellText(t),
                            cellText(k),
                            cellText(m),
                            switch (st) {
                              'CHARGING' => const Pill(
                                'CHARGING',
                                bg: AppColors.sky100,
                                fg: AppColors.blue,
                              ),
                              'DONE' => Pill.success('DONE'),
                              _ => Pill.neutral(st),
                            },
                          ],
                      ],
                    ),
                  ),
                ),
                MutedText(
                  'Tổng tiền = tiền điện theo biểu giá + phí dịch vụ. Số liệu mô phỏng.',
                  size: 12,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
