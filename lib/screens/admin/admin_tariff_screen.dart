import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

class AdminTariffScreen extends StatefulWidget {
  const AdminTariffScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<AdminTariffScreen> createState() => _AdminTariffScreenState();
}

class _AdminTariffScreenState extends PortalRowsState<AdminTariffScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  int? _selected;

  @override
  Future<List<PortalRow>> loadRows() => _api.getAdminClusters();

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.admin,
    route: '/admin/tariff',
    title: 'Biểu giá điện theo cụm',
    eyebrow: 'Quản trị',
    simulationLabel: null,
    children: [
      const InfoNote(
        'Chỉ đọc. API lưu biểu giá chưa hỗ trợ MON_SAT và SUNDAY.',
      ),
      dataPane((rows) {
        if (rows.isEmpty) {
          return const AppCard(child: MutedText('Chưa có cụm điều phối.'));
        }
        final cluster =
            rows.where((row) => row['cluster_id'] == _selected).firstOrNull ??
            rows.first;
        final tariffs = portalRows(cluster['tariffs']);
        return Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: (cluster['cluster_id'] as num).toInt(),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cụm'),
              items: [
                for (final row in rows)
                  DropdownMenuItem(
                    value: (row['cluster_id'] as num).toInt(),
                    child: Text('${row['name']}'),
                  ),
              ],
              onChanged: (id) => setState(() => _selected = id),
            ),
            const Gap(12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BoldText('Khung giá đang có hiệu lực'),
                  if (tariffs.isEmpty)
                    const MutedText('Chưa có biểu giá cho cụm này.'),
                  for (final row in tariffs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: BoldText(
                        '${row['day_type']} · ${row['start_time']}–${row['end_time']} · ${row['band']}',
                      ),
                      subtitle: MutedText(row['source_ref']?.toString() ?? '—'),
                      trailing: BoldText(
                        '${vnDec((row['price_vnd_kwh'] as num), 0)} đ/kWh',
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    ],
  );
}
