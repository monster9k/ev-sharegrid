import 'dart:convert';

class BenchmarkMetrics {
  BenchmarkMetrics(Map<String, dynamic> row)
    : status = _text(row['status']),
      fallbackReason = _text(row['fallback_reason']),
      solveMs = _number(row['solve_ms']),
      _kpi = row['kpi'] == null ? const {} : _object(row['kpi'], 'kpi');

  final String? status;
  final String? fallbackReason;
  final double? solveMs;
  final Map<String, dynamic> _kpi;

  double? get onTimeRate => _number(_kpi['on_time_rate']);
  double? get shortfallKwh => _number(_kpi['total_shortfall_kwh']);
  double? get costVnd => _number(_kpi['total_cost_vnd']);
  double? get peakKw => _number(_kpi['peak_power_kw']);
  int? get capViolations =>
      _kpi['cap_violations'] is int ? _kpi['cap_violations'] as int : null;
}

class BenchmarkCluster {
  BenchmarkCluster(this.id, Map<String, dynamic> row)
    : actualAlgorithm = _text(row['actual_algorithm']),
      metrics = BenchmarkMetrics(row);

  final String id;
  final String? actualAlgorithm;
  final BenchmarkMetrics metrics;
}

class BenchmarkPoint {
  const BenchmarkPoint._({
    required this.milestone,
    required this.requestedAlgorithm,
    required this.actualAlgorithms,
    required this.metrics,
    this.tariff,
    this.variant,
    this.llfThroughput = false,
    this.clusters = const [],
  });

  final String milestone;
  final String? tariff;
  final String requestedAlgorithm;
  final List<String> actualAlgorithms;
  final String? variant;
  final bool llfThroughput;
  final BenchmarkMetrics metrics;
  final List<BenchmarkCluster> clusters;

  /// The admin API wraps the file in data; a raw file can also be read directly.
  static List<BenchmarkPoint> parse(Map<String, dynamic> response) {
    if (response['source'] == 'benchmark_result') {
      return _parseHistory(response);
    }
    final report = response.containsKey('data')
        ? _object(response['data'], 'data')
        : response;

    final points = <BenchmarkPoint>[];
    for (final milestone in _objects(report['milestones'], 'milestones')) {
      final count = milestone['request_count'];
      if (count is! int || count <= 0) {
        throw const FormatException('request_count phải là số nguyên dương.');
      }
      final llfThroughput =
          milestone['data_scenario_type'] == 'LLF_THROUGHPUT_ONLY' ||
          milestone['scenario_type'] == 'LLF_THROUGHPUT_ONLY' ||
          count == 10000;
      for (final tariff in _objects(milestone['tariffs'], 'tariffs')) {
        final tariffName = _requiredText(tariff['tariff'], 'tariff');
        for (final row in _objects(tariff['algorithms'], 'algorithms')) {
          final clusterRows = row['cluster_results'] == null
              ? const <String, dynamic>{}
              : _object(row['cluster_results'], 'cluster_results');
          points.add(
            BenchmarkPoint._(
              milestone: count.toString(),
              tariff: tariffName,
              requestedAlgorithm: _requiredText(
                row['requested_algorithm'],
                'requested_algorithm',
              ),
              actualAlgorithms: _algorithmList(row['actual_algorithms']),
              variant: _text(row['variant']),
              llfThroughput: llfThroughput,
              metrics: BenchmarkMetrics(row),
              clusters: [
                for (final entry in clusterRows.entries)
                  BenchmarkCluster(
                    entry.key,
                    _object(entry.value, 'cluster_results.${entry.key}'),
                  ),
              ],
            ),
          );
        }
      }
    }
    return points;
  }

  /// Older deployments can return measured database rows if no file exists.
  static List<BenchmarkPoint> _parseHistory(Map<String, dynamic> response) {
    return [
      for (final row in _objects(response['results'], 'results'))
        _historyPoint(row),
    ];
  }

  static BenchmarkPoint _historyPoint(Map<String, dynamic> row) {
    final rawMetrics = row['metrics_json'];
    final data = _object(
      rawMetrics is String ? jsonDecode(rawMetrics) : rawMetrics,
      'metrics_json',
    );
    return BenchmarkPoint._(
      milestone:
          (data['active_requests'] ??
                  data['request_count'] ??
                  row['scenario_id'])
              ?.toString() ??
          '—',
      tariff: _text(data['tariff']),
      requestedAlgorithm: _requiredText(row['algorithm'], 'algorithm'),
      actualAlgorithms: [?_text(data['algorithm'])],
      variant: row['repeat_no'] is int ? "Lượt ${row['repeat_no']}" : null,
      metrics: BenchmarkMetrics({'kpi': data, ...data}),
    );
  }
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field phải là một đối tượng JSON.');
}

Iterable<Map<String, dynamic>> _objects(Object? value, String field) {
  if (value is! List) {
    throw FormatException('$field phải là một danh sách JSON.');
  }
  return value.map((item) => _object(item, field));
}

List<String> _algorithmList(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('actual_algorithms phải là một danh sách.');
  }
  return [for (final name in value) _requiredText(name, 'actual_algorithms')];
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _requiredText(Object? value, String field) =>
    _text(value) ?? (throw FormatException('Thiếu hoặc sai định dạng $field.'));

double? _number(Object? value) =>
    value is num && value.isFinite ? value.toDouble() : null;
