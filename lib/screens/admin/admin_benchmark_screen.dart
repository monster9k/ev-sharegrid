import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/benchmark.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A5 – Bảng KPI đọc từ benchmark thật trên API.
class AdminBenchmarkScreen extends StatefulWidget {
  const AdminBenchmarkScreen({super.key});

  @override
  State<AdminBenchmarkScreen> createState() => _AdminBenchmarkScreenState();
}

class _AdminBenchmarkScreenState extends State<AdminBenchmarkScreen> {
  bool _loading = false;
  String? _error;
  String? _source;
  List<BenchmarkPoint> _points = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _source = null;
      _points = const [];
    });
    try {
      final response = await apiClient.getBenchmark();
      final points = BenchmarkPoint.parse(response);
      if (!mounted) return;
      setState(() {
        _source = response['source']?.toString();
        _points = points;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException
            ? '${error.message} (HTTP ${error.statusCode})'
            : 'Không thể tải benchmark từ máy chủ: $error',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(double? value) => value?.toString() ?? '—';
  String _integer(int? value) => value?.toString() ?? '—';

  String _tariff(String? value) => switch (value) {
    'fixed_2000_vnd_kwh' => 'Cố định 2.000 đ/kWh',
    'evn_tou_1600_2400_4000_vnd_kwh' ||
    'simulated_tou_1600_2400_4000_vnd_kwh' =>
      'TOU giả định 1.600 / 2.400 / 4.000 đ/kWh',
    null => '—',
    _ => value,
  };

  String _status(BenchmarkMetrics metrics) => [
    metrics.status ?? '—',
    if (metrics.fallbackReason case final reason? when reason != 'NONE') reason,
  ].join('\n');

  Widget _actual(BenchmarkPoint point) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      cellText(
        point.actualAlgorithms.isEmpty
            ? '—'
            : point.actualAlgorithms.join(' + '),
      ),
      for (final cluster in point.clusters)
        cellText(
          'Cụm ${cluster.id} · ${cluster.actualAlgorithm ?? '—'} · '
          '${_status(cluster.metrics).replaceAll('\n', ' · ')}',
          size: 11,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.admin,
    route: '/admin/benchmark',
    eyebrow: 'Quản trị · số đo từ máy chủ',
    title: 'Benchmark thuật toán',
    actions: [
      if (_source != null) Pill.neutral('Nguồn: $_source'),
      WebBtn(
        _loading ? 'Đang tải…' : 'Tải lại',
        primary: true,
        icon: Icons.refresh_rounded,
        onTap: _loading ? null : _load,
      ),
    ],
    children: [
      if (_loading) const LinearProgressIndicator(minHeight: 3),
      if (_error != null)
        WebCard(
          children: [
            InfoNote(_error!, warn: true),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử tải lại'),
              ),
            ),
          ],
        ),
      if (!_loading && _error == null && _points.isEmpty)
        const WebCard(children: [InfoNote('Chưa có dữ liệu benchmark thật')]),
      if (_points.isNotEmpty)
        WebCard(
          title: 'Kết quả đo · ${_points.length} lượt',
          trailing: const MutedText('Kịch bản mô phỏng', size: 12),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1530,
                child: SimpleTable(
                  columns: const [
                    'Request',
                    'Biểu giá',
                    'Thuật toán yêu cầu',
                    'Thuật toán thực chạy',
                    'Đúng hạn',
                    'Thiếu kWh',
                    'Chi phí VND',
                    'Đỉnh kW',
                    'Vượt trần',
                    'solve_ms',
                    'Trạng thái / lý do',
                  ],
                  flex: const [8, 13, 10, 20, 7, 8, 10, 6, 5, 9, 10],
                  rows: [
                    for (final point in _points)
                      [
                        cellText(
                          point.llfThroughput
                              ? '${point.milestone}\nbài test thông lượng LLF'
                              : point.milestone,
                        ),
                        cellText(_tariff(point.tariff)),
                        cellText(
                          point.variant == null || point.variant == 'DEFAULT'
                              ? point.requestedAlgorithm
                              : '${point.requestedAlgorithm}\n${point.variant}',
                          bold: true,
                        ),
                        _actual(point),
                        cellText(
                          point.metrics.onTimeRate == null
                              ? '—'
                              : '${(point.metrics.onTimeRate! * 100).toStringAsFixed(2)}%',
                        ),
                        cellText(_number(point.metrics.shortfallKwh)),
                        cellText(_number(point.metrics.costVnd)),
                        cellText(_number(point.metrics.peakKw)),
                        cellText(_integer(point.metrics.capViolations)),
                        cellText(_number(point.metrics.solveMs)),
                        cellText(_status(point.metrics)),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
    ],
  );
}
