import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

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
                onRetry: () => setState(() => _requests = _api.getMyRequests()),
              );
            }
            final list = snapshot.data;
            if (list == null) return const LinearProgressIndicator();
            if (list.isEmpty) {
              return const AppCard(child: MutedText('Chưa có lịch sạc.'));
            }
            return Column(
              children: [
                for (final row in list)
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
    final status = response?['status'] ?? row['status'];
    final busy = _checkingIn.contains(id);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BoldText('#$id · ${row['station_name'] ?? 'Trạm sạc'}'),
          const Gap(4),
          MutedText('Đến ${_time(row['arrival_time'])}'),
          MutedText('Rời ${_time(row['departure_time'])}'),
          const Gap(8),
          Pill(status?.toString() ?? '—'),
          if (response?['session_id'] case final num session)
            MutedText('Đã check-in · phiên sạc #$session'),
          TextButton(
            onPressed: () => context.go('/schedule?requestId=$id'),
            child: const Text('Xem lịch sạc'),
          ),
          if (status == 'SCHEDULED' || status == 'CONFIRMED')
            AppButton(
              label: busy ? 'Đang check-in…' : 'Check-in tại trạm',
              onPressed: busy ? null : () => _checkIn(id),
            ),
        ],
      ),
    );
  }
}
