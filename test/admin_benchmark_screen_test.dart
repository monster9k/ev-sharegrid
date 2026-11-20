import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ev_sharegrid/data/api.dart';
import 'package:ev_sharegrid/screens/admin/admin_benchmark_screen.dart';
import 'package:ev_sharegrid/theme.dart';
import 'package:ev_sharegrid/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? data, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(data)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> _open(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) respond,
) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final httpClient = MockClient((request) {
    expect(request.method, 'GET');
    expect(request.url.path, '/api/v1/admin/benchmark');
    return respond(request);
  });
  addTearDown(httpClient.close);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminBenchmarkScreen(
        client: ApiClient(client: httpClient, baseUrl: 'http://localhost:8000'),
      ),
    ),
  );
}

void main() {
  late String reportJson;
  setUpAll(() {
    AppFonts.enabled = false;
    reportJson = File('ai_engine/benchmark_real.json').readAsStringSync();
  });

  testWidgets('renders report, cluster IDs and optional fields', (
    tester,
  ) async {
    final report = jsonDecode(reportJson) as Map<String, dynamic>;
    final milestones = report['milestones'] as List;
    final first =
        milestones.first['tariffs'][0]['algorithms'][0] as Map<String, dynamic>;
    first.remove('kpi');
    first.remove('fallback_reason');
    final cluster =
        milestones[1]['tariffs'][0]['algorithms'][0]['cluster_results']['1']
            as Map<String, dynamic>;
    // The older report lacks this field. Exercise the same UI with both versions.
    cluster.putIfAbsent('fallback_reason', () => 'THRESHOLD_EXCEEDED');

    await _open(
      tester,
      (_) async => _json({'source': 'benchmark_real.json', 'data': report}),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SimpleTable), findsOneWidget);
    expect(find.text('Nguồn: benchmark_real.json'), findsOneWidget);
    expect(find.text('Chưa có benchmark thật'), findsNothing);
    expect(find.text('Cố định 2.000 đ/kWh'), findsWidgets);
    expect(
      find.text('TOU EVN hạ áp 1.620 / 2.700 / 4.212 đ/kWh'),
      findsWidgets,
    );
    expect(find.text('MILP_MPC'), findsWidgets);
    expect(find.text('LLF + MILP_MPC'), findsWidgets);
    expect(
      find.text('Cụm 1 · LLF · FALLBACK · THRESHOLD_EXCEEDED'),
      findsWidgets,
    );
    expect(find.text('10000\nbài test thông lượng LLF'), findsWidgets);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('labels historical TOU as simulated', (tester) async {
    await _open(
      tester,
      (_) async => _json({
        'source': 'benchmark_result',
        'results': [
          {
            'scenario_id': 1,
            'algorithm': 'LLF',
            'metrics_json': {'tariff': 'evn_tou_1600_2400_4000_vnd_kwh'},
          },
        ],
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('TOU giả định 1.600 / 2.400 / 4.000 đ/kWh'),
      findsOneWidget,
    );
  });

  testWidgets('hides prior results if reloading returns a malformed report', (
    tester,
  ) async {
    var calls = 0;
    await _open(tester, (_) async {
      if (++calls == 1) return _json(jsonDecode(reportJson));
      return _json({
        'source': 'benchmark_real.json',
        'data': {'milestones': {}},
      });
    });
    await tester.pumpAndSettle();
    expect(find.byType(SimpleTable), findsOneWidget);

    await tester.tap(find.text('Tải lại'));
    await tester.pumpAndSettle();
    expect(find.byType(SimpleTable), findsNothing);
    expect(
      find.textContaining('Báo cáo benchmark bị thiếu hoặc sai định dạng'),
      findsOneWidget,
    );
    expect(
      find.textContaining('milestones phải là một danh sách JSON'),
      findsOneWidget,
    );
  });

  testWidgets('shows connection errors and can retry the benchmark API', (
    tester,
  ) async {
    var calls = 0;
    await _open(tester, (_) async {
      if (++calls == 1) throw http.ClientException('Connection refused');
      return _json({'source': 'benchmark_result', 'count': 0, 'results': []});
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Không kết nối được máy chủ benchmark'),
      findsOneWidget,
    );
    expect(find.byType(SimpleTable), findsNothing);

    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(
      find.textContaining('Chưa có dữ liệu benchmark thật'),
      findsOneWidget,
    );
    expect(find.byType(SimpleTable), findsNothing);
  });

  testWidgets('reports a missing benchmark data source', (tester) async {
    await _open(tester, (_) async => _json({'detail': 'not found'}, 404));
    await tester.pumpAndSettle();
    expect(
      find.text('Máy chủ không cung cấp dữ liệu benchmark (HTTP 404).'),
      findsOneWidget,
    );
    expect(find.byType(SimpleTable), findsNothing);
  });

  testWidgets('ends the loading state when the benchmark API times out', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    await _open(tester, (_) => response.future);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('không phản hồi trong 10 giây'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(SimpleTable), findsNothing);
    response.complete(_json({}));
    await tester.pump();
  });
}
