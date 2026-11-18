import 'package:ev_sharegrid/data/benchmark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses real benchmark rows by request milestone and algorithm', () {
    final rows = BenchmarkPoint.parse({
      'source': 'benchmark_real.json',
      'data': {
        'seed': 42,
        'scenarios': [
          {
            'active_requests': 100,
            'algorithms': {
              'MILP_MPC': {
                'status': 'OPTIMAL',
                'solve_ms': 10.25,
                'kpi': {
                  'on_time_rate': 0.151,
                  'total_shortfall_kwh': 12.375,
                  'total_cost_vnd': 2812345.5,
                  'peak_power_kw': 375.75,
                  'cap_violations': 0,
                },
              },
            },
          },
        ],
      },
    });

    expect(rows, hasLength(1));
    expect(rows.single.milestone, '100');
    expect(rows.single.algorithm, 'MILP_MPC');
    expect(rows.single.onTimeRate, 0.151);
    expect(rows.single.shortfallKwh, 12.375);
    expect(rows.single.costVnd, 2812345.5);
    expect(rows.single.peakKw, 375.75);
    expect(rows.single.capViolations, 0);
    expect(rows.single.solveMs, 10.25);
    expect(rows.single.status, 'OPTIMAL');
  });

  test('parses benchmark_result database rows and JSON metrics', () {
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
    expect(rows.single.algorithm, 'LLF');
    expect(rows.single.repeat, 2);
    expect(rows.single.onTimeRate, 0.92);
    expect(rows.single.shortfallKwh, 4.5);
    expect(rows.single.solveMs, 2.75);
    expect(rows.single.status, 'FEASIBLE');
  });

  test('empty benchmark data stays empty', () {
    expect(
      BenchmarkPoint.parse({'source': 'benchmark_result', 'results': []}),
      isEmpty,
    );
  });

  test('parses benchmark data grouped by request count and algorithm', () {
    final rows = BenchmarkPoint.parse({
      'source': 'benchmark_real.json',
      'data': {
        '100': {
          'LLF': {
            'status': 'FEASIBLE',
            'solve_ms': 3.125,
            'on_time_rate': 0.151,
            'total_shortfall_kwh': 12.375,
            'total_cost_vnd': 2800.5,
            'peak_power_kw': 14.25,
            'cap_violations': 0,
          },
        },
      },
    });

    expect(rows, hasLength(1));
    expect(rows.single.milestone, '100');
    expect(rows.single.algorithm, 'LLF');
    expect(rows.single.solveMs, 3.125);
    expect(rows.single.onTimeRate, 0.151);
    expect(rows.single.shortfallKwh, 12.375);
    expect(rows.single.costVnd, 2800.5);
    expect(rows.single.peakKw, 14.25);
    expect(rows.single.capViolations, 0);
  });
}
