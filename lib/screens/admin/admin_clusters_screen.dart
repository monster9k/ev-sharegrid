import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/danang_map.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A1 – Cụm điều phối (`grid_cluster`): ranh giới, trần cố định grid_limit_kw.
class AdminClustersScreen extends StatefulWidget {
  const AdminClustersScreen({super.key});
  @override
  State<AdminClustersScreen> createState() => _AdminClustersScreenState();
}

class _AdminClustersScreenState extends State<AdminClustersScreen> {
  String _limit = '550';

  @override
  Widget build(BuildContext context) {
    return WebShell(
      portal: Portal.admin,
      route: '/admin/clusters',
      eyebrow: 'Quản trị · grid_cluster',
      title: 'Cụm điều phối',
      actions: const [
        AppButton(
          label: 'Tạo cụm',
          icon: Icons.add_rounded,
          expand: false,
          height: 42,
          radius: 999,
          fontSize: 14,
        ),
      ],
      children: [
        const AutoGrid(
          minWidth: 170,
          children: [
            WebKpi(
              'Cụm hoạt động',
              '4',
              note: 'Đà Nẵng 2 · Hà Nội 1 · TP.HCM 1',
            ),
            WebKpi('Tổng trần công suất', '2.650 kW', note: 'Cấu hình cố định'),
            WebKpi('Trạm đang hoạt động', '41', note: '+1 chờ duyệt'),
            WebKpi('Request đang hoạt động', '874', note: 'Mô phỏng'),
          ],
        ),
        AutoGrid(
          minWidth: 420,
          gap: 20,
          children: [
            WebCard(
              title: 'Ranh giới cụm – Đà Nẵng',
              trailing: MutedText('Lưới H3 res 7', size: 12),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 220,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: DanangMap(
                            userDot: null,
                            alignment: Alignment(0, -.35),
                          ),
                        ),
                        Positioned.fill(
                          child: Row(
                            children: [
                              Expanded(
                                flex: 53,
                                child: _Zone(
                                  'Cụm 1 · Hải Châu',
                                  AppColors.blue,
                                ),
                              ),
                              Expanded(
                                flex: 47,
                                child: _Zone(
                                  'Cụm 2 · Sơn Trà',
                                  AppColors.chart3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 720,
                    child: SimpleTable(
                      columns: const [
                        'ID',
                        'Tên cụm',
                        'Tỉnh/TP',
                        'Trần kW',
                        'Trạm',
                        'Request',
                        'Đỉnh hôm nay',
                        'Trạng thái',
                      ],
                      flex: const [3, 14, 10, 6, 5, 6, 12, 9],
                      rows: [
                        for (final (id, n, p, cap, st, rq, peak) in const [
                          (
                            '1',
                            'Hải Châu – Trung tâm',
                            'Đà Nẵng',
                            '500',
                            '15',
                            '412',
                            .88,
                          ),
                          (
                            '2',
                            'Sơn Trà – Ven biển',
                            'Đà Nẵng',
                            '350',
                            '9',
                            '186',
                            1.0,
                          ),
                          ('3', 'Cầu Giấy', 'Hà Nội', '800', '10', '143', .61),
                          (
                            '4',
                            'Quận 1',
                            'TP. Hồ Chí Minh',
                            '1.000',
                            '7',
                            '133',
                            .47,
                          ),
                        ])
                          [
                            cellText(id),
                            cellText(n, bold: true),
                            cellText(p),
                            cellText(cap),
                            cellText(st),
                            cellText(rq),
                            Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: ProgressBar(
                                    peak,
                                    height: 6,
                                    color: peak >= 1
                                        ? AppColors.warning
                                        : AppColors.blue,
                                  ),
                                ),
                                const Gap(6),
                                Flexible(
                                  child: cellText(
                                    '${(peak * 100).round()}%${peak >= 1 ? ' !' : ''}',
                                    size: 12,
                                    color: peak >= 1
                                        ? AppColors.warning
                                        : AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                            Pill.success('ACTIVE'),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            WebCard(
              title: 'Sửa cụm · Hải Châu – Trung tâm',
              children: [
                const WebField('Tên cụm', 'Cụm Hải Châu - Trung tâm'),
                const AutoGrid(
                  minWidth: 160,
                  children: [
                    WebField('Tỉnh/TP', 'Đà Nẵng'),
                    WebField('Múi giờ', 'Asia/Ho_Chi_Minh'),
                    WebField('H3 index', '87652636affffff'),
                    WebField('Trạng thái', 'ACTIVE'),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MutedText(
                      'Trần công suất cụm – grid_limit_kw',
                      size: 12,
                      weight: FontWeight.w700,
                    ),
                    const Gap(6),
                    TextFormField(
                      initialValue: _limit,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setState(() => _limit = v),
                      style: AppFonts.body(size: 14, weight: FontWeight.w600),
                      decoration: const InputDecoration(
                        isDense: true,
                        suffixText: 'kW',
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 10,
                    children: [
                      MutedText('Thay đổi:'),
                      const BoldText('500 kW', size: 13),
                      const Text('→'),
                      BoldText('$_limit kW', size: 13, color: AppColors.blue),
                    ],
                  ),
                ),
                const InfoNote(
                  'Đây là trần cố định cho tổng công suất sạc của cụm trong mỗi slot 15 phút, không phải tải lưới đo theo thời điểm. Thay đổi được ghi audit (ai, khi nào, cũ → mới) và áp dụng ở lần tối ưu kế tiếp với snapshot mới.',
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  children: [
                    const AppButton(
                      label: 'Hủy',
                      kind: AppButtonKind.outline,
                      expand: false,
                      height: 42,
                      radius: 999,
                      fontSize: 14,
                    ),
                    AppButton(
                      label: 'Lưu thay đổi',
                      expand: false,
                      height: 42,
                      radius: 999,
                      fontSize: 14,
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Đã lưu grid_limit_kw = $_limit kW · ghi audit log',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Zone extends StatelessWidget {
  const _Zone(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 2),
    ),
    alignment: Alignment.topLeft,
    padding: const EdgeInsets.all(8),
    child: Pill(label, bg: color, fg: Colors.white, size: 11),
  );
}
