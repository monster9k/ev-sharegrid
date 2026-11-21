import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.client});

  final ApiClient? client;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  late var _inbox = _api.accessToken == null ? null : _api.getNotifications();
  final _marking = <int>{};
  Object? _actionError;

  Future<void> _markRead(int id) async {
    setState(() {
      _marking.add(id);
      _actionError = null;
    });
    try {
      await _api.markNotificationRead(id);
      if (mounted) setState(() => _inbox = _api.getNotifications());
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _marking.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _inbox,
        builder: (context, snapshot) => UserScaffold(
          showSimulationTag: false,
          children: [
            MobileHeader(title: 'Thông báo', onBack: () => context.go('/home')),
            if (_inbox == null)
              const SignInCard('Đăng nhập để xem thông báo.')
            else if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (snapshot.hasError)
              ApiErrorCard(
                error: snapshot.error!,
                onRetry: () => setState(() => _inbox = _api.getNotifications()),
              )
            else if (snapshot.data?.isEmpty ?? true)
              const AppCard(child: MutedText('Chưa có thông báo.'))
            else
              for (final item in snapshot.data!) _notification(item),
            if (_actionError != null) ApiErrorCard(error: _actionError!),
          ],
        ),
      );

  Widget _notification(Map<String, dynamic> item) {
    final id = (item['notif_id'] as num?)?.toInt();
    final requestId = (item['request_id'] as num?)?.toInt();
    final timestamp = DateTime.tryParse(item['created_at']?.toString() ?? '');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BoldText(item['title']?.toString() ?? 'Thông báo'),
          if (timestamp != null)
            MutedText(
              '${formatChargingDate(vietnamWallTime(timestamp))} · ${formatVietnamTime(timestamp)}',
              size: 12,
            ),
          const Gap(6),
          Text(item['body']?.toString() ?? '', style: AppFonts.body(size: 14)),
          Wrap(
            children: [
              if (requestId != null && _api.role == 'USER')
                TextButton(
                  onPressed: () => context.go('/schedule?requestId=$requestId'),
                  child: const Text('Xem lịch sạc'),
                ),
              if (id != null && item['read_at'] == null)
                TextButton(
                  onPressed: _marking.contains(id) ? null : () => _markRead(id),
                  child: const Text('Đánh dấu đã đọc'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
