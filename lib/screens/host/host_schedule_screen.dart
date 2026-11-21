import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';

class HostScheduleScreen extends StatefulWidget {
  const HostScheduleScreen({super.key, this.stationId, this.client});
  final int? stationId;
  final ApiClient? client;

  @override
  State<HostScheduleScreen> createState() => _HostScheduleScreenState();
}

class _HostScheduleScreenState extends PortalRowsState<HostScheduleScreen> {
  ApiClient get _api => widget.client ?? apiClient;

  @override
  Future<List<PortalRow>> loadRows() => _api.getHostStations();

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.host,
    route: '/host/schedule',
    eyebrow: 'Cổng chủ trạm',
    title: 'Lịch sạc tại trạm',
    simulationLabel: null,
    children: [
      dataPane((stations) {
        if (stations.isEmpty) {
          return const AppCard(
            child: MutedText('Chưa có trạm của tài khoản này.'),
          );
        }
        final station = widget.stationId == null
            ? stations.first
            : stations
                  .where((row) => row['station_id'] == widget.stationId)
                  .firstOrNull;
        if (station == null) {
          return const AppCard(
            child: MutedText('Trạm không thuộc tài khoản này.'),
          );
        }
        final stationId = (station['station_id'] as num).toInt();
        return Column(
          children: [
            PortalStationPicker(
              stations: stations,
              stationId: stationId,
              onChanged: (id) => context.go('/host/schedule?stationId=$id'),
            ),
            const Gap(12),
            _StationSlots(
              key: ValueKey(stationId),
              client: _api,
              stationId: stationId,
            ),
          ],
        );
      }),
    ],
  );
}

class _StationSlots extends StatefulWidget {
  const _StationSlots({
    super.key,
    required this.client,
    required this.stationId,
  });
  final ApiClient client;
  final int stationId;

  @override
  State<_StationSlots> createState() => _StationSlotsState();
}

class _StationSlotsState extends State<_StationSlots> {
  late var _slots = widget.client.getHostSchedule(widget.stationId);

  String _time(PortalRow slot) {
    final start = DateTime.tryParse(slot['slot_start']?.toString() ?? '');
    final end = DateTime.tryParse(slot['slot_end']?.toString() ?? '');
    if (start == null || end == null) return '—';
    return '${formatChargingDate(vietnamWallTime(start))} · ${formatVietnamTime(start)}–${formatVietnamTime(end)}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PortalRow>>(
    future: _slots,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LinearProgressIndicator();
      }
      if (snapshot.hasError) {
        return ApiErrorCard(
          error: snapshot.error!,
          onRetry: () => setState(
            () => _slots = widget.client.getHostSchedule(widget.stationId),
          ),
        );
      }
      final slots = snapshot.data ?? const [];
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BoldText('Slot đang hiệu lực · ${slots.length}'),
            if (slots.isEmpty)
              const MutedText('Trạm chưa có lịch được phân bổ.'),
            for (final slot in slots)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: BoldText(_time(slot)),
                subtitle: MutedText(
                  'Yêu cầu #${slot['request_id']} · Cổng #${slot['port_id']} · Lịch v${slot['version']}',
                ),
                trailing: MutedText('${slot['power_kw']} kW'),
              ),
          ],
        ),
      );
    },
  );
}
