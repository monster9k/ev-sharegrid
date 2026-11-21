import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';
import '../admin/admin_common.dart';

class HostStationsScreen extends StatefulWidget {
  const HostStationsScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<HostStationsScreen> createState() => _HostStationsScreenState();
}

class _HostStationsScreenState extends PortalRowsState<HostStationsScreen> {
  ApiClient get _api => widget.client ?? apiClient;

  @override
  Future<List<PortalRow>> loadRows() => _api.getHostStations();

  Future<void> _create() async {
    final form = await askPortalFields(context, 'Đăng ký trạm mới', const {
      'cluster_id': PortalField('Mã cụm', isNumber: true),
      'name': PortalField('Tên trạm'),
      'address': PortalField('Địa chỉ'),
      'province': PortalField('Tỉnh/thành', initial: 'Đà Nẵng'),
      'station_power_kw': PortalField('Công suất trạm (kW)', isNumber: true),
      'lat': PortalField(
        'Vĩ độ · cần khi duyệt trạm',
        isNumber: true,
        optional: true,
      ),
      'lng': PortalField(
        'Kinh độ · cần khi duyệt trạm',
        isNumber: true,
        optional: true,
      ),
    });
    if (!mounted || form == null) return;
    await perform(
      () => _api.createHostStation({
        for (final entry in form.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      }),
      (result) => 'Trạm #${result['station_id']} · ${result['status']}',
    );
  }

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.host,
    route: '/host/stations',
    eyebrow: 'Cổng chủ trạm',
    title: 'Trạm của tôi',
    simulationLabel: null,
    actions: [
      WebBtn(
        'Đăng ký trạm mới',
        primary: true,
        onTap: working ? null : _create,
      ),
    ],
    children: [
      ...operationFeedback,
      dataPane(
        (stations) => Column(
          children: [
            if (stations.isEmpty)
              const AppCard(child: MutedText('Chưa có trạm đăng ký.')),
            for (final station in stations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: BoldText(
                      '#${station['station_id']} · ${station['name']}',
                    ),
                    subtitle: MutedText(
                      '${station['address']} · ${station['status']} · ${station['station_power_kw']} kW',
                    ),
                    trailing: TextButton(
                      onPressed: () => context.go(
                        '/host/ports?stationId=${station['station_id']}',
                      ),
                      child: const Text('Xem cổng'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
