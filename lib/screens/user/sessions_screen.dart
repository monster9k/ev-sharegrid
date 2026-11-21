import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
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
  late final _requestId = _api.lastRequestId;
  late var _schedule = _requestId == null
      ? null
      : _api.getRequestSchedule(_requestId);
  bool _checkingIn = false;
  Object? _actionError;
  Map<String, dynamic>? _session;

  Future<void> _checkIn(int id) async {
    setState(() {
      _checkingIn = true;
      _actionError = null;
    });
    try {
      final session = await _api.checkinRequest(id);
      if (mounted) setState(() => _session = session);
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _schedule,
    builder: (context, snapshot) {
      final status = _session?['status'] ?? snapshot.data?['status'];
      final id = _requestId;
      return UserScaffold(
        tab: UserTab.bookings,
        showSimulationTag: false,
        children: [
          Text('Lịch đặt của tôi', style: AppFonts.display(size: 26)),
          if (_api.accessToken == null)
            const SignInCard('Đăng nhập để xem lịch sạc.')
          else if (id == null)
            const AppCard(child: MutedText('Chưa có lịch sạc trong phiên này.'))
          else if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            ApiErrorCard(
              error: snapshot.error!,
              onRetry: () =>
                  setState(() => _schedule = _api.getRequestSchedule(id)),
            )
          else
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BoldText('Yêu cầu gần nhất #$id'),
                  const Gap(8),
                  Pill(status?.toString() ?? '—'),
                  if (_session?['session_id'] case final num sessionId)
                    MutedText(
                      'Đã check-in · phiên sạc #$sessionId · cổng ${_session?['port_id']}',
                    ),
                  TextButton(
                    onPressed: () => context.go('/schedule'),
                    child: const Text('Xem lịch sạc'),
                  ),
                  if (status == 'SCHEDULED' || status == 'CONFIRMED')
                    AppButton(
                      label: _checkingIn
                          ? 'Đang check-in…'
                          : 'Check-in tại trạm',
                      onPressed: _checkingIn ? null : () => _checkIn(id),
                    ),
                ],
              ),
            ),
          if (_actionError != null) ApiErrorCard(error: _actionError!),
        ],
      );
    },
  );
}
