import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({super.key, required this.stationId, this.client});

  final int? stationId;
  final ApiClient? client;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late Future<Map<String, dynamic>>? _station = _load();

  Future<Map<String, dynamic>>? _load() {
    final id = widget.stationId;
    return id == null || id <= 0
        ? null
        : (widget.client ?? apiClient).getStation(id);
  }

  Future<void> _openDirections(num lat, num lng) async {
    final uri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$lat,$lng',
    });
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Some devices have no handler for external links.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _station,
    builder: (context, snapshot) {
      final station = snapshot.data;
      final lat = station?['lat'];
      final lng = station?['lng'];
      final ports = (station?['ports'] as List?)?.whereType<Map>() ?? const [];
      final active = station?['status'] == 'ACTIVE';
      return UserScaffold(
        tab: UserTab.map,
        showSimulationTag: false,
        actionBar: station != null && active
            ? GlassActionBar(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Đặt lịch sạc',
                      icon: AppIcons.calendar,
                      radius: 999,
                      onPressed: () =>
                          context.go('/booking?stationId=${widget.stationId}'),
                    ),
                  ),
                ],
              )
            : null,
        children: [
          MobileHeader(
            title: 'Chi tiết trạm',
            onBack: () => context.go('/map'),
          ),
          if (_station == null)
            const AppCard(child: MutedText('Mã trạm không hợp lệ.'))
          else if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            ApiErrorCard(
              error: snapshot.error!,
              onRetry: () => setState(() => _station = _load()),
            )
          else if (station != null) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (active)
                    Pill.success('Đang hoạt động')
                  else
                    const Pill('Chưa hoạt động'),
                  const Gap(10),
                  Text(
                    station['name'].toString(),
                    style: AppFonts.display(size: 23),
                  ),
                  const Gap(6),
                  MutedText(
                    station['address']?.toString() ?? 'Chưa có địa chỉ',
                  ),
                  if (station['is_24h'] == true)
                    const MutedText('Mở 24/7')
                  else if (station['open_time'] != null &&
                      station['close_time'] != null)
                    MutedText(
                      '${station['open_time']} – ${station['close_time']}',
                    ),
                  if (station['station_power_kw'] case final num kw)
                    MutedText('Công suất trạm ${vnDec(kw)} kW'),
                  if (lat is num && lng is num)
                    TextButton.icon(
                      icon: const Icon(Icons.directions_outlined),
                      label: const Text('Chỉ đường'),
                      onPressed: () => _openDirections(lat, lng),
                    ),
                ],
              ),
            ),
            const SectionHeader('Cổng sạc'),
            if (ports.isEmpty)
              const AppCard(
                child: MutedText('Chưa có cổng sạc trong danh mục.'),
              ),
            for (final port in ports)
              AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const IconBox(AppIcons.plug, size: 38),
                  title: BoldText(
                    '${port['port_code']} · ${port['connector_type']}',
                  ),
                  subtitle: MutedText('${port['max_power_kw'] ?? '—'} kW'),
                  trailing: MutedText(
                    port['status']?.toString() ?? '—',
                    size: 11,
                  ),
                ),
              ),
          ],
        ],
      );
    },
  );
}
