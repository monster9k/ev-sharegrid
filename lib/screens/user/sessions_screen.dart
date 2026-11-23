import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

enum SessionFilter {
  all('Tất cả'),
  charging('Đang sạc'),
  upcoming('Sắp tới'),
  completed('Hoàn tất');

  const SessionFilter(this.label);
  final String label;
}

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, this.client});

  final ApiClient? client;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  late var _requests = _api.role == 'USER' ? _api.getMyRequests() : null;
  final _checkingIn = <int>{};
  final _responses = <int, Map<String, dynamic>>{};
  SessionFilter _filter = SessionFilter.all;
  Object? _error;

  Future<void> _checkIn(int id) async {
    setState(() {
      _checkingIn.add(id);
      _error = null;
    });
    try {
      final result = await _api.checkinRequest(id);
      if (mounted) setState(() => _responses[id] = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() {
          _checkingIn.remove(id);
          _requests = _api.role == 'USER' ? _api.getMyRequests() : null;
        });
      }
    }
  }

  String _time(Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '');
    return time == null
        ? '—'
        : '${formatChargingDate(vietnamWallTime(time))} · ${formatVietnamTime(time)}';
  }

  String _formatVnd(num? value) {
    if (value == null) return '—';
    final rounded = value.round();
    final s = rounded.abs().toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(s[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buffer.toString()} đ';
  }

  bool _filterMatches(Map<String, dynamic> row) {
    final id = (row['request_id'] as num?)?.toInt() ?? 0;
    final response = _responses[id];
    final status = (response?['status'] ?? row['status'] ?? '')
        .toString()
        .toUpperCase();
    return switch (_filter) {
      SessionFilter.all => true,
      SessionFilter.charging => status == 'CHARGING' || status == 'IN_PROGRESS',
      SessionFilter.upcoming =>
        status == 'SCHEDULED' || status == 'CONFIRMED' || status == 'PENDING',
      SessionFilter.completed =>
        status == 'DONE' ||
            status == 'COMPLETED' ||
            status == 'CANCELLED' ||
            status == 'FAILED' ||
            status == 'NO_SHOW',
    };
  }

  Color _statusBg(String status) {
    switch (status.toUpperCase()) {
      case 'CONFIRMED':
      case 'DONE':
      case 'COMPLETED':
        return AppColors.successBg;
      case 'CHARGING':
      case 'IN_PROGRESS':
        return AppColors.sky100;
      case 'SCHEDULED':
      case 'PENDING':
        return AppColors.warningBg;
      case 'CANCELLED':
      case 'FAILED':
      case 'NO_SHOW':
        return AppColors.redBg;
      default:
        return AppColors.neutralBg;
    }
  }

  Color _statusFg(String status) {
    switch (status.toUpperCase()) {
      case 'CONFIRMED':
      case 'DONE':
      case 'COMPLETED':
        return AppColors.success;
      case 'CHARGING':
      case 'IN_PROGRESS':
        return AppColors.blue;
      case 'SCHEDULED':
      case 'PENDING':
        return AppColors.warning;
      case 'CANCELLED':
      case 'FAILED':
      case 'NO_SHOW':
        return AppColors.red;
      default:
        return AppColors.navy;
    }
  }

  @override
  Widget build(BuildContext context) => UserScaffold(
    tab: UserTab.bookings,
    showSimulationTag: false,
    children: [
      Text('Lịch đặt của tôi', style: AppFonts.display(size: 26)),
      if (_error != null) ApiErrorCard(error: _error!),
      if (_requests == null)
        const SignInCard('Đăng nhập để xem lịch sạc.')
      else
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _requests,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ApiErrorCard(
                error: snapshot.error!,
                onRetry: () {
                  final requests = _api.getMyRequests();
                  setState(() {
                    _requests = requests;
                  });
                },
              );
            }
            final list = snapshot.data;
            if (list == null) return const LinearProgressIndicator();

            final filtered = list.where(_filterMatches).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in SessionFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            selectedColor: AppColors.sky200,
                            checkmarkColor: AppColors.blue,
                            labelStyle: AppFonts.body(
                              size: 13,
                              weight: _filter == filter
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _filter == filter
                                  ? AppColors.blue800
                                  : AppColors.body,
                            ),
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                const Gap(12),
                if (filtered.isEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: AppCard(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 40,
                                color: AppColors.muted,
                              ),
                              const Gap(12),
                              const BoldText('Chưa có lịch sạc.', size: 15),
                              const Gap(4),
                              MutedText(
                                _filter == SessionFilter.all
                                    ? 'Bạn chưa có yêu cầu sạc nào được tạo.'
                                    : 'Không có yêu cầu nào ở trạng thái "${_filter.label}".',
                                size: 13,
                              ),
                              const Gap(16),
                              AppButton(
                                label: 'Đặt lịch sạc mới',
                                radius: 999,
                                fontSize: 13,
                                onPressed: () => context.go('/booking'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  for (final row in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _booking(row),
                    ),
              ],
            );
          },
        ),
    ],
  );

  Widget _booking(Map<String, dynamic> row) {
    final id = (row['request_id'] as num).toInt();
    final response = _responses[id];
    final status = (response?['status'] ?? row['status'] ?? '—').toString();
    final busy = _checkingIn.contains(id);
    final canCheckIn = status == 'SCHEDULED' || status == 'CONFIRMED';
    final hasPortOrSession =
        row['port_code'] != null ||
        row['port_id'] != null ||
        response?['session_id'] != null;
    final hasEnergyOrCost =
        row['energy_needed_kwh'] != null || row['estimated_cost_vnd'] != null;

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hàng 1: Tên trạm bên trái + Pill trạng thái bên phải
            Row(
              children: [
                Expanded(
                  child: BoldText(
                    '#$id · ${row['station_name'] ?? 'Trạm sạc'}',
                    size: 15,
                    maxLines: 1,
                  ),
                ),
                const Gap(8),
                Pill(status, bg: _statusBg(status), fg: _statusFg(status)),
              ],
            ),
            const Gap(10),
            // Hàng 2: Thời gian Đến - Rời kèm icon, cổng/phiên sạc, năng lượng/chi phí
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 15,
                        color: AppColors.blue,
                      ),
                      const Gap(6),
                      Expanded(
                        child: Text(
                          'Đến ${_time(row['arrival_time'])}  —  Rời ${_time(row['departure_time'])}',
                          style: AppFonts.body(size: 12, color: AppColors.navy),
                        ),
                      ),
                    ],
                  ),
                  if (hasPortOrSession) ...[
                    const Gap(6),
                    Row(
                      children: [
                        const Icon(
                          Icons.ev_station_outlined,
                          size: 15,
                          color: AppColors.muted,
                        ),
                        const Gap(6),
                        Expanded(
                          child: Text(
                            [
                              if (row['port_code'] != null ||
                                  row['port_id'] != null)
                                'Cổng ${row['port_code'] ?? row['port_id']}',
                              if (response?['session_id']
                                  case final num session)
                                'Phiên sạc #$session',
                            ].join(' · '),
                            style: AppFonts.body(
                              size: 12,
                              color: AppColors.body,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (hasEnergyOrCost) ...[
                    const Gap(6),
                    Row(
                      children: [
                        const Icon(
                          Icons.bolt_outlined,
                          size: 15,
                          color: AppColors.muted,
                        ),
                        const Gap(6),
                        Expanded(
                          child: Text(
                            [
                              if (row['energy_needed_kwh'] != null)
                                'Nhu cầu: ${row['energy_needed_kwh']} kWh',
                              if (row['estimated_cost_vnd'] != null)
                                'Chi phí: ${_formatVnd(row['estimated_cost_vnd'] as num)}',
                            ].join(' · '),
                            style: AppFonts.body(
                              size: 12,
                              color: AppColors.body,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Gap(12),
            // Hàng 3: Cụm nút hành động căn đều ngang nhau
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Xem lịch sạc',
                    kind: canCheckIn
                        ? AppButtonKind.outline
                        : AppButtonKind.primary,
                    radius: 999,
                    fontSize: 13,
                    onPressed: () => context.go('/schedule?requestId=$id'),
                  ),
                ),
                if (canCheckIn) ...[
                  const Gap(10),
                  Expanded(
                    child: AppButton(
                      label: busy ? 'Đang check-in…' : 'Check-in tại trạm',
                      radius: 999,
                      fontSize: 13,
                      onPressed: busy ? null : () => _checkIn(id),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
