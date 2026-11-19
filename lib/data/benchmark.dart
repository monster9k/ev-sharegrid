import 'dart:convert';

class BenchmarkPoint {
  const BenchmarkPoint({
    required this.milestone,
    required this.algorithm,
    required this.status,
    this.repeat,
    this.onTimeRate,
    this.shortfallKwh,
    this.costVnd,
    this.peakKw,
    this.capViolations,
    this.solveMs,
  });

  final String milestone;
  final String algorithm;
  final String status;
  final int? repeat;
  final double? onTimeRate;
  final double? shortfallKwh;
  final double? costVnd;
  final double? peakKw;
  final int? capViolations;
  final double? solveMs;

  static List<BenchmarkPoint> parse(Map<String, dynamic> response) {
    final points = <BenchmarkPoint>[];
    _visit(response['data'] ?? response, points);
    points.sort((a, b) {
      final aSize = int.tryParse(a.milestone);
      final bSize = int.tryParse(b.milestone);
      if (aSize != null && bSize != null && aSize != bSize) {
        return aSize.compareTo(bSize);
      }
      final milestoneOrder = a.milestone.compareTo(b.milestone);
      return milestoneOrder != 0
          ? milestoneOrder
          : a.algorithm.compareTo(b.algorithm);
    });
    return points;
  }

  static void _visit(
    Object? value,
    List<BenchmarkPoint> output, {
    String? inheritedMilestone,
    String? inheritedScenario,
  }) {
    if (value is List) {
      for (final item in value) {
        _visit(
          item,
          output,
          inheritedMilestone: inheritedMilestone,
          inheritedScenario: inheritedScenario,
        );
      }
      return;
    }
    if (value is! Map) return;

    final map = Map<String, dynamic>.from(value);
    final milestone = _milestone(map) ?? inheritedMilestone;
    final scenario = _string(map['scenario_id']) ?? inheritedScenario;

    final algorithms = map['algorithms'];
    if (algorithms is Map) {
      for (final entry in algorithms.entries) {
        if (entry.value is Map) {
          final algorithmRecord = <String, dynamic>{
            ...Map<String, dynamic>.from(entry.value as Map),
            'algorithm': entry.key.toString(),
          };
          _add(
            algorithmRecord,
            output,
            milestone: milestone,
            scenario: scenario,
          );
        }
      }
      return;
    }

    final algorithm = _string(map['algorithm']);
    if (algorithm != null) {
      final result = map['result'];
      final record = result is Map
          ? <String, dynamic>{
              ...map,
              ...Map<String, dynamic>.from(result),
              'algorithm': algorithm,
            }
          : map;
      _add(record, output, milestone: milestone, scenario: scenario);
      return;
    }

    for (final key in const [
      'benchmarks',
      'records',
      'results',
      'runs',
      'summary',
      'scenarios',
      'milestones',
      'data',
    ]) {
      if (map[key] != null) {
        _visit(
          map[key],
          output,
          inheritedMilestone: milestone,
          inheritedScenario: scenario,
        );
        return;
      }
    }

    for (final entry in map.entries) {
      if (entry.value is! Map && entry.value is! List) continue;
      final key = entry.key.toString();
      if (_isAlgorithm(key) && entry.value is Map) {
        _add(
          {...Map<String, dynamic>.from(entry.value as Map), 'algorithm': key},
          output,
          milestone: milestone ?? inheritedMilestone,
          scenario: scenario ?? inheritedScenario,
        );
      } else {
        _visit(
          entry.value,
          output,
          inheritedMilestone: int.tryParse(key) == null ? milestone : key,
          inheritedScenario: scenario,
        );
      }
    }
  }

  static bool _isAlgorithm(String value) => const {
    'MILP_MPC',
    'LP_MPC',
    'LLF',
    'EDF',
    'FCFS',
    'EQUAL_SHARE',
    'ASAP',
  }.contains(value);

  static void _add(
    Map<String, dynamic> row,
    List<BenchmarkPoint> output, {
    String? milestone,
    String? scenario,
  }) {
    final result = row['result'] is Map
        ? Map<String, dynamic>.from(row['result'] as Map)
        : const <String, dynamic>{};
    final metrics = _map(row['metrics_json']) ?? _map(row['metrics']) ?? {};
    final kpi =
        _map(row['kpi']) ??
        _map(result['kpi']) ??
        _map(metrics['kpi']) ??
        metrics;
    final merged = <String, dynamic>{...metrics, ...result, ...row};
    final algorithm = _string(row['algorithm']) ?? _string(result['algorithm']);
    if (algorithm == null) return;

    final count =
        _milestone(row) ??
        _milestone(metrics) ??
        _milestone(result) ??
        milestone;
    output.add(
      BenchmarkPoint(
        milestone: count ?? scenario ?? '—',
        algorithm: algorithm,
        status: _string(merged['status']) ?? '—',
        repeat: _int(merged['repeat_no']) ?? _int(merged['repeat_index']),
        onTimeRate:
            _number(kpi['on_time_rate']) ?? _number(merged['on_time_rate']),
        shortfallKwh:
            _number(kpi['total_shortfall_kwh']) ??
            _number(merged['total_shortfall_kwh']) ??
            _number(merged['shortfall_kwh']),
        costVnd:
            _number(kpi['total_cost_vnd']) ??
            _number(merged['total_cost_vnd']) ??
            _number(merged['cost_vnd']),
        peakKw:
            _number(kpi['peak_power_kw']) ??
            _number(merged['peak_power_kw']) ??
            _number(merged['peak_kw']),
        capViolations:
            _int(kpi['cap_violations']) ?? _int(merged['cap_violations']),
        solveMs:
            _number(merged['solve_ms']) ?? _number(merged['solve_ms_mean']),
      ),
    );
  }

  static String? _milestone(Map map) {
    for (final key in const [
      'active_requests',
      'active_request_count',
      'request_count',
      'n_requests',
      'requests_count',
      'size',
      'milestone',
    ]) {
      final value = map[key];
      if (value is num || value is String) return value.toString();
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;

  static int? _int(Object? value) => value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value)
      : null;
}
