import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A5 – Mô phỏng & Benchmark Lab: chọn scenario, thuật toán, so KPI.
/// Toàn bộ số liệu là MINH HOẠ, chưa phải kết quả đo.
class AdminBenchmarkScreen extends StatefulWidget {
  const AdminBenchmarkScreen({super.key});
  @override
  State<AdminBenchmarkScreen> createState() => _AdminBenchmarkScreenState();
}

class _AdminBenchmarkScreenState extends State<AdminBenchmarkScreen> {
  int _size = 2;
  int _profile = 0;
  String _scenario = 'SC-1K-BAL · Đà Nẵng';
  final _algos = {
    'MILP_MPC': true,
    'LP_MPC': true,
    'LLF': true,
    'EDF': true,
    'FCFS': true,
    'EQUAL_SHARE': true,
    'ASAP': true,
  };

  static const _sizes = ['100', '500', '1.000', '2.500', '5.000', '10.000'];

  static const _kpi = [
    ('MILP_MPC', '12,4', '99,1%', '28,6 tr đ', '2.640', '0', '0,97', '1.420'),
    ('LP_MPC', '15,8', '98,7%', '28,9 tr đ', '2.650', '0', '0,96', '310'),
    ('LLF', '31,2', '97,4%', '31,5 tr đ', '2.650', '0', '0,94', '45'),
    ('EDF', '44,6', '96,2%', '32,0 tr đ', '2.650', '0', '0,90', '38'),
    ('EQUAL_SHARE', '71,5', '93,5%', '32,4 tr đ', '2.650', '0', '0,99', '25'),
    ('FCFS', '96,3', '91,8%', '33,1 tr đ', '2.650', '0', '0,81', '22'),
    ('ASAP', '0,0*', '100%*', '36,8 tr đ', '3.910', '214', '—', '5'),
  ];

