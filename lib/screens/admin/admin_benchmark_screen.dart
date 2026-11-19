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
    });
    try {
      final response = await apiClient.getBenchmark();
      if (!mounted) return;
      setState(() {
        _source = response['source']?.toString();
        _points = BenchmarkPoint.parse(response);
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
          title: 'Kết quả thật · ${_points.length} dòng',
          trailing: const MutedText(
            'Giữ nguyên độ chính xác API trả về',
            size: 12,
          ),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1250,
                child: SimpleTable(
                  columns: const [
                    'Request',
                    'Thuật toán',
                    'Đúng hạn',
                    'Thiếu kWh',
                    'Chi phí VND',
                    'Đỉnh kW',
                    'Vượt trần',
                    'solve_ms',
                    'Status',
                    'Lượt',
                  ],
                  flex: const [8, 11, 8, 9, 12, 8, 8, 8, 8, 6],
                  rows: [
                    for (final point in _points)
                      [
                        cellText(point.milestone),
                        cellText(point.algorithm, bold: true),
                        cellText(
                          point.onTimeRate == null
                              ? '—'
                              : '${(point.onTimeRate! * 100).toString()}%',
                        ),
                        cellText(_number(point.shortfallKwh)),
                        cellText(_number(point.costVnd)),
                        cellText(_number(point.peakKw)),
                        cellText(_integer(point.capViolations)),
                        cellText(_number(point.solveMs)),
                        cellText(point.status),
                        cellText(_integer(point.repeat)),
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
