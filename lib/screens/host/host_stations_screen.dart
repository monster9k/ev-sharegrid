import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/danang_map.dart';
import '../../widgets/web_shell.dart';

/// H1 – Trạm của tôi: danh sách trạm + form đăng ký trạm mới (→ PENDING).
class HostStationsScreen extends StatefulWidget {
  const HostStationsScreen({super.key});
  @override
  State<HostStationsScreen> createState() => _HostStationsScreenState();
}

class _HostStationsScreenState extends State<HostStationsScreen> {
  bool _is24h = false;
  String _type = 'ALL (ô tô + xe máy)';

  @override
  Widget build(BuildContext context) {
    return WebShell(
      portal: Portal.host,
      route: '/host/stations',
      eyebrow: 'Chủ trạm · Đà Nẵng',
      title: 'Trạm của tôi',
      actions: [
        AppButton(
          label: 'Đăng ký trạm mới',
          icon: Icons.add_rounded,
          expand: false,
          height: 42,
          radius: 999,
          fontSize: 14,
        ),
      ],
      children: [
        const AutoGrid(
          children: [
            WebKpi('Trạm', '3', note: '2 ACTIVE · 1 PENDING'),
            WebKpi('Cổng sạc', '12', note: '1 đang bảo trì'),
            WebKpi('Phiên hôm nay', '41', note: 'Mô phỏng'),
            WebKpi(
              'Phí dịch vụ hôm nay',
              '410.000 đ',
              note: 'Chưa gồm tiền điện',
            ),
          ],
        ),
        AutoGrid(
          minWidth: 420,
          gap: 20,
          children: [
            WebCard(
              title: 'Danh sách trạm',
              children: [
                _StationRow(
                  name: 'Trạm ShareGrid Nguyễn Văn Linh',
                  address: '85 Nguyễn Văn Linh, Hải Châu · cụm Hải Châu · 24/7',
                  meta: 'Trần 40 kW · 5 cổng · phí DV 10.000 đ',
                  pill: Pill.success('✓ ACTIVE · đã xác minh'),
                  onPorts: () => context.go('/host/ports'),
                ),
                _StationRow(
                  name: 'Trạm ShareGrid Bạch Đằng',
                  address: '120 Bạch Đằng, Hải Châu · 06:00–23:00',
                  meta: 'Trần 22 kW · 4 cổng · phí DV 5.000 đ',
                  pill: Pill.success('✓ ACTIVE · đã xác minh'),
                  onPorts: () => context.go('/host/ports'),
                ),
                _StationRow(
                  name: 'Điểm sạc Chung cư Hòa Xuân',
                  address: 'Hòa Xuân, Cẩm Lệ · 18:00–07:00',
                  meta: 'Trần 11 kW · 3 cổng · gửi 17/11',
                  pill: Pill.warning('◷ PENDING · chờ ADMIN duyệt'),
                  pending: true,
                ),
                MutedText(
                  'Chủ trạm không tự chuyển PENDING sang ACTIVE và không viết lịch cho từng xe; lịch do bộ lập lịch tạo.',
                  size: 12,
                ),
              ],
            ),
            WebCard(
              title: 'Đăng ký trạm mới',
              children: [
                const WebField('Tên trạm', 'Điểm sạc Ngũ Hành Sơn'),
                const WebField('Địa chỉ', 'Lê Văn Hiến, Ngũ Hành Sơn, Đà Nẵng'),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 150,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: DanangMap(
                            showLabels: false,
                            userDot: null,
                            alignment: Alignment(0, .3),
                          ),
                        ),
                        const Center(
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 40,
                            color: AppColors.blue,
                          ),
                        ),
                        Positioned(
                          left: 10,
                          bottom: 10,
                          child: Pill(
                            'Kéo ghim để chọn vị trí',
                            bg: Colors.white.withValues(alpha: .85),
                            fg: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _Grid2([
                  const WebField('Vĩ độ (lat)', '16.000812'),
                  const WebField('Kinh độ (lng)', '108.263504'),
                  const WebField('Giờ mở cửa', '06:00'),
                  const WebField('Giờ đóng cửa', '22:00'),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MutedText(
                        'Loại xe hỗ trợ',
                        size: 12,
                        weight: FontWeight.w700,
                      ),
                      const Gap(6),
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        isExpanded: true,
                        isDense: true,
                        items: [
                          for (final t in const [
                            'ALL (ô tô + xe máy)',
                            'CAR',
                            'MOTORBIKE',
                          ])
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (v) => setState(() => _type = v!),
                      ),
                    ],
                  ),
                  const WebField('Trần công suất trạm (kW)', '22'),
                  const WebField('Phí dịch vụ (đ/phiên)', '5000'),
                  const WebField('Phiên tối đa (phút)', '240'),
                ]),
                CheckboxListTile(
                  value: _is24h,
                  onChanged: (v) => setState(() => _is24h = v!),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Mở cửa 24/7',
                    style: AppFonts.body(size: 14, weight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg.withValues(alpha: .85),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: AppFonts.body(
                        size: 13,
                        color: const Color(0xFF7A3E06),
                        height: 1.45,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Trần công suất trạm là giới hạn đường dây thực tế, có thể nhỏ hơn tổng công suất danh định các cổng. Sau khi gửi, trạm ở trạng thái ',
                        ),
                        TextSpan(
                          text: 'PENDING',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' và chưa nhận đặt lịch cho tới khi ADMIN kiểm chứng.',
                        ),
                      ],
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    const AppButton(
                      label: 'Lưu nháp',
                      kind: AppButtonKind.outline,
                      expand: false,
                      height: 42,
                      radius: 999,
                      fontSize: 14,
                    ),
                    AppButton(
                      label: 'Gửi duyệt',
                      expand: false,
                      height: 42,
                      radius: 999,
                      fontSize: 14,
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã gửi · trạm ở trạng thái PENDING chờ ADMIN duyệt',
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

class _Grid2 extends StatelessWidget {
  const _Grid2(this.children);
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      AutoGrid(minWidth: 160, children: children);
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.name,
    required this.address,
    required this.meta,
    required this.pill,
    this.onPorts,
    this.pending = false,
  });
  final String name;
  final String address;
  final String meta;
  final Widget pill;
  final VoidCallback? onPorts;
  final bool pending;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: pending ? const Color(0xFFF0C48E) : Colors.white,
        width: pending ? 1.5 : 1,
      ),
    ),
    child: Wrap(
      spacing: 14,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BoldText(name),
              const Gap(3),
              MutedText(address),
              MutedText(meta, size: 12),
            ],
          ),
        ),
        pill,
        if (onPorts != null)
          AppButton(
            label: 'Cổng',
            kind: AppButtonKind.outline,
            expand: false,
            height: 36,
            radius: 999,
            fontSize: 14,
            onPressed: onPorts,
          ),
      ],
    ),
  );
}
