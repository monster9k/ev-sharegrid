import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import 'home_screen.dart' show DateBadge;

/// U7 – Lịch đặt & theo dõi phiên sạc: % pin, kWh đã nạp, thời gian còn lại,
/// nút giả lập Check-in / Đến trễ 15 phút / Rời sớm.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});
  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  int _tab = 0;
  int _version = 3;
  String _status = 'CHARGING';
  String _updated = '09:15';
  String _note =
      'Đang tạm dừng trong giờ cao điểm 09:30–11:30, sạc tiếp lúc 11:30 theo lịch v3.';
  bool _done = false;

  void _event(String kind) {
    setState(() {
      switch (kind) {
        case 'checkin':
          _status = 'CHARGING';
          _updated = '09:16';
          _note =
              'Đã check-in tại cổng P3. Phần đã sạc được giữ nguyên, lịch v$_version không đổi.';
        case 'late':
          _version++;
          _updated = '09:20';
          _note =
              'Đã báo đến trễ 15 phút: hệ thống đóng băng slot đã chạy, xếp lại phần còn lại → lịch v$_version, dự kiến 80% lúc 12:30.';
        case 'stop':
          _done = true;
          _status = 'DONE';
          _updated = '09:22';
          _note =
              'Đã dừng sạc sớm ở 65%. Slot tương lai chuyển is_active = false và được giải phóng cho yêu cầu khác.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return UserScaffold(
      tab: UserTab.bookings,
      gap: 14,
      children: [
        Text('Lịch đặt của tôi', style: AppFonts.display(size: 26)),
        Segmented(
          items: const ['Đang diễn ra', 'Sắp tới', 'Lịch sử'],
          selected: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        if (_tab == 0) ...[
          _liveCard(),
          Text('Sắp tới', style: AppFonts.display(size: 19)),
          for (final b in Mock.upcoming) _BookingRow(item: b),
        ] else if (_tab == 1) ...[
          for (final b in Mock.upcoming) _BookingRow(item: b),
          AppCard(
            onTap: () => context.go('/schedule'),
            child: const Row(
              children: [
                DateBadge(day: '05', month: 'TH12'),
                Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BoldText('Nguyễn Văn Linh · P3'),
                      Gap(3),
                      MutedText('Đỗ 08:00 – 17:30 · lịch v3 chờ xác nhận'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          for (final (d, m, t, s, c) in const [
            (
              '02',
              'TH12',
              'Nguyễn Văn Linh · P1',
              '18,4 kWh · 54.160 đ',
              'DONE',
            ),
            ('28', 'TH11', 'Bạch Đằng · P2', '12,1 kWh · 34.040 đ', 'DONE'),
            (
              '25',
              'TH11',
              'Bạch Đằng · P3',
              'Không đến trong 30 phút',
              'NO_SHOW',
            ),
            (
              '20',
              'TH11',
              'Nguyễn Văn Linh · P4',
              'Hủy trước giờ đến',
              'CANCELLED',
            ),
          ])
            _BookingRow(
              item: BookingItem(
                day: d,
                month: m,
                title: t,
                subtitle: s,
                status: c,
              ),
              history: true,
            ),
        ],
      ],
    );
  }

  Widget _liveCard() {
    final soc = _done ? .65 : .65;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.blue, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _done
                  ? Pill.success('✓ DONE · cổng P3')
                  : Pill(
                      '● $_status · cổng P3',
                      bg: AppColors.sky100,
                      fg: AppColors.blue,
                    ),
              const Spacer(),
              Flexible(
                child: MutedText(
                  'Lịch v$_version · cập nhật $_updated',
                  size: 12,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const Gap(12),
          MutedText('Trạm ShareGrid Nguyễn Văn Linh · VFe34 Gia đình'),
          const Gap(8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${(soc * 100).round()}%',
                style: AppFonts.numbers(size: 44),
              ),
              const Spacer(),
              MutedText('Mục tiêu 80%'),
            ],
          ),
          const Gap(10),
          Semantics(
            label: 'Tiến độ sạc 65% trên mục tiêu 80%',
            child: SizedBox(
              height: 20,
              child: LayoutBuilder(
                builder: (context, c) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ProgressBar(
                      soc,
                      height: 12,
                      track: const Color(0xFFE6EAF2),
                    ),
                    Positioned(
                      left: c.maxWidth * .8,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Gap(12),
          const Divider(color: AppColors.divider, height: 1),
          const Gap(12),
          Row(
            children: [
              _Kv('Đã nạp', '15,9 / 22,8 kWh'),
              _Kv('Còn lại', _done ? '—' : '≈ 45 phút'),
              _Kv('Tạm tính', '38.200 đ'),
            ],
          ),
          const Gap(12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warningBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _note,
              style: AppFonts.body(
                size: 12,
                color: const Color(0xFF7A3E06),
                height: 1.5,
              ),
            ),
          ),
          const Gap(12),
          Text(
            'NÚT GIẢ LẬP CHO DEMO',
            style: AppFonts.body(
              size: 11,
              weight: FontWeight.w700,
              color: AppColors.muted,
            ).copyWith(letterSpacing: .7),
          ),
          const Gap(6),
          Row(
            children: [
              _DemoButton('Check-in tại trạm', () => _event('checkin')),
              const Gap(6),
              _DemoButton('Đến trễ 15 phút', () => _event('late')),
              const Gap(6),
              _DemoButton('Rời sớm / Dừng', () => _event('stop'), danger: true),
            ],
          ),
          const Gap(6),
          MutedText(
            'Mỗi thao tác gửi sự kiện để hệ thống giữ phần đã sạc, cập nhật năng lượng còn lại và xếp lại các slot tương lai.',
            size: 11,
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(label, size: 11),
        Text(value, style: AppFonts.body(size: 13, weight: FontWeight.w700)),
      ],
    ),
  );
}

class _DemoButton extends StatelessWidget {
  const _DemoButton(this.label, this.onTap, {this.danger = false});
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: danger ? AppColors.redBg : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: danger ? const Color(0xFFF3B4B6) : AppColors.border,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppFonts.body(
              size: 11,
              weight: FontWeight.w700,
              color: danger ? AppColors.red : AppColors.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.item, this.history = false});
  final BookingItem item;
  final bool history;

  @override
  Widget build(BuildContext context) {
    final pill = switch (item.status) {
      'DONE' => Pill.neutral('DONE'),
      'NO_SHOW' => Pill.danger('NO_SHOW'),
      'CANCELLED' => Pill.neutral('CANCELLED'),
      _ when item.warn => Pill.warning(item.status),
      _ => Pill.success(item.status),
    };
    return AppCard(
      child: Row(
        children: [
          DateBadge(day: item.day, month: item.month, warn: item.warn),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BoldText(item.title, maxLines: 1),
                const Gap(3),
                MutedText(item.subtitle),
              ],
            ),
          ),
          const Gap(8),
          pill,
        ],
      ),
    );
  }
}
