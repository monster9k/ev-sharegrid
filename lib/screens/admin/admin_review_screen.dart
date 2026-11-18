import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A2 – Kiểm duyệt trạm & quy ước dữ liệu (REAL / SURVEY / SIMULATED).
class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key});
  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  int _tab = 0;
  int _selected = 0;
  String _status = 'PENDING';

  static const _queue = [
    (
      'Điểm sạc Chung cư Hòa Xuân',
      'Gửi bởi HOST · 17/11 21:40',
      ['PENDING', 'SURVEY'],
    ),
    (
      'Trạm sạc công cộng Điện Biên Phủ',
      'Nhập từ OpenStreetMap',
      ['verified = false', 'REAL'],
    ),
    (
      'Trạm thử nghiệm SIM-0043',
      'Sinh bởi script dữ liệu',
      ['Chỉ dùng benchmark', 'SIMULATED'],
    ),
  ];

  Widget _tag(String t) => switch (t) {
    'PENDING' => Pill.warning(t),
    'SURVEY' => Pill(
      t,
      bg: const Color(0xFFE8EEF9),
      fg: const Color(0xFF2F55A4),
    ),
    'REAL' => Pill.success(t),
    'SIMULATED' => Pill(
      t,
      bg: const Color(0xFFF3EAFB),
      fg: const Color(0xFF6B3FA0),
    ),
    _ => Pill.neutral(t),
  };

  @override
  Widget build(BuildContext context) {
    final queue = WebCard(
      title: 'Hàng đợi',
      gap: 10,
      children: [
        for (var i = 0; i < _queue.length; i++)
          Material(
            color: i == _selected
                ? AppColors.sky100.withValues(alpha: .7)
                : Colors.white.withValues(alpha: .6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: i == _selected ? AppColors.blue : Colors.white,
                width: i == _selected ? 2 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _selected = i),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BoldText(_queue[i].$1, size: 14),
                    MutedText(_queue[i].$2, size: 12),
                    const Gap(6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final t in _queue[i].$3) _tag(t)],
                    ),
                  ],
                ),
              ),
            ),
          ),
        MutedText(
          'Dữ liệu bản đồ chưa xác minh không được coi là đang mở và không nhận đặt lịch.',
          size: 12,
        ),
      ],
    );

    final detail = WebCard(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Điểm sạc Chung cư Hòa Xuân',
                    style: AppFonts.display(size: 19),
                  ),
                  const Gap(4),
                  MutedText(
                    'Chủ trạm: Nguyễn Văn Chủ Trạm (HOST #2) · nguồn SURVEY · Khao_sat_DN_07',
                  ),
                ],
              ),
            ),
            switch (_status) {
              'ACTIVE' => Pill.success('✓ ACTIVE · verified'),
              'REJECTED' => Pill.danger('✗ REJECTED'),
              _ => Pill.warning('◷ $_status'),
            },
          ],
        ),
        AutoGrid(
          minWidth: 300,
          gap: 20,
          children: [
            Column(
              children: [
                for (final (k, v) in const [
                  ('Địa chỉ', 'Khu đô thị Hòa Xuân, Cẩm Lệ'),
                  ('Toạ độ', '16.011420, 108.224730'),
                  ('Cụm gán theo H3', '1 · Hải Châu – Trung tâm'),
                  ('Giờ mở cửa', '18:00 – 07:00 (qua đêm)'),
                  ('Loại xe', 'ALL'),
                  ('Trần trạm khai báo', '11 kW'),
                  ('Phí dịch vụ', '5.000 đ/phiên'),
                ])
                  InfoRow(k, v, size: 13),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BoldText('Cổng khai báo', size: 13),
                const Gap(6),
                SimpleTable(
                  columns: const ['Mã', 'Đầu nối', 'Điều khiển', 'Max'],
                  flex: const [3, 5, 8, 4],
                  rows: [
                    for (final (c, n, t, m) in const [
                      ('P1', 'CCS2', 'CONTINUOUS', '7,4 kW'),
                      ('P2', 'Type2', 'CONTINUOUS', '7,4 kW'),
                      ('P3', 'AC_HOME', 'ON_OFF_SWITCH', '2,2 kW'),
                    ])
                      [
                        cellText(c, bold: true),
                        cellText(n),
                        cellText(t, size: 11),
                        cellText(m),
                      ],
                  ],
                ),
                const Gap(6),
                MutedText('Tổng danh định 17 kW · trần trạm 11 kW', size: 12),
              ],
            ),
          ],
        ),
        const BoldText('Danh sách kiểm tra', size: 14),
        const Column(
          children: [
            CheckLine(
              CheckState.ok,
              'Vị trí',
              'toạ độ khớp địa chỉ, lệch 18 m.',
            ),
            CheckLine(
              CheckState.ok,
              'Quyền sở hữu',
              'tài khoản HOST đã xác minh số điện thoại; chủ trạm khớp người gửi.',
            ),
            CheckLine(
              CheckState.warn,
              'Công suất',
              'trần trạm 11 kW nhỏ hơn tổng danh định 17 kW – hợp lệ, bộ lập lịch sẽ giữ tổng ≤ 11 kW. Đề nghị ảnh tủ điện để xác nhận mức 11 kW.',
            ),
            CheckLine(
              CheckState.ok,
              'Mã cổng',
              'P1–P3 không trùng trong trạm; đầu nối thuộc danh mục.',
            ),
            CheckLine(
              CheckState.ok,
              'Giờ mở cửa',
              'khung qua đêm hợp lệ; phiên tối đa 240 phút.',
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            WebBtn(
              'Từ chối',
              color: AppColors.red,
              onTap: () => setState(() => _status = 'REJECTED'),
            ),
            WebBtn(
              'Yêu cầu bổ sung',
              onTap: () =>
                  showSnack(context, 'Đã gửi yêu cầu bổ sung cho HOST'),
            ),
            WebBtn(
              'Duyệt & kích hoạt',
              primary: true,
              onTap: () {
                setState(() => _status = 'ACTIVE');
                showSnack(
                  context,
                  'verified = TRUE, status = ACTIVE · đã ghi audit',
                );
              },
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: MutedText(
            'Duyệt: verified = TRUE, status = ACTIVE · thao tác được ghi audit.',
            size: 12,
          ),
        ),
      ],
    );

    return WebShell(
      portal: Portal.admin,
      route: '/admin/review',
      eyebrow: 'Quản trị · charging_station',
      title: 'Kiểm duyệt trạm & dữ liệu',
      actions: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (i, l) in const [
              (0, 'Chờ duyệt (1)'),
              (1, 'OSM chưa xác minh (12)'),
              (2, 'Đã duyệt (41)'),
              (3, 'Từ chối (2)'),
            ])
              FilterChipX(
                l,
                selected: _tab == i,
                onTap: () => setState(() => _tab = i),
              ),
          ],
        ),
      ],
      children: [
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 760) {
              return Column(children: [queue, const Gap(20), detail]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 10, child: queue),
                const Gap(20),
                Expanded(flex: 22, child: detail),
              ],
            );
          },
        ),
      ],
    );
  }
}
