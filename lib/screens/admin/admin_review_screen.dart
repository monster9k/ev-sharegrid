import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends PortalRowsState<AdminReviewScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  String _status = 'PENDING';

  @override
  Future<List<PortalRow>> loadRows() => _api.getAdminStations(_status);

  Future<void> _verify(PortalRow station, bool value) => perform(
    () => _api.verifyStation((station['station_id'] as num).toInt(), value),
    (result) =>
        'Trạm #${result['station_id']} · ${result['status']} · ${optimizationLabel(result)}',
  );

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.admin,
    route: '/admin/review',
    title: 'Duyệt trạm',
    eyebrow: 'Quản trị',
    simulationLabel: null,
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final (status, label) in const [
            ('PENDING', 'Chờ duyệt'),
            ('ACTIVE', 'Đang hoạt động'),
          ])
            FilterChip(
              label: Text(label),
              selected: _status == status,
              onSelected: working
                  ? null
                  : (_) {
                      if (_status == status) return;
                      _status = status;
                      refresh();
                    },
            ),
        ],
      ),
      ...operationFeedback,
      dataPane(
        (rows) => Column(
          children: [
            if (rows.isEmpty)
              const AppCard(child: MutedText('Chưa có trạm ở trạng thái này.')),
            for (final station in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BoldText(
                        '#${station['station_id']} · ${station['name']}',
                      ),
                      MutedText(
                        '${station['address']} · Cụm #${station['cluster_id']}',
                      ),
                      if (station['lat'] == null || station['lng'] == null)
                        const MutedText('Cần đủ vĩ độ và kinh độ để duyệt.')
                      else
                        MutedText(
                          'Tọa độ tham khảo · ${station['lat']}, ${station['lng']}',
                        ),
                      if (_status == 'PENDING' &&
                          station['lat'] != null &&
                          station['lng'] != null)
                        FilledButton(
                          onPressed: working
                              ? null
                              : () => _verify(station, true),
                          child: const Text('Duyệt & kích hoạt'),
                        ),
                      if (_status == 'ACTIVE' && station['verified'] == true)
                        TextButton(
                          onPressed: working
                              ? null
                              : () => _verify(station, false),
                          child: const Text('Gỡ duyệt · chuyển về chờ duyệt'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
