import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// Trang chủ USER: xe mặc định, biểu giá hôm nay, lối tắt, trạm gần, lịch sắp tới.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final car = Mock.vehicles.first;
    return UserScaffold(
      tab: UserTab.home,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: AppColors.blue,
                      ),
                      const Gap(4),
                      MutedText('Hải Châu, Đà Nẵng ▾', weight: FontWeight.w600),
                    ],
                  ),
                  const Gap(2),
                  Text('Chào buổi sáng, An', style: AppFonts.display(size: 26)),
                ],
              ),
            ),
            CircleIconButton(
              AppIcons.bell,
              badge: true,
              tooltip: 'Thông báo',
              onTap: () => context.go('/notifications'),
            ),
          ],
        ),
        _CarCard(vehicle: car),
        AppCard(
          onTap: () => context.go('/station'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: BoldText('Biểu giá điện hôm nay')),
                  Pill.neutral('Cụm Hải Châu'),
                ],
              ),
              const Gap(10),
              const TariffStrip(),
              const Gap(8),
              Wrap(
                spacing: 12,
                children: const [
                  LegendDot(AppColors.offPeak, '1.600 đ'),
                  LegendDot(AppColors.normal, '2.400 đ'),
                  LegendDot(AppColors.peak, '4.000 đ'),
                ],
              ),
              const Gap(10),
              Row(
                children: [
                  const Icon(AppIcons.ai, size: 18, color: AppColors.blue),
                  const Gap(8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: AppFonts.body(size: 13, color: AppColors.body),
                        children: [
                          const TextSpan(
                            text: 'Đặt lịch để hệ thống tự tránh ',
                          ),
                          TextSpan(
                            text: '09:30–11:30',
                            style: AppFonts.body(
                              size: 13,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' và '),
                          TextSpan(
                            text: '17:00–20:00',
                            style: AppFonts.body(
                              size: 13,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            for (final (icon, label, route) in const [
              (AppIcons.map, 'Bản đồ', '/map'),
              (AppIcons.calendar, 'Đặt lịch', '/booking'),
              (AppIcons.ai, 'Thông minh', '/schedule'),
              (AppIcons.car, 'Xe của tôi', '/garage'),
            ])
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.go(route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        IconBox(
                          icon,
                          size: 58,
                          radius: 18,
                          iconSize: 26,
                          bg: AppColors.sky200,
                          fg: AppColors.blue,
                        ),
                        const Gap(6),
                        Text(
                          label,
                          style: AppFonts.body(
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        SectionHeader(
          'Trạm gần bạn',
          action: 'Xem bản đồ',
          onAction: () => context.go('/map'),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NearStation(
                status: '● 3 cổng trống',
                statusColor: AppColors.success,
                distance: '1,4 km',
                name: 'ShareGrid Nguyễn Văn Linh',
                meta: 'CCS2 · Type2 · AC_HOME · 24/7',
              ),
              const Gap(10),
              _NearStation(
                status: '● Gần đầy',
                statusColor: AppColors.warning,
                distance: '2,1 km',
                name: 'ShareGrid Bạch Đằng',
                meta: 'CCS2 · AC_HOME · 06:00–23:00',
              ),
              const Gap(10),
              _NearStation(
                status: '● 2 cổng trống',
                statusColor: AppColors.success,
                distance: '3,2 km',
                name: 'Trạm công cộng Điện Biên Phủ',
                meta: 'CCS2 · Type2 · 06:00–22:00',
              ),
            ],
          ),
        ),
        SectionHeader(
          'Lịch sắp tới',
          action: 'Tất cả',
          onAction: () => context.go('/sessions'),
        ),
        AppCard(
          onTap: () => context.go('/schedule'),
          child: Row(
            children: [
              const DateBadge(day: '05', month: 'TH12'),
              const Gap(12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BoldText('Nguyễn Văn Linh · cổng P3'),
                    Gap(3),
                    MutedText('Sạc 08:00–12:15 · ≈ 54.700 đ'),
                  ],
                ),
              ),
              Pill.success('✓ Đã xác nhận'),
            ],
          ),
        ),
      ],
    );
  }
}

class _CarCard extends StatelessWidget {
  const _CarCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.sky200,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -6,
            bottom: 8,
            child: Icon(
              AppIcons.car,
              size: 84,
              color: Colors.white.withValues(alpha: .55),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: MutedText(
                      '${vehicle.nickname} · ${vehicle.plate}',
                      color: AppColors.skyInk,
                    ),
                  ),
                  const Pill('Đang đỗ', bg: Colors.white, fg: AppColors.skyInk),
                ],
              ),
              const Gap(12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '46%',
                    style: AppFonts.numbers(size: 46, color: AppColors.skyInk),
                  ),
                  const Gap(10),
                  Flexible(
                    child: MutedText(
                      '≈ 180 km còn lại',
                      size: 14,
                      color: AppColors.skyInk,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const Gap(12),
              ProgressBar(.46, track: Colors.white.withValues(alpha: .75)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NearStation extends StatelessWidget {
  const _NearStation({
    required this.status,
    required this.statusColor,
    required this.distance,
    required this.name,
    required this.meta,
  });
  final String status;
  final Color statusColor;
  final String distance;
  final String name;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      width: 212,
      padding: const EdgeInsets.all(12),
      onTap: () => context.go('/station'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: AppFonts.body(
                    size: 12,
                    weight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              MutedText(distance, size: 12),
            ],
          ),
          const Gap(6),
          BoldText(name, maxLines: 2),
          const Gap(4),
          MutedText(meta, size: 12, maxLines: 1),
        ],
      ),
    );
  }
}

/// Ô ngày (05 / TH12) dùng ở lịch sắp tới.
class DateBadge extends StatelessWidget {
  const DateBadge({
    super.key,
    required this.day,
    required this.month,
    this.warn = false,
  });
  final String day;
  final String month;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final fg = warn ? AppColors.warning : AppColors.blue;
    return Container(
      width: 52,
      height: 56,
      decoration: BoxDecoration(
        color: warn ? AppColors.warningBg : AppColors.sky100,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(day, style: AppFonts.numbers(size: 19, color: fg)),
          Text(
            month,
            style: AppFonts.body(size: 11, weight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}
