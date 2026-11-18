import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U5 – Form đặt lịch: chọn xe, giờ đến/lấy xe, SOC hiện tại/mục tiêu,
/// kiểm tra 4 điều kiện trước khi gửi vào hàng đợi cụm.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const _eta = 0.92;
  final _station = Mock.nguyenVanLinh;
  Vehicle _vehicle = Mock.vehicles.first;
  TimeOfDay _arrival = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _departure = const TimeOfDay(hour: 17, minute: 30);
  double _socNow = 30;
  double _socTarget = 80;

  int _min(TimeOfDay t) => t.hour * 60 + t.minute;
  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  double get _energy =>
      (_socTarget - _socNow) / 100 * _vehicle.model.batteryKwh / _eta;

  List<Port> get _compatible => _station.ports
      .where(
        (p) =>
            p.connector == _vehicle.model.connector &&
            p.status == PortStatus.active,
      )
      .toList();

  Future<void> _pick(bool arrival) async {
    final t = await showTimePicker(
      context: context,
      initialTime: arrival ? _arrival : _departure,
    );
    if (t == null) return;
    setState(() => arrival ? _arrival = t : _departure = t);
  }

  @override
  Widget build(BuildContext context) {
    final m = _vehicle.model;
    final connectorOk = _compatible.isNotEmpty;
    final socOk = _socNow < _socTarget && _socTarget <= 100;
    final timeOk = _min(_departure) > _min(_arrival);
    final allOk = connectorOk && socOk && timeOk;
    final codes = _compatible.map((p) => p.code).join(', ');

    return UserScaffold(
      gap: 14,
      actionBar: GlassActionBar(
        children: [
          Expanded(
            child: AppButton(
              label: 'Gửi yêu cầu & Xếp lịch',
              icon: AppIcons.ai,
              radius: 999,
              height: 54,
              kind: allOk ? AppButtonKind.primary : AppButtonKind.outline,
              onPressed: allOk ? () => context.go('/schedule') : null,
            ),
          ),
        ],
      ),
      children: [
        MobileHeader(
          title: 'Đặt lịch sạc',
          onBack: () => context.go('/station'),
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
                    BoldText(_station.name),
                    MutedText(
                      'Cụm Hải Châu · mở 24/7 · trần trạm ${vnDec(_station.capKw, 0)} kW',
                      size: 12,
                    ),
                  ],
                ),
              ),
              LinkText('Đổi', size: 13, onTap: () => context.go('/map')),
            ],
          ),
        ),
        _Section(
          label: '1. Chọn xe',
          children: [
            DropdownButtonFormField<Vehicle>(
              initialValue: _vehicle,
              isExpanded: true,
              style: AppFonts.body(size: 14, weight: FontWeight.w600),
              items: [
                for (final v in Mock.vehicles)
                  DropdownMenuItem(
                    value: v,
                    child: Text(
                      '${v.nickname} · ${v.plate}${v.isDefault ? ' (mặc định)' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _vehicle = v!;
                _socTarget = v.defaultSoc.toDouble();
                if (_socNow >= _socTarget) _socNow = _socTarget - 10;
              }),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill.neutral('${m.brand} ${m.name}'),
                Pill.neutral(m.connector),
                Pill.neutral('Pin ${vnDec(m.batteryKwh, 1)} kWh'),
                Pill.neutral(
                  'Tối đa ${vnDec(m.maxKw, m.maxKw % 1 == 0 ? 0 : 1)} kW',
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MutedText(
                  'Thông số lấy từ danh mục mẫu xe, không chỉnh tay. ',
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
                    value: '05/12 · ${_fmt(_arrival)}',
                    onTap: () => _pick(true),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: _TimeTile(
                    label: 'Giờ lấy xe (departure)',
                    value: '05/12 · ${_fmt(_departure)}',
                    onTap: () => _pick(false),
                    error: !timeOk,
                  ),
                ),
              ],
            ),
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
                        ? '(${_socTarget.round()} − ${_socNow.round()})% × ${vnDec(m.batteryKwh, 1)} kWh ÷ ${vnDec(_eta, 2)} = ${vnDec(_energy, 2)} kWh'
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
                  ? 'xe ${m.connector} – trạm có ${_compatible.length} cổng ${m.connector} đang hoạt động ($codes). Hệ thống tự gán cổng.'
                  : 'trạm không có cổng ${m.connector} đang hoạt động. Gợi ý: Trạm ShareGrid Bạch Đằng.',
            ),
            _Check(
              ok: socOk && timeOk,
              title: 'SOC & giờ hợp lệ',
              body: socOk && timeOk
                  ? '${_socNow.round()}% < ${_socTarget.round()}% ≤ 100%, giờ lấy xe sau giờ đến, trạm mở 24/7, trong giới hạn phiên 360 phút.'
                  : 'cần pin hiện tại < pin mục tiêu ≤ 100% và giờ lấy xe sau giờ đến.',
            ),
            _Check(
              ok: true,
              title: 'Không trùng lịch',
              body:
                  'xe ${_vehicle.plate} chưa có yêu cầu khác trong khung giờ này.',
            ),
            _Check(
              ok: allOk,
              title: 'Đưa vào hàng đợi',
              body: allOk
                  ? 'yêu cầu được xếp chung với các yêu cầu đang hoạt động của cụm Hải Châu.'
                  : 'sửa các mục chưa đạt để gửi yêu cầu.',
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
