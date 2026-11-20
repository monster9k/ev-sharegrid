import 'dart:convert';
import 'dart:io';

import 'package:ev_sharegrid/data/benchmark.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> readReport() =>
    jsonDecode(File('ai_engine/benchmark_real.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'reads every measured milestone, tariff and algorithm from the repository',
    () {
      final report = readReport();
      final points = BenchmarkPoint.parse({
        'source': 'benchmark_real.json',
        'data': report,
      });

      expect(points.map((point) => point.milestone).toSet(), {
        '100',
        '500',
        '1000',
        '10000',
      });
      final tariffMetadata = report['tariffs'] as Map<String, dynamic>;
      expect(tariffMetadata, hasLength(2));
      expect(tariffMetadata.keys, contains('fixed_2000_vnd_kwh'));
      var offset = 0;
      for (final milestone in report['milestones'] as List) {
        final tariffs = milestone['tariffs'] as List;
        expect(
          tariffs.map((row) => row['tariff']),
          unorderedEquals(tariffMetadata.keys),
        );
        for (final tariff in tariffs) {
          final algorithms = tariff['algorithms'] as List;
          expect(
            algorithms.map((row) => row['requested_algorithm']),
            containsAll(['LLF', 'EDF', 'FCFS', 'EQUAL_SHARE', 'ASAP']),
          );
          for (final raw in algorithms) {
            final point = points[offset++];
            final kpi = raw['kpi'];
            expect(point.milestone, milestone['request_count'].toString());
            expect(point.tariff, tariff['tariff']);
            expect(point.requestedAlgorithm, raw['requested_algorithm']);
            expect(point.actualAlgorithms, raw['actual_algorithms']);
            expect(point.variant, raw['variant']);
            expect(point.metrics.status, raw['status']);
            expect(point.metrics.fallbackReason, raw['fallback_reason']);
            expect(point.metrics.solveMs, raw['solve_ms']);
            expect(point.metrics.onTimeRate, kpi?['on_time_rate']);
            expect(point.metrics.shortfallKwh, kpi?['total_shortfall_kwh']);
            expect(point.metrics.costVnd, kpi?['total_cost_vnd']);
            expect(point.metrics.peakKw, kpi?['peak_power_kw']);
            expect(point.metrics.capViolations, kpi?['cap_violations']);
            final clusterResults = raw['cluster_results'] as Map;
            expect(point.clusters.map((cluster) => cluster.id).toSet(), {
              '1',
              '2',
            });
            for (final cluster in point.clusters) {
              final rawCluster = clusterResults[cluster.id];
              expect(cluster.actualAlgorithm, rawCluster['actual_algorithm']);
              expect(cluster.metrics.status, rawCluster['status']);
              expect(
                cluster.metrics.fallbackReason,
                rawCluster['fallback_reason'],
              );
            }
            expect(point.llfThroughput, point.milestone == '10000');
          }
        }
      }
      expect(points, hasLength(offset));
      final mixed = points.firstWhere(
        (point) =>
            point.milestone == '500' &&
            point.tariff == 'fixed_2000_vnd_kwh' &&
            point.requestedAlgorithm == 'MILP_MPC' &&
            (point.variant == null || point.variant == 'DEFAULT'),
      );
      expect(mixed.actualAlgorithms, ['LLF', 'MILP_MPC']);
      expect(
        mixed.clusters
            .singleWhere((cluster) => cluster.id == '1')
            .actualAlgorithm,
        'LLF',
      );
    },
  );

  test('accepts missing metrics and optional fields in the real report', () {
    final report = readReport();
    final first =
        report['milestones'][0]['tariffs'][0]['algorithms'][0]
            as Map<String, dynamic>;
    first
      ..remove('fallback_reason')
      ..remove('actual_algorithms')
      ..remove('kpi')
      ..remove('solve_ms')
      ..['future_metadata'] = {'another_field': true};
    final point = BenchmarkPoint.parse(report).first;
    expect(point.requestedAlgorithm, first['requested_algorithm']);
    expect(point.actualAlgorithms, isEmpty);
    expect(point.metrics.fallbackReason, isNull);
    expect(point.metrics.onTimeRate, isNull);
    expect(point.metrics.solveMs, isNull);
  });

  test('rejects malformed report structure instead of guessing rows', () {
    final report = readReport();
    report['milestones'][0]['tariffs'][0]['algorithms'] = {'LLF': {}};
    expect(
      () => BenchmarkPoint.parse(report),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('algorithms'),
        ),
      ),
    );
  });
}
