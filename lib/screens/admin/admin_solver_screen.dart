import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A4 – Giám sát vận hành & hàng đợi: optimization_job, optimization_run.
class AdminSolverScreen extends StatelessWidget {
  const AdminSolverScreen({super.key});

  static Widget status(String s) {
    final key = s.split(' ').first;
    return switch (key) {
      'OPTIMAL' || 'DONE' || '✓' => Pill.success(s),
      'FEASIBLE' ||
      'RUNNING' => Pill(s, bg: AppColors.sky100, fg: AppColors.blue),
      'FALLBACK' || 'STALE' => Pill.warning(s),
      'ERROR' => Pill.danger(s),
      _ => Pill.neutral(s),
    };
  }

  @override
  Widget build(BuildContext context) {
    return WebShell(
      portal: Portal.admin,
      route: '/admin/solver',
      eyebrow:
          'Quản trị · optimization_job & optimization_run · cập nhật 09:15:42',
      title: 'Giám sát solver & hàng đợi',
      actions: [
        Pill.neutral('Dữ liệu mô phỏng'),
        WebBtn(
          'Khởi chạy lại cụm…',
          onTap: () => showSnack(
            context,
            'Đã tạo job RE_OPTIMIZE cho cụm Hải Châu (gom vào job đang chờ nếu có)',
          ),
        ),
      ],
      children: [
        const AutoGrid(
          minWidth: 170,
          children: [
            WebKpi('Job trong hàng đợi', '3', note: 'Lâu nhất 2,1 s'),
            WebKpi(
              'solve_ms p95 (1 giờ)',
              '1.840 ms',
              note: 'Time budget 2.000 ms',
            ),
            WebKpi('FALLBACK (24 giờ)', '2', note: '0,4% số run · LLF'),
            WebKpi('Outbox lag', '120 ms', note: '0 event mất'),
            WebKpi('Kết quả stale bị loại', '5', note: 'Có version mới hơn'),
          ],
        ),
        AutoGrid(
          minWidth: 440,
          gap: 20,
          children: [
            WebCard(
              title: 'Độ sâu hàng đợi · 60 phút',
              trailing: MutedText('số job', size: 12),
              children: [
                LineChart(
                  series: const [
                    LineSeries(
                      Mock.queueDepth,
                      color: AppColors.blue,
                      area: true,
                      dots: true,
                    ),
                  ],
                  xLabels: [
                    for (var m = 0; m <= 60; m += 6)
                      m == 60 ? 'bây giờ' : '-${60 - m}′',
                  ],
                  maxY: 10,
                  yTicks: const [0, 5, 10],
                  height: 190,
                  semantics:
                      'Độ sâu hàng đợi job trong 60 phút, cao nhất 9 job',
                ),
                MutedText(
                  'Nhiều sự kiện cùng cụm được gom (coalesce) thành một job; mỗi cụm tối đa một job đang giữ lease.',
                  size: 12,
                ),
              ],
            ),
            WebCard(
              title: 'Hàng đợi job',
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 640,
                    child: SimpleTable(
                      columns: const [
                        'Job',
                        'Cụm',
                        'Version',
                        'Event',
                        'Thử',
                        'Worker',
                        'Trạng thái',
                      ],
                      flex: const [6, 7, 5, 4, 3, 9, 13],
                      rows: [
                        for (final (j, c, v, e, a, w, s) in const [
                          (
                            'J-2297',
                            'Hải Châu',
                            'v108',
                            '4',
                            '1',
                            'opt-worker-2',
                            'RUNNING · lease 18 s',
                          ),
                          ('J-2298', 'Sơn Trà', 'v77', '2', '0', '—', 'QUEUED'),
                          (
                            'J-2299',
                            'Cầu Giấy',
                            'v41',
                            '1',
                            '0',
                            '—',
                            'QUEUED',
                          ),
                          (
                            'J-2295',
                            'Hải Châu',
                            'v107',
                            '6',
                            '1',
                            'opt-worker-1',
                            'STALE · có v108',
                          ),
                          (
                            'J-2291',
                            'Hải Châu',
                            'v106',
                            '3',
                            '1',
                            'opt-worker-2',
                            'DONE',
                          ),
                        ])
                          [
                            cellText(j, bold: true),
                            cellText(c),
                            cellText(v),
                            cellText(e),
                            cellText(a),
                            cellText(w, size: 12),
                            status(s),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        WebCard(
          title: 'Các lần chạy gần đây',
          trailing: MutedText(
            'Lưu input_json, seed, code_version để tái lập',
            size: 12,
          ),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1060,
                child: SimpleTable(
                  columns: const [
                    'Run',
                    'Cụm',
                    'Kích hoạt',
                    'Thuật toán',
                    'Trạng thái',
                    'n_req',
                    'solve_ms',
                    'Thiếu kWh',
                    'Validator',
                    'Lúc',
                  ],
                  flex: const [5, 7, 11, 8, 16, 5, 6, 6, 7, 4],
                  rows: [
                    for (final (r, c, t, a, s, n, ms, sf, v, at) in const [
                      (
                        '#1046',
                        'Sơn Trà',
                        'MPC_15MIN',
                        'MILP_MPC',
                        'FEASIBLE',
                        '186',
                        '2.000',
                        '3,4',
                        '✓ đạt',
                        '09:15',
                      ),
                      (
                        '#1045',
                        'Hải Châu',
                        'PORT_OFFLINE (P2)',
                        'MILP_MPC',
                        'OPTIMAL',
                        '412',
                        '1.320',
                        '0,0',
                        '✓ đạt',
                        '08:40',
                      ),
                      (
                        '#1044',
                        'Hải Châu',
                        'NEW_REQUEST ×6',
                        'MILP_MPC',
                        'OPTIMAL',
                        '409',
                        '1.180',
                        '0,0',
                        '✓ đạt',
                        '08:31',
                      ),
                      (
                        '#1043',
                        'Sơn Trà',
                        'NEW_REQUEST ×3',
                        'LLF',
                        'FALLBACK',
                        '181',
                        '2.000',
                        '4,1',
                        '✓ đạt',
                        '08:30',
                      ),
                      (
                        '#1042',
                        'Hải Châu',
                        'NEW_REQUEST',
                        'MILP_MPC',
                        'OPTIMAL',
                        '38',
                        '142',
                        '0,0',
                        '✓ đạt',
                        '08:02',
                      ),
                      (
                        '#1039',
                        'Quận 1',
                        'CONFIG_CHANGE',
                        '—',
                        'ERROR · thiếu biểu giá 22–24h',
                        '—',
                        '—',
                        '—',
                        'không chạy',
                        '07:55',
                      ),
                    ])
                      [
                        cellText(r, bold: true),
                        cellText(c),
                        cellText(t, size: 12),
                        cellText(a, size: 12),
                        status(s),
                        cellText(n),
                        cellText(ms),
                        cellText(sf),
                        status(v),
                        cellText(at),
                      ],
                  ],
                ),
              ),
            ),
            MutedText(
              'FEASIBLE: có lịch hợp lệ nhưng chưa chứng minh tối ưu trước time budget · FALLBACK: solver quá hạn, dùng LLF · ERROR: không phát lịch, xem log.',
              size: 12,
            ),
          ],
        ),
      ],
    );
  }
}
