import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U6 – Hiển thị lịch và KPI nhận trực tiếp từ API đặt lịch.
class ScheduleResultScreen extends StatefulWidget {
  const ScheduleResultScreen({
    super.key,
    this.bookingResult,
    this.requestId,
    this.client,
  });

  final Map<String, dynamic>? bookingResult;
  final int? requestId;
  final ApiClient? client;

  @override
  State<ScheduleResultScreen> createState() => _ScheduleResultScreenState();
}

class _ScheduleResultScreenState extends State<ScheduleResultScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  Map<String, dynamic>? _schedule;
  bool _loading = false;
  bool _working = false;
  String? _error;
  String? _actionError;
  String? _confirmedStatus;

  int? get _requestId {
    final value = widget.bookingResult?['request_id'];
    return widget.requestId ??
        (value is num
            ? value.toInt()
            : int.tryParse(value?.toString() ?? '')) ??
        _api.lastRequestId;
  }

  @override
  void initState() {
    super.initState();
    if (_requestId case final id?) _loadSchedule(id);
  }

  Future<void> _loadSchedule(int requestId) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final schedule = await _api.getRequestSchedule(requestId);
      if (mounted) {
        setState(() {
          _schedule = schedule;
          _confirmedStatus = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(Object error) => error is ApiException
      ? error.userMessage
      : 'Không thể tải lịch từ máy chủ: $error';

  Map<String, dynamic> get _data {
    final root = _schedule ?? const <String, dynamic>{};
    final nested = root['data'];
    return nested is Map ? Map<String, dynamic>.from(nested) : root;
  }

  Map<String, dynamic> get _summary {
    final root = _data;
    final summary = root['summary'] ?? root['request_result'];
    final result =
        widget.bookingResult ??
        (_requestId == _api.lastRequestId ? _api.lastBooking : null) ??
        const <String, dynamic>{};
    return {
      ...result,
      if (summary is Map) ...Map<String, dynamic>.from(summary),
      ...root,
    };
  }

  List<Map<String, dynamic>> get _slotRows {
    final root = _data;
    final raw = root['slots'] ?? root['schedules'] ?? root['schedule'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
      ..sort((a, b) => _slotTime(a).compareTo(_slotTime(b)));
  }

  DateTime _slotTime(Map<String, dynamic> slot) =>
      DateTime.tryParse(
        (slot['slot_start'] ?? slot['start_time'] ?? slot['start'])
                ?.toString() ??
            '',
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  double _power(Map<String, dynamic> slot) =>
      ((slot['power_kw'] ?? slot['allocated_kw'] ?? slot['kw']) as num?)
          ?.toDouble() ??
      0;

  List<ScheduleSlot> get _chartSlots {
    final rows = _slotRows;
    if (rows.isEmpty) return const [];
    final first = _slotTime(rows.first);
    return [
      for (final row in rows)
        ScheduleSlot(
          _slotTime(row).difference(first).inMinutes / 60,
          _power(row),
        ),
    ];
  }

  double get _chartEnd {
    if (_slotRows.isEmpty) return 1;
    final last = _slotTime(_slotRows.last);
    final first = _slotTime(_slotRows.first);
    return (last.difference(first).inMinutes / 60) + .25;
  }

  double get _maxPower => _slotRows.fold<double>(
    1,
    (maxPower, slot) => _power(slot) > maxPower ? _power(slot) : maxPower,
  );

  String _fmtNumber(Object? value, {int fractionDigits = 2}) {
    if (value == null) return '—';
    if (value is num) return value.toStringAsFixed(fractionDigits);
    return value.toString();
  }

  Future<void> _changeRequest({required bool confirm}) async {
    final id = _requestId;
    if (id == null) return;
    setState(() {
      _working = true;
      _actionError = null;
    });
    try {
      if (confirm) {
        final result = await _api.confirmRequest(id);
        if (!mounted) return;
        setState(() => _confirmedStatus = result['status'] as String?);
      } else {
        await _api.cancelRequest(id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(confirm ? 'Đã xác nhận lịch.' : 'Đã gửi yêu cầu hủy.'),
        ),
      );
      if (!confirm) context.go('/sessions');
    } catch (error) {
      if (mounted) setState(() => _actionError = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _requestId;
    final summary = _summary;
    final slots = _slotRows;
    final status =
        _confirmedStatus ?? (_data['status'] ?? summary['status'])?.toString();
    final canConfirm = status == 'SCHEDULED';
    final canCancel =
        canConfirm || status == 'CONFIRMED' || status == 'PENDING';
    final actionDisabled = _loading || _working;
    final algorithm = (_data['algorithm'] ?? summary['algorithm'])?.toString();
    final firstStart = slots.isEmpty ? null : _slotTime(slots.first);
    final lastStart = slots.isEmpty ? null : _slotTime(slots.last);
    final firstPort = slots.isEmpty
        ? '—'
        : (slots.first['port_code'] ?? slots.first['port_id'] ?? '—')
              .toString();
    final actionBar = id == null || !canCancel
        ? null
        : GlassActionBar(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Hủy yêu cầu',
                  kind: AppButtonKind.ghost,
                  radius: 999,
                  fontSize: 14,
                  onPressed: actionDisabled
                      ? null
                      : () => _confirmCancel(context),
                ),
              ),
              if (canConfirm)
                Expanded(
                  child: AppButton(
                    label: _working ? 'Đang gửi…' : 'Xác nhận lịch',
                    radius: 999,
                    fontSize: 14,
                    onPressed: actionDisabled
                        ? null
                        : () => _changeRequest(confirm: true),
                  ),
                ),
            ],
          );

    return UserScaffold(
      showSimulationTag: false,
      gap: 12,
      tab: UserTab.smart,
      actionBar: actionBar,
      children: [
        MobileHeader(
          title: 'Kết quả lịch sạc',
          onBack: () => context.go('/booking'),
          trailing: const Pill(
            'Dữ liệu máy chủ',
            bg: AppColors.successBg,
            fg: AppColors.success,
            radius: 6,
            size: 11,
          ),
        ),
        if (_loading || _working) const LinearProgressIndicator(minHeight: 3),
        if (_error != null || _actionError != null)
          _Notice(
            text: _error ?? _actionError!,
            error: true,
            onRetry: id == null ? null : () => _loadSchedule(id),
          ),
        if (id == null)
          const _Notice(
            text: 'Chưa có lịch sạc. Hãy gửi yêu cầu ở màn Đặt lịch.',
          )
        else if (!_loading && _error == null && _schedule != null) ...[
          AppCard(
            color: AppColors.sky200,
            borderColor: null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Pill(
                      status ?? '—',
                      bg: status == 'CONFIRMED'
                          ? AppColors.success
                          : AppColors.warning,
                      fg: Colors.white,
                    ),
                    MutedText(
                      [
                            if (algorithm != null && algorithm != '—')
                              algorithm,
                            if (_data['solve_ms'] != null)
                              '${_fmtNumber(_data['solve_ms'])} ms',
                          ].join(' · ').isEmpty
                          ? 'Thông tin bộ giải chưa được trả về'
                          : [
                              if (algorithm != null && algorithm != '—')
                                algorithm,
                              if (_data['solve_ms'] != null)
                                '${_fmtNumber(_data['solve_ms'])} ms',
                            ].join(' · '),
                      size: 12,
                      color: AppColors.skyInk,
                    ),
                  ],
                ),
                const Gap(12),
                BoldText('Yêu cầu #$id', size: 18, color: AppColors.skyInk),
                const Gap(4),
                MutedText(
                  slots.isEmpty
                      ? 'Máy chủ chưa phân bổ slot sạc cho yêu cầu này.'
                      : 'Cổng $firstPort · ${formatVietnamTime(firstStart!)}–${formatVietnamTime(lastStart!.add(const Duration(minutes: 15)))}',
                  color: AppColors.skyInk,
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(
                  label: summary['expected_soc'] == null
                      ? 'Đáp ứng nhu cầu'
                      : 'SOC dự kiến',
                  value: summary['expected_soc'] == null
                      ? '—'
                      : '${_fmtNumber(summary['expected_soc'])}%',
                  note: 'theo kết quả API',
                  width: (constraints.maxWidth - 16) / 3,
                ),
                _Metric(
                  label: 'Điện thiếu',
                  value: _fmtNumber(summary['shortfall_kwh']),
                  note: 'kWh',
                  width: (constraints.maxWidth - 16) / 3,
                ),
                _Metric(
                  label: 'Chi phí điện',
                  value: _fmtNumber(summary['estimated_cost_vnd']),
                  note: 'VND',
                  width: (constraints.maxWidth - 16) / 3,
                ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Lịch theo slot 15 phút',
                        style: AppFonts.display(size: 17),
                      ),
                    ),
                    MutedText('${slots.length} slot', size: 12),
                  ],
                ),
                const Gap(10),
                if (slots.isEmpty)
                  const MutedText('API chưa trả về slot sạc.', size: 13)
                else ...[
                  SlotScheduleChart(
                    slots: _chartSlots,
                    from: 0,
                    to: _chartEnd,
                    maxKw: _maxPower,
                    showTariffBands: false,
                  ),
                  const Gap(8),
                  for (var index = 0; index < slots.length; index++)
                    _SlotLine(
                      start: _slotTime(slots[index]),
                      powerKw: _power(slots[index]),
                      port:
                          (slots[index]['port_code'] ??
                                  slots[index]['port_id'] ??
                                  '—')
                              .toString(),
                      last: index == slots.length - 1,
                    ),
                ],
              ],
            ),
          ),
          if ((summary['explanation'] ?? _data['explanation']) is String)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BoldText('Giải thích từ máy chủ', size: 14),
                  const Gap(6),
                  Text(
                    (summary['explanation'] ?? _data['explanation']).toString(),
                    style: AppFonts.body(size: 13, color: AppColors.body),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  void _confirmCancel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Hủy yêu cầu #$_requestId?'),
        content: const Text(
          'Yêu cầu hủy sẽ được gửi tới máy chủ. Lịch chỉ được cập nhật khi máy chủ xác nhận.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Giữ lịch'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _changeRequest(confirm: false);
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Gửi yêu cầu hủy'),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.error = false, this.onRetry});

  final String text;
  final bool error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    color: error ? AppColors.redBg : AppColors.sky100,
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: AppFonts.body(
              size: 13,
              color: error ? AppColors.red : AppColors.skyInk,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.note,
    required this.width,
  });

  final String label;
  final String value;
  final String note;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: AppCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText(label, size: 11, maxLines: 1),
          const Gap(3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppFonts.numbers(size: 16)),
          ),
          MutedText(note, size: 10),
        ],
      ),
    ),
  );
}

class _SlotLine extends StatelessWidget {
  const _SlotLine({
    required this.start,
    required this.powerKw,
    required this.port,
    required this.last,
  });

  final DateTime start;
  final double powerKw;
  final String port;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${formatVietnamTime(start)} · Cổng $port · ${powerKw.toString()} kW',
            style: AppFonts.body(size: 12),
          ),
        ),
        Text(
          '${(powerKw * .25).toStringAsFixed(3)} kWh',
          style: AppFonts.body(size: 12, weight: FontWeight.w600),
        ),
      ],
    ),
  );
}
