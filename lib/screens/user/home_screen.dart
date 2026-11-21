import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.client});

  final ApiClient? client;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  late var _stations = _api.getStations();
  late final _requestId = _api.lastRequestId;
  late var _schedule = _requestId == null
      ? null
      : _api.getRequestSchedule(_requestId);

  @override
  Widget build(BuildContext context) {
    final fullName = _api.currentUser?['full_name']?.toString();
    final vehicles = (_api.currentUser?['vehicles'] as List?)?.whereType<Map>();
    final vehicle = vehicles?.firstOrNull;
    final requestId = _requestId;
    return UserScaffold(
      tab: UserTab.home,
      showSimulationTag: false,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MutedText('Đà Nẵng'),
                  Text(
                    fullName == null ? 'Chào bạn' : 'Chào $fullName',
                    style: AppFonts.display(size: 26),
                  ),
                ],
              ),
            ),
            CircleIconButton(
              AppIcons.bell,
              tooltip: 'Thông báo',
              onTap: () => context.go('/notifications'),
            ),
          ],
        ),
        if (vehicle != null)
          AppCard(
            color: AppColors.sky200,
            onTap: () => context.go('/garage'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BoldText(
                  '${vehicle['nickname'] ?? vehicle['model_name']} · ${vehicle['plate_number'] ?? '—'}',
                  color: AppColors.skyInk,
                ),
                const Gap(4),
                MutedText(
                  '${vehicle['brand']} ${vehicle['model_name']} · ${vehicle['connector_type']}',
                  color: AppColors.skyInk,
                ),
              ],
            ),
          ),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: BoldText('Khung giờ biểu giá')),
                  SimTag(text: 'Minh họa'),
                ],
              ),
              Gap(10),
              TariffStrip(),
            ],
          ),
        ),
        Row(
          children: [
            for (final (icon, label, route) in const [
              (AppIcons.map, 'Bản đồ', '/map'),
              (AppIcons.calendar, 'Đặt lịch', '/booking'),
              (AppIcons.ai, 'Lịch', '/schedule'),
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
                          size: 52,
                          iconSize: 24,
                          bg: AppColors.sky200,
                          fg: AppColors.skyInk,
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
          'Trạm đang hoạt động',
          action: 'Xem bản đồ',
          onAction: () => context.go('/map'),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _stations,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return ApiErrorCard(
                error: snapshot.error!,
                onRetry: () => setState(() => _stations = _api.getStations()),
              );
            }
            final stations = (snapshot.data ?? const [])
                .where((station) => station['status'] == 'ACTIVE')
                .take(3)
                .toList();
            if (stations.isEmpty) {
              return const AppCard(
                child: MutedText('Chưa có trạm đang hoạt động.'),
              );
            }
            return Column(
              children: [
                for (final station in stations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconBox(AppIcons.station, size: 40),
                    title: BoldText(station['name']?.toString() ?? 'Trạm sạc'),
                    subtitle: MutedText(station['address']?.toString() ?? '—'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        context.go('/station/${station['station_id']}'),
                  ),
              ],
            );
          },
        ),
        SectionHeader(
          'Lịch gần nhất',
          action: 'Lịch đặt',
          onAction: () => context.go('/sessions'),
        ),
        if (requestId == null)
          const AppCard(child: MutedText('Chưa có lịch sạc trong phiên này.'))
        else
          FutureBuilder<Map<String, dynamic>>(
            future: _schedule,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return ApiErrorCard(
                  error: snapshot.error!,
                  onRetry: () => setState(
                    () => _schedule = _api.getRequestSchedule(requestId),
                  ),
                );
              }
              return AppCard(
                onTap: () => context.go('/schedule'),
                child: Row(
                  children: [
                    Expanded(child: BoldText('Yêu cầu #$requestId')),
                    Pill(snapshot.data?['status']?.toString() ?? '—'),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
