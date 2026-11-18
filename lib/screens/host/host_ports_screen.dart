import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';

/// H2/H3 – Quản lý cổng & báo bảo trì (phát RE_OPTIMIZE, xem ảnh hưởng).
class HostPortsScreen extends StatefulWidget {
  const HostPortsScreen({super.key});
  @override
  State<HostPortsScreen> createState() => _HostPortsScreenState();
}

class _HostPortsScreenState extends State<HostPortsScreen> {
  String _port = 'P1 · CCS2';
  bool _offline = false;
  String _connector = 'CCS2';
  String _control = 'CONTINUOUS';

  @override
  Widget build(BuildContext context) {
    final ports = Mock.nvlPorts;
    final nominal = ports.fold<double>(0, (s, p) => s + p.maxKw);
    return WebShell(
      portal: Portal.host,
      route: '/host/ports',
      eyebrow: 'Trạm ShareGrid Nguyễn Văn Linh ▾ · cụm Hải Châu',
      title: 'Cổng sạc & bảo trì',
      actions: const [
        AppButton(
          label: 'Thêm cổng',
          icon: Icons.add_rounded,
          expand: false,
          height: 42,
          radius: 999,
          fontSize: 14,
        ),
      ],
      children: [
        WebCard(
          gap: 10,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              children: [
                const BoldText('Công suất trạm'),
                Text.rich(
                  TextSpan(
                    style: AppFonts.body(size: 13, color: AppColors.muted),
                    children: [
                      const TextSpan(text: 'Tổng danh định các cổng '),
                      TextSpan(
                        text: '${vnDec(nominal, 1)} kW',
                        style: AppFonts.body(size: 13, weight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' · Trần trạm '),
                      TextSpan(
                        text: '40 kW',
                        style: AppFonts.body(size: 13, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Semantics(
              label:
                  'Tổng danh định ${vnDec(nominal, 1)} kW vượt trần trạm 40 kW',
              child: SizedBox(
                height: 26,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final capX = c.maxWidth * 40 / nominal;
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFBFD0F7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Container(
                          width: capX,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.blue,
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(999),
                            ),
                          ),
                        ),
                        Positioned(
                          left: capX,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: AppColors.red),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            MutedText(
              'Bộ lập lịch luôn giữ tổng công suất các cổng đang phát ≤ 40 kW ở mọi slot 15 phút, dù tổng danh định lớn hơn.',
              size: 12,
            ),
          ],
        ),
        AutoGrid(
          minWidth: 440,
          gap: 20,
          children: [
            WebCard(
              title: 'Danh sách cổng',
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 640,
                    child: SimpleTable(
                      columns: const [
                        'Mã',
                        'Đầu nối',
                        'Điều khiển',
                        'Công suất',
                        'Trạng thái',
                        'Lịch tới',
                        '',
                      ],
                      flex: const [5, 7, 12, 10, 14, 6, 8],
                      rows: [
                        for (final p in ports)
                          [
                            cellText(p.code, bold: true),
                            cellText(p.connector),
                            cellText(p.control, size: 12),
                            cellText(
                              p.minKw == p.maxKw
                                  ? '${vnDec(p.maxKw, 1)} kW cố định'
                                  : '${vnDec(p.minKw, 1)}–${vnDec(p.maxKw, 0)} kW',
                            ),
                            p.status == PortStatus.active
                                ? Pill.success('ACTIVE')
                                : Pill.warning('BẢO TRÌ · 14:00'),
                            cellText('${p.futureBookings}'),
                            AppButton(
                              label: p.status == PortStatus.active
                                  ? 'Sửa'
                                  : 'Mở lại',
                              kind: AppButtonKind.outline,
                              expand: false,
                              height: 32,
                              radius: 999,
                              fontSize: 12,
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
                const Divider(color: AppColors.border),
                const BoldText('Thêm cổng mới', size: 14),
                AutoGrid(
                  minWidth: 110,
                  gap: 10,
                  children: [
                    const WebField('Mã cổng', 'P6'),
                    _Drop('Đầu nối', _connector, const [
                      'CCS2',
                      'Type2',
                      'CHAdeMO',
                      'AC_HOME',
                    ], (v) => setState(() => _connector = v)),
                    _Drop('Điều khiển', _control, const [
                      'CONTINUOUS',
                      'ON_OFF_SWITCH',
                    ], (v) => setState(() => _control = v)),
                    const WebField('Min kW', '1,4'),
                    const WebField('Max kW', '7,4'),
                  ],
                ),
                MutedText(
                  'Cổng ON_OFF_SWITCH chỉ có 2 mức: 0 kW hoặc bật ở mức cố định (min = max). Mã cổng không được trùng trong trạm.',
                  size: 12,
                ),
              ],
            ),
            WebCard(
              title: 'Báo bảo trì / sự cố',
              children: [
                AutoGrid(
                  minWidth: 150,
                  children: [
                    _Drop('Cổng', _port, const [
                      'P1 · CCS2',
                      'P3 · CCS2',
                      'P4 · Type2',
                      'Cả trạm',
                    ], (v) => setState(() => _port = v)),
                    const WebField('Dự kiến hoạt động lại', '16:00'),
                  ],
                ),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: const Text('MAINTENANCE'),
                      selected: !_offline,
                      selectedColor: AppColors.warningBg,
                      onSelected: (_) => setState(() => _offline = false),
                    ),
                    ChoiceChip(
                      label: const Text('OFFLINE'),
                      selected: _offline,
                      selectedColor: AppColors.redBg,
                      onSelected: (_) => setState(() => _offline = true),
                    ),
                  ],
                ),
                const WebField('Lý do', 'Thay đầu súng sạc bị lỏng'),
                const BoldText(
                  'Ảnh hưởng dự kiến · 3 lịch tương lai trên P1',
                  size: 14,
                ),
                const _Impact(
                  ok: true,
                  id: 'R-5040',
                  text: ' (10:00–11:15) → chuyển sang P3, cùng đầu nối CCS2.',
                ),
                const _Impact(
                  ok: true,
                  id: 'R-5047',
                  text: ' (12:00–13:00) → chuyển sang P3.',
                ),
                const _Impact(
                  ok: false,
                  id: 'R-5051',
                  text: ' (13:15–15:00): P3 đã kín và trạm chạm trần 40 kW → dự kiến thiếu 1,2 kWh, gửi thông báo khẩn cho khách.',
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.sky100.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Khi xác nhận: hệ thống phát sự kiện RE_OPTIMIZE cho cụm Hải Châu → giữ nguyên slot đã chạy → xếp lại phần tương lai sang cổng tương thích → tạo lịch version mới và gửi thông báo cho khách bị ảnh hưởng.',
                    style: AppFonts.body(
                      size: 12,
                      color: AppColors.blue800,
                      height: 1.5,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã phát RE_OPTIMIZE · lịch cụm Hải Châu lên v4',
                              ),
                            ),
                          ),
                      child: Text(
                        'Xác nhận chuyển bảo trì',
                        style: AppFonts.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop(this.label, this.value, this.items, this.onChanged);
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MutedText(label, size: 12, weight: FontWeight.w700),
      const Gap(6),
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        isDense: true,
        style: AppFonts.body(size: 14, weight: FontWeight.w600),
        items: [
          for (final i in items)
            DropdownMenuItem(
              value: i,
              child: Text(i, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => onChanged(v!),
      ),
    ],
  );
}

class _Impact extends StatelessWidget {
  const _Impact({required this.ok, required this.id, required this.text});
  final bool ok;
  final String id;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ok ? AppColors.successBg : AppColors.redBg,
          shape: BoxShape.circle,
        ),
        child: Text(
          ok ? '✓' : '!',
          style: AppFonts.body(
            size: 12,
            weight: FontWeight.w700,
            color: ok ? AppColors.success : AppColors.red,
          ),
        ),
      ),
      const Gap(10),
      Expanded(
        child: Text.rich(
          TextSpan(
            style: AppFonts.body(size: 13, color: AppColors.body, height: 1.45),
            children: [
              TextSpan(
                text: id,
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              TextSpan(text: text),
            ],
          ),
        ),
      ),
    ],
  );
}
