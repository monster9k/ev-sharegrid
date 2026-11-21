import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';

class AdminClustersScreen extends StatefulWidget {
  const AdminClustersScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<AdminClustersScreen> createState() => _AdminClustersScreenState();
}

class _AdminClustersScreenState extends PortalRowsState<AdminClustersScreen> {
  ApiClient get _api => widget.client ?? apiClient;

  @override
  Future<List<PortalRow>> loadRows() => _api.getAdminClusters();

  Future<void> _edit(PortalRow cluster) async {
    final id = (cluster['cluster_id'] as num).toInt();
    final form = await askPortalFields(context, 'Công suất lưới cụm #$id', {
      'grid_limit_kw': PortalField(
        'Giới hạn công suất (kW)',
        initial: cluster['grid_limit_kw'].toString(),
        isNumber: true,
      ),
    });
    if (!mounted || form == null) return;
    await perform(
      () => _api.updateClusterLimit(id, double.parse(form['grid_limit_kw']!)),
      (result) =>
          'Cụm #$id · ${result['grid_limit_kw']} kW · ${optimizationLabel(result)}',
    );
  }

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.admin,
    route: '/admin/clusters',
    title: 'Cụm điều phối',
    eyebrow: 'Quản trị',
    simulationLabel: null,
    children: [
      ...operationFeedback,
      dataPane(
        (rows) => Column(
          children: [
            if (rows.isEmpty)
              const AppCard(child: MutedText('Chưa có cụm điều phối.')),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: BoldText('#${row['cluster_id']} · ${row['name']}'),
                    subtitle: MutedText(
                      '${row['status']} · Giới hạn lưới ${row['grid_limit_kw']} kW',
                    ),
                    trailing: row['status'] == 'ACTIVE'
                        ? TextButton(
                            onPressed: working ? null : () => _edit(row),
                            child: const Text('Chỉnh công suất'),
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
