import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/portal_data.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

class AdminForecastScreen extends StatefulWidget {
  const AdminForecastScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<AdminForecastScreen> createState() => _AdminForecastScreenState();
}

class _AdminForecastScreenState extends PortalRowsState<AdminForecastScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  int? _cluster;
  String _model = 'BEST';
  bool _running = false;
  PortalRow? _forecast;
  Object? _error;
  int? _ms;

  @override
  Future<List<PortalRow>> loadRows() => _api.getAdminClusters();

  Future<void> _run(int id) async {
    if (_running) return;
    final timer = Stopwatch()..start();
    setState(() {
      _running = true;
      _forecast = null;
      _error = null;
    });
    try {
      final result = await _api.runForecast(id, _model);
      if (!mounted) return;
      setState(() {
        _forecast = result;
        _ms = timer.elapsedMilliseconds;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _time(Object? value) {
    final time = DateTime.tryParse(value?.toString() ?? '');
    return time == null
        ? '—'
        : '${formatChargingDate(vietnamWallTime(time))} · ${formatVietnamTime(time)}';
  }

  @override
  Widget build(BuildContext context) {
    final forecast = _forecast;
    return WebShell(
      portal: Portal.admin,
      route: '/admin/forecast',
      title: 'Dự báo nhu cầu sạc',
      eyebrow: 'Quản trị',
      simulationLabel: null,
      children: [
        const MutedText('Dự báo 24 giờ theo lịch sử check-in của cụm.'),
        dataPane((rows) {
          if (rows.isEmpty) {
            return const AppCard(child: MutedText('Chưa có cụm điều phối.'));
          }
          final id = _cluster ?? (rows.first['cluster_id'] as num).toInt();
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: id,
                  decoration: const InputDecoration(labelText: 'Cụm'),
                  isExpanded: true,
                  items: [
                    for (final row in rows)
                      DropdownMenuItem(
                        value: (row['cluster_id'] as num).toInt(),
                        child: Text('${row['name']}'),
                      ),
                  ],
                  onChanged: _running
                      ? null
                      : (value) => setState(() => _cluster = value),
                ),
                const Gap(10),
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  decoration: const InputDecoration(
                    labelText: 'Mô hình yêu cầu',
                  ),
                  items: [
                    for (final model in const [
                      'BEST',
                      'HOURLY_MEAN',
                      'RANDOM_FOREST',
                      'XGBOOST',
                    ])
                      DropdownMenuItem(value: model, child: Text(model)),
                  ],
                  onChanged: _running
                      ? null
                      : (value) => setState(() => _model = value!),
                ),
                const Gap(12),
                WebBtn(
                  _running ? 'Đang chạy…' : 'Chạy dự báo AI',
                  primary: true,
                  onTap: _running ? null : () => _run(id),
                ),
              ],
            ),
          );
        }),
        if (_running) const LinearProgressIndicator(),
        if (_error != null) ApiErrorCard(error: _error!),
        if (forecast != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BoldText(
                  'Cụm #${forecast['cluster_id']} · Mô hình thực tế ${forecast['model']} · $_ms ms',
                ),
                for (final warning
                    in (forecast['warnings'] as List? ?? const []))
                  InfoNote(warning.toString(), warn: true),
                for (final row in portalRows(forecast['predictions']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: BoldText(_time(row['hour_start'])),
                    trailing: MutedText('${row['pred_arrivals']} lượt'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