  @override
  Widget build(BuildContext context) {
    final seg = Segmented(
      items: _sizes,
      selected: _size,
      onChanged: (i) => setState(() => _size = i),
    );
    return WebShell(
      portal: Portal.admin,
      route: '/admin/benchmark',
      eyebrow: 'Quản trị · simulation_scenario & benchmark_result',
      title: 'Mô phỏng & Benchmark thuật toán',
      actions: [
        Pill.warning('Số liệu minh hoạ – thay bằng kết quả đo thật'),
        const WebBtn('Xuất CSV'),
        WebBtn(
          'Chạy benchmark',
          primary: true,
          icon: Icons.play_arrow_rounded,
          onTap: () => showSnack(
            context,
            'Đã xếp hàng benchmark $_scenario · ${_sizes[_size]} active requests · seed 42 (mô phỏng)',
          ),
        ),
      ],
      children: [
        WebCard(
          title: 'Kịch bản',
          children: [
            AutoGrid(
              minWidth: 170,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MutedText(
                      'simulation_scenario',
                      size: 12,
                      weight: FontWeight.w700,
                    ),
                    const Gap(6),
                    DropdownButtonFormField<String>(
                      initialValue: _scenario,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final s in const [
                          'SC-1K-BAL · Đà Nẵng',
                          'SC-10K-HOT · Hải Châu',
                        ])
                          DropdownMenuItem(value: s, child: Text(s)),
                      ],
                      onChanged: (v) => setState(() => _scenario = v!),
                    ),
                  ],
                ),
                const WebField('Tài khoản (registry_users)', '100.000'),
                const WebField('Seed', '42'),
                const WebField('Số lần lặp', '5'),
                const WebField('Time budget / job', '2.000 ms'),
              ],
            ),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MutedText('active_requests', size: 12, weight: FontWeight.w700),
                SizedBox(width: 440, child: seg),
                MutedText('Profile', size: 12, weight: FontWeight.w700),
                SizedBox(
                  width: 280,
                  child: Segmented(
                    items: const ['Balanced', 'Hot-spot 17–20h'],
                    selected: _profile,
                    onChanged: (i) => setState(() => _profile = i),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _algos.keys)
                  FilterChipX(
                    a,
                    selected: _algos[a]!,
                    icon: _algos[a]! ? Icons.check_rounded : null,
                    onTap: () => setState(() => _algos[a] = !_algos[a]!),
                  ),
                const Opacity(
                  opacity: .5,
                  child: FilterChipX('NSGA_II (≤ 500 request)'),
                ),
              ],
            ),
            MutedText(
              '100.000 là số tài khoản trong hệ thống; số yêu cầu đưa vào bộ lập lịch mỗi lần là active_requests. Mọi thuật toán chạy trên cùng scenario, seed, biểu giá và trần công suất.',
              size: 12,
            ),
          ],
        ),
        WebCard(
          title: 'Bảng KPI · SC-1K-BAL · 1.000 active requests',
          trailing: MutedText('Trung bình 5 lần lặp', size: 12),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 960,
                child: SimpleTable(
                  columns: const [
                    'Thuật toán',
                    'Điện thiếu kWh',
                    'Đúng hạn',
                    'Chi phí điện',
                    'Đỉnh kW',
                    'Vi phạm trần',
                    'Fairness',
                    'solve_ms',
                  ],
                  flex: const [14, 8, 7, 8, 6, 7, 6, 6],
                  rows: [
                    for (final r in _kpi)
                      if (_algos[r.$1]!)
                        [
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              cellText(r.$1, bold: true),
                              if (r.$1 == 'MILP_MPC') Pill.blue('đề xuất'),
                              if (r.$1 == 'ASAP') Pill.danger('chỉ đối chiếu'),
                            ],
                          ),
                          cellText(r.$2, bold: r.$1 == 'MILP_MPC'),
                          cellText(r.$3, bold: r.$1 == 'MILP_MPC'),
                          cellText(r.$4),
                          cellText(
                            r.$5,
                            bold: r.$1 == 'ASAP',
                            color: r.$1 == 'ASAP'
                                ? AppColors.red
                                : AppColors.ink,
                          ),
                          cellText(
                            r.$6,
                            bold: r.$1 == 'ASAP',
                            color: r.$1 == 'ASAP'
                                ? AppColors.red
                                : AppColors.ink,
                          ),
                          cellText(r.$7),
                          cellText(r.$8),
                        ],
                  ],
                ),
              ),
            ),
            MutedText(
              '* ASAP sạc tối đa ngay khi cắm nên vượt trần cụm 214 slot; lịch này không qua validator và chỉ dùng làm mốc "khi chưa điều phối".',
              size: 12,
            ),
          ],
        ),
        AutoGrid(
          minWidth: 420,
          gap: 20,
          children: [
            WebCard(
              title: 'Thời gian giải theo số request đang hoạt động',
              trailing: const SimTag(text: 'Minh hoạ'),
              children: [
                MutedText('Wall time một lần tối ưu, thang log (giây)'),
                const Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    LegendDot(AppColors.chart1, 'MILP_MPC + Master–Worker'),
                    LegendDot(AppColors.chart2, 'LP_MPC'),
                    LegendDot(AppColors.chart3, 'LLF'),
                    LegendDot(
                      Color(0xFF8A94A8),
                      'MILP nguyên khối',
                      dashed: true,
                    ),
                  ],
                ),
                LineChart(
                  series: const [
                    LineSeries(
                      Mock.solveMilp,
                      color: AppColors.chart1,
                      dots: true,
                    ),
                    LineSeries(
                      Mock.solveLp,
                      color: AppColors.chart2,
                      dots: true,
                    ),
                    LineSeries(
                      Mock.solveLlf,
                      color: AppColors.chart3,
                      dots: true,
                    ),
                    LineSeries(
                      Mock.solveMonolithic,
                      color: Color(0xFF8A94A8),
                      dashed: true,
                    ),
                  ],
                  xLabels: const ['100', '500', '1k', '2,5k', '5k', '10k'],
                  log: true,
                  minY: .01,
                  maxY: 100,
                  yTicks: const [.01, .1, 1, 10, 100],
                  yFormat: (v) => v < 1 ? vnDec(v, v < .1 ? 2 : 1) : vnInt(v),
                  height: 220,
                  semantics:
                      'Biểu đồ thang log thời gian giải theo số request, minh hoạ',
                ),
              ],
            ),
            WebCard(
              title: 'Tổng điện thiếu theo thuật toán',
              children: [
                MutedText('kWh · càng thấp càng tốt · không tính ASAP'),
                for (final (a, v) in const [
                  ('MILP_MPC', 12.4),
                  ('LP_MPC', 15.8),
                  ('LLF', 31.2),
                  ('EDF', 44.6),
                  ('EQUAL_SHARE', 71.5),
                  ('FCFS', 96.3),
                ])
                  HBar(
                    label: a,
                    value: v,
                    max: 96.3,
                    display: vnDec(v),
                    color: a == 'MILP_MPC'
                        ? AppColors.blue
                        : AppColors.chartGrey,
                  ),
              ],
            ),
          ],
        ),
        AutoGrid(
          minWidth: 420,
          gap: 20,
          children: [
            WebCard(
              title: 'Ma trận 9 case kiểm chứng',
              gap: 8,
              children: [
                for (final (c, ok) in const [
                  ('New joins old – request cũ + mới cùng pool', true),
                  ('Old charging – giữ kWh đã nạp', true),
                  ('Terminal excluded – DONE/CANCELLED/FAILED', true),
                  ('Cross-cluster – không tranh nhầm tài nguyên', true),
                  ('Tie-break – ổn định, không theo tuổi tài khoản', true),
                  ('Capacity conflict – không vượt trần', true),
                  ('Concurrent booking – khóa theo cụm', false),
                  ('Solver timeout – FALLBACK, không OPTIMAL giả', true),
                  ('Schedule change – version mới + thông báo', true),
                ])
                  _CaseRow(
                    c,
                    ok ? Pill.success('✓ Đạt') : Pill.neutral('◷ Chưa chạy'),
                  ),
              ],
            ),
            WebCard(
              title: '5 mức tải 10.000 (báo cáo tách riêng)',
              gap: 8,
              children: [
                _CaseRow(
                  '10.000 tài khoản trong CSDL (đã sinh 100.000)',
                  Pill.success('✓ Đã có dữ liệu'),
                ),
                _CaseRow(
                  '10.000 phiên App/Web đồng thời',
                  Pill.neutral('◷ Chưa đo'),
                ),
                _CaseRow(
                  '10.000 lệnh đặt chỗ trong một burst',
                  Pill.neutral('◷ Chưa đo'),
                ),
                _CaseRow(
                  '10.000 active requests cho bộ lập lịch',
                  Pill.warning('Minh hoạ'),
                ),
                _CaseRow(
                  '10.000 solver jobs (sau coalesce)',
                  Pill.neutral('◷ Chưa đo'),
                ),
                MutedText(
                  'Chỉ ghi "đạt" khi có số đo thật gắn scenario và code_version. Tiêu chí: 0 vi phạm trần, 0 request trùng, 0 request bị bỏ, 0 kết quả stale, 0 event mất.',
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

class _CaseRow extends StatelessWidget {
  const _CaseRow(this.text, this.pill);
  final String text;
  final Widget pill;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: AppFonts.body(size: 13, weight: FontWeight.w500),
          ),
        ),
        const Gap(8),
        pill,
      ],
    ),
  );
}
