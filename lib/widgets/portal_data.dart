import 'package:flutter/material.dart';

import 'api_content.dart';
import 'common.dart';

typedef PortalRow = Map<String, dynamic>;

List<PortalRow> portalRows(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

abstract class PortalRowsState<T extends StatefulWidget> extends State<T> {
  late Future<List<PortalRow>> _rows = loadRows();
  bool working = false;
  Object? _operationError;
  String? _result;

  Future<List<PortalRow>> loadRows();

  void refresh() => setState(() => _rows = loadRows());

  List<Widget> get operationFeedback => [
    if (working) const LinearProgressIndicator(),
    if (_operationError != null) ApiErrorCard(error: _operationError!),
    if (_result != null) AppCard(child: BoldText(_result!)),
  ];

  Future<void> perform(
    Future<PortalRow> Function() action,
    String Function(PortalRow) describe,
  ) async {
    if (working) return;
    final timer = Stopwatch()..start();
    setState(() {
      working = true;
      _result = null;
      _operationError = null;
    });
    try {
      final result = await action();
      if (mounted) {
        setState(
          () =>
              _result = '${describe(result)} · ${timer.elapsedMilliseconds} ms',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _operationError = error);
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          _rows = loadRows();
        });
      }
    }
  }

  Widget dataPane(Widget Function(List<PortalRow>) builder) =>
      FutureBuilder<List<PortalRow>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ApiErrorCard(error: snapshot.error!, onRetry: refresh);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          return builder(snapshot.data ?? const []);
        },
      );
}

String optimizationLabel(PortalRow result) =>
    'Tái tối ưu · ${result['optimization_status'] ?? 'Máy chủ chưa trả trạng thái'}';

class PortalField {
  const PortalField(
    this.label, {
    this.initial = '',
    this.choices = const [],
    this.isNumber = false,
    this.optional = false,
  });

  final String label;
  final String initial;
  final List<String> choices;
  final bool isNumber;
  final bool optional;
}

Future<Map<String, String>?> askPortalFields(
  BuildContext context,
  String title,
  Map<String, PortalField> fields,
) => showDialog<Map<String, String>>(
  context: context,
  builder: (context) {
    final form = GlobalKey<FormState>();
    final values = <String, String>{};
    return AlertDialog(
      title: Text(title),
      scrollable: true,
      content: SizedBox(
        width: 380,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: entry.value.choices.isEmpty
                      ? TextFormField(
                          initialValue: entry.value.initial,
                          decoration: InputDecoration(
                            labelText: entry.value.label,
                          ),
                          keyboardType: entry.value.isNumber
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                )
                              : null,
                          validator: (raw) {
                            final value = raw?.trim() ?? '';
                            if (value.isEmpty) {
                              return entry.value.optional
                                  ? null
                                  : 'Vui lòng nhập giá trị.';
                            }
                            if (entry.value.isNumber &&
                                double.tryParse(value)?.isFinite != true) {
                              return 'Vui lòng nhập số hợp lệ.';
                            }
                            return null;
                          },
                          onSaved: (value) => values[entry.key] = value!.trim(),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: entry.value.choices.first,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: entry.value.label,
                          ),
                          items: [
                            for (final choice in entry.value.choices)
                              DropdownMenuItem(
                                value: choice,
                                child: Text(choice),
                              ),
                          ],
                          onChanged: (_) {},
                          onSaved: (value) => values[entry.key] = value!,
                        ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () {
            final state = form.currentState!;
            if (!state.validate()) return;
            state.save();
            Navigator.pop(context, values);
          },
          child: const Text('Gửi'),
        ),
      ],
    );
  },
);

class PortalStationPicker extends StatelessWidget {
  const PortalStationPicker({
    super.key,
    required this.stations,
    required this.stationId,
    required this.onChanged,
  });

  final List<PortalRow> stations;
  final int stationId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    key: ValueKey(stationId),
    initialValue: stationId,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Trạm'),
    items: [
      for (final station in stations)
        DropdownMenuItem(
          value: (station['station_id'] as num).toInt(),
          child: Text(
            '#${station['station_id']} · ${station['name']}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (id) {
      if (id != null) onChanged(id);
    },
  );
}
