import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';
import '../admin/admin_common.dart';

class HostPortsScreen extends StatefulWidget {
  const HostPortsScreen({super.key, this.stationId, this.client});
  final int? stationId;
  final ApiClient? client;

  @override
  State<HostPortsScreen> createState() => _HostPortsScreenState();
}

class _HostPortsScreenState extends PortalRowsState<HostPortsScreen> {
  ApiClient get _api => widget.client ?? apiClient;

  @override
  Future<List<PortalRow>> loadRows() => _api.getHostStations();

  Future<void> _addPort(int stationId) async {
    final form = await askPortalFields(context, 'Thêm cổng sạc', const {
      'port_code': PortalField('Mã cổng'),
      'connector_type': PortalField(
        'Đầu nối',
        choices: ['CCS2', 'Type2', 'CHAdeMO', 'AC_HOME'],
      ),
      'control_type': PortalField(
        'Kiểu điều khiển',
        choices: ['CONTINUOUS', 'ON_OFF_SWITCH'],
      ),
      'min_power_kw': PortalField(
        'Công suất nhỏ nhất (kW)',
        initial: '0',
        isNumber: true,
      ),
      'max_power_kw': PortalField('Công suất lớn nhất (kW)', isNumber: true),
    });
    if (!mounted || form == null) return;
    await perform(
      () => _api.addHostPort(stationId, form),
      (result) => 'Cổng #${result['port_id']} · ${result['status']}',
    );
  }

  Future<void> _change(PortalRow port, String status) => perform(
    () => _api.changeHostPortStatus((port['port_id'] as num).toInt(), status),
    (result) =>
        'Cổng ${port['port_code']} · ${result['status']} · ${optimizationLabel(result)}',
  );

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.host,
    route: '/host/ports',
    eyebrow: 'Cổng chủ trạm',
    title: 'Cổng sạc và bảo trì',
    simulationLabel: null,
    children: [
      ...operationFeedback,
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
          return AppCard(
            child: TextButton(
              onPressed: () => context.go('/host/stations'),
              child: const Text(
                'Trạm không thuộc tài khoản này · Quay về danh sách',
              ),
            ),
          );
        }
        final stationId = (station['station_id'] as num).toInt();
        final ports = portalRows(station['ports']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PortalStationPicker(
              stations: stations,
              stationId: stationId,
              onChanged: (id) => context.go('/host/ports?stationId=$id'),
            ),
            const Gap(12),
            Wrap(
              spacing: 12,
              children: [
                WebBtn(
                  'Thêm cổng',
                  primary: true,
                  onTap: working ? null : () => _addPort(stationId),
                ),
                WebBtn(
                  'Xem lịch trạm',
                  onTap: () =>
                      context.go('/host/schedule?stationId=$stationId'),
                ),
              ],
            ),
            const Gap(12),
            const MutedText(
              'API hiện hỗ trợ chuyển cổng sang bảo trì hoặc ngừng hoạt động.',
            ),
            if (ports.isEmpty) const MutedText('Trạm chưa có cổng.'),
            for (final port in ports)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BoldText(
                        '${port['port_code']} · ${port['connector_type']} · ${port['status']}',
                      ),
                      MutedText(
                        '${port['min_power_kw']}–${port['max_power_kw']} kW',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (port['status'] != 'MAINTENANCE')
                            TextButton(
                              onPressed: working
                                  ? null
                                  : () => _change(port, 'MAINTENANCE'),
                              child: const Text('Đưa vào bảo trì'),
                            ),
                          if (port['status'] != 'OFFLINE')
                            TextButton(
                              onPressed: working
                                  ? null
                                  : () => _change(port, 'OFFLINE'),
                              child: const Text('Ngừng cổng'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    ],
  );
}
