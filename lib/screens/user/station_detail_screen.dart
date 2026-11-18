import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U4 – Chi tiết trạm: thông tin, cổng, trần trạm, biểu giá theo khung giờ.
class StationDetailScreen extends StatelessWidget {
  const StationDetailScreen({super.key, this.station = Mock.nguyenVanLinh});
  final Station station;

  @override
  Widget build(BuildContext context) {
    final s = station;
    final active = s.ports.where((p) => p.status == PortStatus.active).length;
    return UserScaffold(
      padding: EdgeInsets.zero,
      gap: 0,
      actionBar: GlassActionBar(
        children: [
          const Gap(12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MutedText('Giá hiện tại', size: 12),
              Text('2.400 đ/kWh', style: AppFonts.numbers(size: 16)),
            ],
          ),
          const Gap(4),
          Expanded(
            child: AppButton(
              label: 'Đặt lịch sạc',
              radius: 999,
              onPressed: () => context.go('/booking'),
            ),
          ),
        ],
      ),
      children: [
        Container(
          height: 200,
          color: const Color(0xFFDCE3EF),
          padding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Positioned(
                left: 2,
                top: 6,
                child: CircleIconButton(
                  Icons.arrow_back_rounded,
                  tooltip: 'Quay lại',
                  onTap: () => context.go('/map'),
                ),
              ),
              const Positioned(
                right: 2,
                top: 6,
                child: CircleIconButton(
                  Icons.favorite_border_rounded,
                  tooltip: 'Lưu trạm yêu thích',
                ),
              ),
              const Center(
                child: Icon(
                  AppIcons.station,
                  size: 64,
                  color: Color(0xFFB9C4D8),
                ),
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: Pill(
                  '1 / 8 ảnh',
                  bg: AppColors.navy.withValues(alpha: .7),
                  fg: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill.success('✓ ACTIVE · đã xác minh'),
                  Pill.neutral('Nguồn: REAL'),
                ],
              ),
              const Gap(8),
              Text(s.name, style: AppFonts.display(size: 25, height: 1.2)),
              const Gap(4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BoldText(vnDec(s.rating), size: 14),
                  const Gap(5),
                  for (var i = 0; i < 5; i++)
                    const Icon(
                      AppIcons.star,
                      size: 15,
                      color: AppColors.chart2,
                    ),
                  const Gap(5),
                  MutedText(
                    '(${s.reviews}) · ${s.vehicles} · ${vnDec(s.distanceKm)} km',
                    size: 14,
                  ),
                ],
              ),
              const Gap(16),
              Row(
                children: [
                  _RoundAction(AppIcons.route, 'Chỉ đường', primary: true),
                  _RoundAction(
                    AppIcons.calendar,
                    'Đặt lịch',
                    onTap: () => context.go('/booking'),
                  ),
                  _RoundAction(Icons.call_outlined, 'Gọi'),
                  _RoundAction(Icons.bookmark_border_rounded, 'Lưu'),
                ],
              ),
              const Gap(10),
              _Info(AppIcons.pin, Text('${s.address} · cụm Hải Châu')),
              _Info(
                AppIcons.clock,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: s.hours,
                        style: AppFonts.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      const TextSpan(text: ' · phiên tối đa 360 phút'),
                    ],
                  ),
                ),
              ),
              _Info(
                AppIcons.money,
                Text(
                  'Phí dịch vụ ${vnInt(s.feeVnd)} đ/phiên · tiền điện theo biểu giá cụm',
                ),
              ),
              _Info(
                AppIcons.bolt,
                Text(
                  'Trần công suất trạm ${vnDec(s.capKw, 0)} kW (tổng các cổng đang phát không vượt mức này)',
                ),
                last: true,
              ),
              const Gap(14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text('Cổng sạc', style: AppFonts.display(size: 19)),
                  ),
                  MutedText('$active/${s.ports.length} hoạt động', size: 12),
                ],
              ),
              for (final p in s.ports)
                _PortRow(port: p, last: p == s.ports.last),
              const Gap(14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      'Biểu giá điện hôm nay',
                      style: AppFonts.display(size: 19),
                    ),
                  ),
                  MutedText('đ/kWh · ngày thường', size: 12),
                ],
              ),
              const Gap(8),
              const TariffStepChart(),
              const Gap(8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  const LegendDot(AppColors.offPeak, 'Thấp điểm'),
                  const LegendDot(AppColors.normal, 'Bình thường'),
                  const LegendDot(AppColors.peak, 'Cao điểm'),
                  MutedText('Nguồn: biểu giá TOU mẫu (EVN)', size: 11),
                ],
              ),
              const Gap(14),
              Text('Giờ đông khách', style: AppFonts.display(size: 19)),
              const Gap(8),
              BarChart(
                values: Mock.popularTimes,
                xLabels: [for (var h = 6; h <= 22; h++) '${h}h'],
                highlight: 3,
                height: 120,
                semantics: 'Mức độ đông khách theo giờ từ 6h đến 22h',
              ),
              const Gap(14),
              AppCard(
                radius: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.sky100,
                          child: Text(
                            'TL',
                            style: AppFonts.body(
                              size: 12,
                              weight: FontWeight.w700,
                              color: AppColors.blue,
                            ),
                          ),
                        ),
                        const Gap(10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const BoldText('Thu Linh', size: 13),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '★★★★★',
                                    style: AppFonts.body(
                                      size: 12,
                                      color: AppColors.chart2,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' · 2 tuần trước',
                                    style: AppFonts.body(
                                      size: 12,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Gap(6),
                    MutedText(
                      'Đặt lịch trước nên tới là có cổng ngay, lịch còn tự tránh giờ cao điểm nên rẻ hơn hẳn.',
                      color: AppColors.body,
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
}

class _RoundAction extends StatelessWidget {
  const _RoundAction(this.icon, this.label, {this.primary = false, this.onTap});
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap ?? () {},
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primary ? AppColors.blue : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: primary ? AppColors.blue : AppColors.border,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: primary ? Colors.white : AppColors.blue,
            ),
          ),
          const Gap(6),
          Text(
            label,
            style: AppFonts.body(
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.blue,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.child, {this.last = false});
  final IconData icon;
  final Widget child;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.blue),
        const Gap(14),
        Expanded(
          child: DefaultTextStyle.merge(
            style: AppFonts.body(size: 14, color: AppColors.ink, height: 1.4),
            child: child,
          ),
        ),
      ],
    ),
  );
}

class _PortRow extends StatelessWidget {
  const _PortRow({required this.port, this.last = false});
  final Port port;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = port;
    final maint = p.status != PortStatus.active;
    final kw = p.minKw == p.maxKw
        ? '${vnDec(p.maxKw, 1)} kW'
        : '${vnDec(p.minKw, 1)}–${vnDec(p.maxKw, 0)} kW';
    final pill = maint
        ? Pill.warning(p.statusNote ?? 'Bảo trì')
        : p.inUse
        ? const Pill('Đang sạc', bg: AppColors.sky100, fg: AppColors.blue)
        : Pill.success('Trống');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: maint ? AppColors.warningBg : AppColors.sky100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              p.code,
              style: AppFonts.body(
                size: 14,
                weight: FontWeight.w800,
                color: maint ? AppColors.warning : AppColors.blue,
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BoldText('${p.connector} · $kw', size: 14),
                MutedText(
                  p.control == 'CONTINUOUS'
                      ? 'Điều chỉnh liên tục'
                      : 'Bật/tắt cố định (xe máy)',
                  size: 12,
                ),
              ],
            ),
          ),
          pill,
        ],
      ),
    );
  }
}
