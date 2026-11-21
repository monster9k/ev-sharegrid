import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../data/charging_time.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U5 – Form đặt lịch: chọn xe, giờ đến/lấy xe, SOC hiện tại/mục tiêu,
/// kiểm tra 4 điều kiện trước khi gửi vào hàng đợi cụm.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, this.stationId, this.client});
  final int? stationId;
  final ApiClient? client;
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  static const _eta = 0.90;
  static const _slot = Duration(minutes: 15);
  static const _horizon = Duration(hours: 24);
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _stations = [];
  Map<String, dynamic>? _vehicle;
  Map<String, dynamic>? _station;
  Map<String, dynamic>? _stationDetail;
  late DateTime _arrival;
  late DateTime _departure;
  double _socNow = 30;
  double _socTarget = 80;
  bool _loadingData = false;
  bool _loadingStation = false;
  bool _submitting = false;
  String? _loadError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _arrival = _horizonStart().add(_slot);
    _departure = _arrival.add(const Duration(hours: 2));
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final profile = _api.currentUser;
    if (profile == null) {
      setState(
        () => _loadError = 'Đăng nhập để tải xe và trạm sạc của máy chủ.',
      );
      return;
    }
    final rawVehicles = profile['vehicles'];
    final vehicles = rawVehicles is List
        ? rawVehicles.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _vehicles = vehicles;
      _vehicle = vehicles.cast<Map<String, dynamic>?>().firstWhere(
        (vehicle) => vehicle?['is_default'] == true,
        orElse: () => vehicles.isEmpty ? null : vehicles.first,
      );
      if (_vehicle != null) {
        _socTarget =
            (_vehicle!['default_soc_target'] as num?)?.toDouble() ?? 80;
      }
      _loadingData = true;
      _loadError = null;
    });
    try {
      if (vehicles.isEmpty) {
        throw const FormatException(
          'Tài khoản chưa có xe đăng ký trên máy chủ.',
        );
      }
      final stations = await _api.getActiveStations();
      if (stations.isEmpty) {
        throw const FormatException('Máy chủ chưa có trạm ACTIVE để đặt lịch.');
      }
      final selected = stations
          .where((station) => station['station_id'] == widget.stationId)
          .firstOrNull;
      if (widget.stationId != null && selected == null) {
        if (!mounted) return;
        setState(() {
          _stations = stations;
          _loadError = 'Trạm được chọn chưa hoạt động. Hãy chọn trạm khác.';
        });
        return;
      }
      final station = selected ?? stations.first;
      final detail = await _api.getStation(
        (station['station_id'] as num).toInt(),
      );
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _station = station;
        _stationDetail = detail;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _selectStation(int stationId) async {
    final station = _stations.firstWhere(
      (item) => (item['station_id'] as num).toInt() == stationId,
    );
    setState(() {
      _station = station;
      _stationDetail = null;
      _loadingStation = true;
      _loadError = null;
    });
    try {
      final detail = await _api.getStation(stationId);
      if (mounted && _station?['station_id'] == stationId) {
        setState(() => _stationDetail = detail);
      }
    } catch (error) {
      if (mounted && _station?['station_id'] == stationId) {
        setState(() => _loadError = _errorMessage(error));
      }
    } finally {
      if (mounted && _station?['station_id'] == stationId) {
        setState(() => _loadingStation = false);
      }
    }
  }

  Future<void> _submit() async {
    final timeError = _validateTimes();
    if (timeError != null) {
      setState(() => _submitError = timeError);
      return;
    }
    final profile = _api.currentUser;
    final vehicleId = _vehicle?['vehicle_id'];
    final stationId = _station?['station_id'];
    if (profile == null || vehicleId is! num || stationId is! num) {
      setState(
        () => _submitError =
            'Thiếu thông tin tài khoản, xe hoặc trạm từ máy chủ.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final result = await _api.submitBooking(
        userId: (profile['user_id'] as num).toInt(),
        vehicleId: vehicleId.toInt(),
        stationId: stationId.toInt(),
        arrivalTime: _arrival.toIso8601String(),
        departureTime: _departure.toIso8601String(),
        socNow: _socNow,
        socTarget: _socTarget,
        idempotencyKey: 'booking-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) context.go('/schedule', extra: result);
    } catch (error) {
      if (!mounted) return;
      final message = _errorMessage(error);
      setState(() => _submitError = message);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  DateTime _horizonStart() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute - now.minute % _slot.inMinutes,
    );
  }

  String? _validateTimes() {
    if (!_departure.isAfter(_arrival)) {
      return 'Giờ lấy xe phải sau giờ đến.';
    }
    final start = _horizonStart();
    final end = start.add(_horizon);
    if (_arrival.isBefore(start) || _departure.isAfter(end)) {
      return 'Chọn giờ trong 24 giờ xếp lịch, đến ${_dateTimeLabel(end)}.';
    }
    return null;
  }

  String _errorMessage(Object error) => error is ApiException
      ? error.userMessage
      : 'Không thể kết nối máy chủ: $error';

  String get _connector => _vehicle?['connector_type']?.toString() ?? '';
  double get _batteryKwh => (_vehicle?['battery_kwh'] as num?)?.toDouble() ?? 0;
  double get _maxKw => (_vehicle?['max_kw'] as num?)?.toDouble() ?? 0;

  String _dateTimeLabel(DateTime instant) =>
      '${formatChargingDate(vietnamWallTime(instant))} · ${formatVietnamTime(instant)}';

  double get _energy => (_socTarget - _socNow) / 100 * _batteryKwh / _eta;

  List<Map<String, dynamic>> get _compatible {
    final ports = _stationDetail?['ports'];
    if (ports is! List) return [];
    return ports
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where(
          (port) =>
              port['connector_type'] == _connector &&
              port['status'] == 'ACTIVE',
        )
        .toList();
  }

  Future<void> _pick(bool arrival) async {
    final localTime = vietnamWallTime(arrival ? _arrival : _departure);
    final today = vietnamWallTime(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final day = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(arrival ? 'Chọn ngày đến' : 'Chọn ngày lấy xe'),
        children: [
          for (final (label, date) in [
            ('Hôm nay', today),
            ('Ngày mai', tomorrow),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, date),
              child: Text('$label · ${formatChargingDate(date)}'),
            ),
        ],
      ),
    );
    if (!mounted || day == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(localTime),
      helpText: arrival ? 'Chọn giờ đến' : 'Chọn giờ lấy xe',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
      hourLabelText: 'Giờ',
      minuteLabelText: 'Phút',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!mounted || time == null) return;
    final instant = DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).subtract(vietnamOffset);
    setState(() {
      if (arrival) {
        _arrival = instant;
      } else {
        _departure = instant;
      }
      _submitError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userIsSignedIn = _api.currentUser != null;
    final connectorOk = _compatible.isNotEmpty;
    final socOk = _vehicle != null && _socNow < _socTarget && _socTarget <= 100;
    final timeError = _validateTimes();
    final timeOk = timeError == null;
    final allOk = connectorOk && socOk && timeOk && _station != null;
    final codes = _compatible.map((port) => port['port_code']).join(', ');
    final vehicleName = [
      _vehicle?['brand'],
      _vehicle?['model_name'],
    ].where((part) => part != null && part.toString().isNotEmpty).join(' ');
    final stationPower = (_station?['station_power_kw'] as num?)?.toDouble();
    final stationHours = _stationDetail?['is_24h'] == true
        ? 'mở 24/7'
        : '${_stationDetail?['open_time'] ?? '—'}–${_stationDetail?['close_time'] ?? '—'}';
    final buttonLabel = _submitting
        ? 'Đang gửi và xếp lịch…'
        : userIsSignedIn
        ? 'Gửi yêu cầu & Xếp lịch'
        : 'Đăng nhập để gửi yêu cầu';

    return UserScaffold(
      showSimulationTag: false,
      gap: 14,
      actionBar: GlassActionBar(
        children: [
          Expanded(
            child: AppButton(
              label: buttonLabel,
              icon: AppIcons.ai,
              radius: 999,
              height: 54,
              kind: allOk ? AppButtonKind.primary : AppButtonKind.outline,
              onPressed: _submitting
                  ? null
                  : !userIsSignedIn
                  ? () => context.go(
                      Uri(
                        path: '/login',
                        queryParameters: {
                          'next': GoRouterState.of(context).uri.toString(),
                        },
                      ).toString(),
                    )
                  : allOk
                  ? _submit
                  : null,
            ),
          ),
        ],
      ),
      children: [
        MobileHeader(
          title: 'Đặt lịch sạc',
          onBack: () => context.go(
            widget.stationId == null ? '/home' : '/station/${widget.stationId}',
          ),
        ),
        if (_loadingData || _loadingStation || _submitting)
          const LinearProgressIndicator(minHeight: 3),
        if (_loadError != null || _submitError != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.redBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _submitError ?? _loadError!,
              style: AppFonts.body(size: 13, color: AppColors.red),
            ),
          ),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const IconBox(AppIcons.station, size: 48),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BoldText(_station?['name']?.toString() ?? 'Chưa chọn trạm'),
                    MutedText(
                      _station == null
                          ? 'Đang tải danh sách trạm thật từ máy chủ.'
                          : 'Cụm ${_station?['cluster_id']} · $stationHours · trần trạm ${stationPower == null ? '—' : vnDec(stationPower, 1)} kW',
                      size: 12,
                    ),
                  ],
                ),
              ),
              if (_stations.isNotEmpty &&
                  (_stations.length > 1 || _station == null))
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                    initialValue: (_station?['station_id'] as num?)?.toInt(),
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Đổi trạm'),
                    items: [
                      for (final station in _stations)
                        DropdownMenuItem(
                          value: (station['station_id'] as num).toInt(),
                          child: Text('#${station['station_id']}'),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) _selectStation(id);
                    },
                  ),
                ),
            ],
          ),
        ),
        _Section(
          label: '1. Chọn xe',
          children: [
            if (_vehicles.isEmpty)
              MutedText('Tài khoản chưa có xe thật để đặt lịch.', size: 13)
            else
              DropdownButtonFormField<int>(
                initialValue: (_vehicle?['vehicle_id'] as num?)?.toInt(),
                isExpanded: true,
                style: AppFonts.body(size: 14, weight: FontWeight.w600),
                items: [
                  for (final vehicle in _vehicles)
                    DropdownMenuItem(
                      value: (vehicle['vehicle_id'] as num).toInt(),
                      child: Text(
                        '${vehicle['nickname'] ?? vehicle['model_name']} · ${vehicle['plate_number']}${vehicle['is_default'] == true ? ' (mặc định)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _vehicle = _vehicles.firstWhere(
                    (vehicle) => (vehicle['vehicle_id'] as num).toInt() == id,
                  );
                  _socTarget =
                      (_vehicle!['default_soc_target'] as num?)?.toDouble() ??
                      80;
                  if (_socNow >= _socTarget) _socNow = _socTarget - 10;
                }),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_vehicle != null) ...[
                  Pill.neutral(vehicleName),
                  Pill.neutral(_connector),
                  Pill.neutral('Pin ${vnDec(_batteryKwh, 1)} kWh'),
                  Pill.neutral('Tối đa ${vnDec(_maxKw, 1)} kW'),
                ],
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MutedText(
                  'Xe và thông số được tải từ tài khoản máy chủ. ',
                  size: 12,
                ),
                LinkText(
                  'Quản lý xe',
                  size: 12,
                  onTap: () => context.go('/garage'),
                ),
              ],
            ),
          ],
        ),
        _Section(
          label: '2. Thời gian xe ở trạm',
          children: [
            Row(
              children: [
                Expanded(
                  child: _TimeTile(
                    label: 'Giờ đến (arrival)',
                    value: _dateTimeLabel(_arrival),
                    onTap: () => _pick(true),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: _TimeTile(
                    label: 'Giờ lấy xe (departure)',
                    value: _dateTimeLabel(_departure),
                    onTap: () => _pick(false),
                    error: !timeOk,
                  ),
                ),
              ],
            ),
            if (timeError != null)
              MutedText(timeError, color: AppColors.red, size: 12),
          ],
        ),
        _Section(
          label: '3. Mức pin',
          children: [
            _SocSlider(
              label: 'Pin hiện tại',
              value: _socNow,
              onChanged: (v) => setState(() => _socNow = v),
            ),
            _SocSlider(
              label: 'Pin mục tiêu',
              value: _socTarget,
              onChanged: (v) => setState(() => _socTarget = v),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MutedText('Năng lượng cần nạp', size: 12),
                  Text(
                    socOk
                        ? 'Ước tính (${_socTarget.round()} − ${_socNow.round()})% × ${vnDec(_batteryKwh, 1)} kWh ÷ ${vnDec(_eta, 2)} = ${vnDec(_energy, 2)} kWh'
                        : 'Pin mục tiêu phải lớn hơn pin hiện tại',
                    style: AppFonts.numbers(
                      size: 16,
                      color: socOk ? AppColors.ink : AppColors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        _Section(
          label: 'Kiểm tra trước khi gửi',
          children: [
            _Check(
              ok: connectorOk,
              title: 'Đầu nối khớp',
              body: connectorOk
                  ? 'Xe $_connector – trạm có ${_compatible.length} cổng $_connector đang hoạt động ($codes). Máy chủ sẽ xếp cổng.'
                  : 'Máy chủ chưa xác nhận cổng $_connector đang hoạt động tại trạm này.',
            ),
            _Check(
              ok: socOk && timeOk,
              title: 'SOC & giờ hợp lệ',
              body: socOk && timeOk
                  ? '${_socNow.round()}% < ${_socTarget.round()}% ≤ 100%, giờ lấy xe sau giờ đến.'
                  : 'cần pin hiện tại < pin mục tiêu ≤ 100% và giờ lấy xe sau giờ đến.',
            ),
            _Check(
              ok: _vehicle != null,
              title: 'Không trùng lịch',
              body: 'Máy chủ sẽ kiểm tra lịch trùng của xe khi nhận yêu cầu.',
            ),
            _Check(
              ok: allOk,
              title: 'Đưa vào hàng đợi',
              body: allOk
                  ? 'Yêu cầu sẽ được gửi tới máy chủ để xếp cùng các yêu cầu đang hoạt động.'
                  : 'Đăng nhập, chọn xe/trạm hợp lệ và sửa các mục chưa đạt.',
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BoldText(label, size: 14),
        for (final c in children) ...[const Gap(12), c],
      ],
    ),
  );
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
    this.error = false,
  });
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool error;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MutedText(label, size: 12, weight: FontWeight.w600, maxLines: 1),
      const Gap(6),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: error ? AppColors.red : AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                const Icon(AppIcons.clock, size: 17, color: AppColors.blue),
                const Gap(6),
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.body(size: 14, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _SocSlider extends StatelessWidget {
  const _SocSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: BoldText(label, size: 13)),
          Text(
            '${value.round()}%',
            style: AppFonts.body(
              size: 13,
              weight: FontWeight.w700,
              color: AppColors.blue,
            ),
          ),
        ],
      ),
      Slider(
        value: value,
        max: 100,
        divisions: 20,
        label: '${value.round()}%',
        onChanged: onChanged,
      ),
    ],
  );
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.title, required this.body});
  final bool ok;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ok ? AppColors.successBg : AppColors.redBg,
          shape: BoxShape.circle,
        ),
        child: Icon(
          ok ? Icons.check_rounded : Icons.close_rounded,
          size: 14,
          color: ok ? AppColors.success : AppColors.red,
        ),
      ),
      const Gap(10),
      Expanded(
        child: Text.rich(
          TextSpan(
            style: AppFonts.body(size: 13, color: AppColors.body, height: 1.45),
            children: [
              TextSpan(
                text: '$title: ',
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              TextSpan(text: body),
            ],
          ),
        ),
      ),
    ],
  );
}
