import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U6 – Kết quả lịch & giải thích: trạng thái solver, cổng được gán,
/// Gantt slot 15 phút, SOC dự kiến, shortfall, chi phí, explanation, version.
class ScheduleResultScreen extends StatelessWidget {
  const ScheduleResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return UserScaffold(
      gap: 12,
      tab: UserTab.smart,
      actionBar: GlassActionBar(
        children: [
          Expanded(
            flex: 8,
            child: AppButton(
              label: 'Hủy',
              kind: AppButtonKind.ghost,
              radius: 999,
              fontSize: 14,
              onPressed: () => _confirmCancel(context),
            ),
          ),
          Expanded(
            flex: 10,
            child: _OutlineBlue(
              label: 'Sửa',
              onTap: () => context.go('/booking'),
            ),
          ),
          Expanded(
            flex: 16,
            child: AppButton(
              label: 'Xác nhận lịch',
              radius: 999,
              fontSize: 15,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã xác nhận lịch v3 · trạng thái CONFIRMED'),
                  ),
                );
                context.go('/sessions');
              },
            ),
          ),
        ],
      ),
      children: [
        MobileHeader(
          title: 'Kết quả lịch sạc',
          onBack: () => context.go('/booking'),
          trailing: const Pill(
            'Mô phỏng',
            bg: AppColors.border,
            fg: AppColors.muted,
            radius: 6,
            size: 11,
          ),
        ),
        const _Stepper(),
        MutedText('Request #R-5012 · Job #J-2291 · Run #1042', size: 11),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.sky200,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Pill(
                    'OPTIMAL',
                    bg: AppColors.success,
                    fg: Colors.white,
                  ),
                  MutedText(
                    'MILP_MPC · 142 ms · lịch v3',
                    size: 12,
                    color: AppColors.skyInk,
                  ),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'CỔNG',
                          style: AppFonts.body(
                            size: 10,
                            weight: FontWeight.w700,
                            color: AppColors.sky100,
                          ),
                        ),
                        Text(
                          'P3',
                          style: AppFonts.numbers(
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BoldText(
                          'CCS2 · liên tục · tối đa 11 kW',
                          size: 16,
                          color: AppColors.skyInk,
                        ),
                        MutedText(
                          'Sạc 08:00–09:30 và 11:30–12:15',
                          color: AppColors.skyInk,
                        ),
                        MutedText(
                          'Đỗ 08:00 → lấy xe 17:30 (05/12)',
                          color: AppColors.skyInk,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Expanded(child: _Metric('SOC dự kiến', '80%', 'lúc 12:15')),
              Gap(8),
              Expanded(
                child: _Metric(
                  'Điện thiếu',
                  '0,00',
                  'kWh',
                  color: AppColors.success,
                ),
              ),
              Gap(8),
              Expanded(
                child: _Metric('Chi phí điện', '54.700', 'đ + phí DV 10.000'),
              ),
            ],
          ),
        ),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      'Lịch theo slot 15 phút',
                      style: AppFonts.display(size: 17),
                    ),
                  ),
                  MutedText('kW tại cổng P3', size: 12),
                ],
              ),
              const Gap(10),
              const SlotScheduleChart(slots: Mock.schedule),
              const Gap(8),
              const Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  LegendDot(AppColors.blue, 'Công suất cấp'),
                  LegendDot(AppColors.border, 'Bình thường 2.400 đ'),
                  LegendDot(Color(0xFFF3C9A5), 'Cao điểm 4.000 đ'),
                ],
              ),
              const Gap(6),
              const _SlotLine('08:00–08:30 · 11 kW', '5,50 kWh'),
              const _SlotLine(
                '08:30–09:00 · 7,4 kW',
                '3,70 kWh',
                note: '(trạm chạm trần)',
              ),
              const _SlotLine('09:00–09:30 · 11 kW', '5,50 kWh'),
              const _SlotLine(
                '11:30–12:15 · 11 / 11 / 10,3 kW',
                '8,07 kWh',
                last: true,
              ),
            ],
          ),
        ),
        const ExplainBox(
          title: 'Lý do xếp lịch',
          lines: [
            'Xếp vào 08:00–09:30 và 11:30–12:15 ở cổng P3 với giá 2.400 đ/kWh, tránh khung cao điểm 09:30–11:30 (4.000 đ/kWh).',
            'Slot 08:30–09:00 giảm còn 7,4 kW vì trạm đã chạm trần 40 kW.',
            'Dự kiến đạt 80% lúc 12:15, trước giờ lấy xe 17:30.',
          ],
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BoldText('Tối ưu chung với các yêu cầu khác', size: 14),
              const Gap(6),
              Text.rich(
                TextSpan(
                  style: AppFonts.body(
                    size: 13,
                    color: AppColors.body,
                    height: 1.45,
                  ),
                  children: [
                    const TextSpan(text: 'Lần chạy này xếp cùng lúc '),
                    TextSpan(
                      text: '38 yêu cầu',
                      style: AppFonts.body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' đang hoạt động của cụm Hải Châu (cả yêu cầu cũ và mới). Không vượt trần trạm 40 kW, trần cụm 500 kW; các slot đã sạc được giữ nguyên.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy yêu cầu R-5012?'),
        content: const Text(
          'Lịch tương lai sẽ chuyển is_active = false và giải phóng cổng P3. '
          'Các yêu cầu khác trong cụm có thể được xếp lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Giữ lịch'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/sessions');
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Hủy yêu cầu'),
          ),
        ],
      ),
    );
  }
}

class _OutlineBlue extends StatelessWidget {
  const _OutlineBlue({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: .75),
        side: const BorderSide(color: AppColors.blue, width: 1.5),
        shape: const StadiumBorder(),
        foregroundColor: AppColors.blue,
      ),
      child: Text(
        label,
        style: AppFonts.body(
          size: 14,
          weight: FontWeight.w700,
          color: AppColors.blue,
        ),
      ),
    ),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper();

  @override
  Widget build(BuildContext context) {
    Widget step(String label, {String? n}) => Flexible(
      flex: 3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: n == null ? AppColors.successBg : AppColors.bg,
              shape: BoxShape.circle,
            ),
            child: n == null
                ? const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: AppColors.success,
                  )
                : Text(
                    n,
                    style: AppFonts.body(
                      size: 10,
                      weight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
          ),
          const Gap(6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(
                size: 11,
                weight: FontWeight.w700,
                color: n == null ? AppColors.success : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
    Widget line(Color c) => Container(
      width: 14,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      color: c,
    );
    return AppCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          step('Đã nhận'),
          line(AppColors.success),
          step('Đã xếp lịch'),
          line(AppColors.border),
          step('Chờ xác nhận', n: '3'),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.note, {this.color});
  final String label;
  final String value;
  final String note;
  final Color? color;

  @override
  Widget build(BuildContext context) => AppCard(
    radius: 16,
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(label, size: 11, weight: FontWeight.w600, maxLines: 1),
        const Gap(2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppFonts.numbers(size: 20, color: color ?? AppColors.ink),
          ),
        ),
        MutedText(note, size: 11, maxLines: 2),
      ],
    ),
  );
}

class _SlotLine extends StatelessWidget {
  const _SlotLine(this.left, this.right, {this.note, this.last = false});
  final String left;
  final String right;
  final String? note;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              style: AppFonts.body(size: 13),
              children: [
                TextSpan(text: left),
                if (note != null)
                  TextSpan(
                    text: ' $note',
                    style: AppFonts.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.warning,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Text(right, style: AppFonts.body(size: 13, weight: FontWeight.w600)),
      ],
    ),
  );
}
