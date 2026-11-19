import 'package:ev_sharegrid/data/benchmark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads measured database rows when the backend has no report file', () {
    final rows = BenchmarkPoint.parse({
      'source': 'benchmark_result',
      'count': 1,
      'results': [
        {
          'scenario_id': 'SC-1000',
          'algorithm': 'LLF',
          'repeat_no': 2,
          'metrics_json':
              '{"active_requests":1000,"on_time_rate":0.92,"total_shortfall_kwh":4.5,"solve_ms":2.75,"status":"FEASIBLE"}',
        },
      ],
    });

    expect(rows, hasLength(1));
    expect(rows.single.milestone, '1000');
    expect(rows.single.requestedAlgorithm, 'LLF');
    expect(rows.single.actualAlgorithms, isEmpty);
    expect(rows.single.variant, 'Lượt 2');
    expect(rows.single.metrics.onTimeRate, 0.92);
    expect(rows.single.metrics.shortfallKwh, 4.5);
    expect(rows.single.metrics.solveMs, 2.75);
    expect(rows.single.metrics.status, 'FEASIBLE');
  });

  test('empty benchmark history stays empty', () {
    expect(
      BenchmarkPoint.parse({'source': 'benchmark_result', 'results': []}),
      isEmpty,
    );
  });
}
