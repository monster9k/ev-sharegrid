import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U2 – Garage: danh sách xe + thêm xe từ danh mục `vehicle_model`
/// (không cho tự nhập thông số hãng).
class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});
  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  String _brand = 'VinFast';
  VehicleModel _model = Mock.vf5;
  double _soc = 80;
  bool _default = false;

  List<VehicleModel> get _models =>
      Mock.vehicleModels.where((m) => m.brand == _brand).toList();

  @override
  Widget build(BuildContext context) {
    final brands = {for (final m in Mock.vehicleModels) m.brand}.toList();
    return UserScaffold(
      gap: 14,
      actionBar: GlassActionBar(
        children: [
          Expanded(
            child: AppButton(
              label: 'Lưu xe',
              radius: 999,
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã lưu xe (dữ liệu mẫu)')),
                );
                context.go('/profile');
              },
            ),
          ),
        ],
      ),
      children: [
        MobileHeader(
          title: 'Xe của tôi',
          onBack: () => context.go('/profile'),
          trailing: MutedText('${Mock.vehicles.length} xe'),
        ),
        for (final v in Mock.vehicles) _VehicleCard(vehicle: v),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Thêm xe', style: AppFonts.display(size: 19)),
              const Gap(14),
              _Field(
                label: 'Hãng xe',
                child: DropdownButtonFormField<String>(
                  initialValue: _brand,
                  items: [
                    for (final b in brands)
                      DropdownMenuItem(value: b, child: Text(b)),
                  ],
                  onChanged: (b) => setState(() {
                    _brand = b!;
                    _model = _models.first;
                  }),
                ),
              ),
              const Gap(14),
              _Field(
                label: 'Mẫu xe',
                child: DropdownButtonFormField<VehicleModel>(
                  key: ValueKey(_brand),
                  initialValue: _model,
                  items: [
                    for (final m in _models)
                      DropdownMenuItem(value: m, child: Text(m.name)),
                  ],
                  onChanged: (m) => setState(() => _model = m!),
                ),
              ),
              const Gap(14),
              Row(
                children: [
                  const Icon(AppIcons.lock, size: 15, color: AppColors.muted),
                  const Gap(6),
                  Expanded(
                    child: MutedText(
                      'Thông số tự điền từ danh mục mẫu xe',
                      size: 12,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Gap(8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _Spec('Loại xe', _model.type),
                        _Spec('Đầu nối', _model.connector),
                      ],
                    ),
                    const Gap(10),
                    Row(
                      children: [
                        _Spec(
                          'Dung lượng pin',
                          '${vnDec(_model.batteryKwh, _model.batteryKwh % 1 == 0 ? 0 : 2)} kWh',
                        ),
                        _Spec(
                          'Công suất sạc tối đa',
                          '${vnDec(_model.maxKw, _model.maxKw % 1 == 0 ? 0 : 1)} kW',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(6),
              MutedText(
                'Nguồn: REAL · ${_model.sourceRef}. Không chỉnh tay thông số hãng.',
                size: 11,
              ),
              const Gap(14),
              const _Field(
                label: 'Biển số',
                child: TextField(
                  decoration: InputDecoration(hintText: 'vd: 43A-123.45'),
                ),
              ),
              const Gap(14),
              const _Field(
                label: 'Tên gợi nhớ',
                child: TextField(
                  decoration: InputDecoration(hintText: 'vd: VF5 đi làm'),
                ),
              ),
              const Gap(14),
              Row(
                children: [
                  Expanded(
                    child: MutedText(
                      'Pin mục tiêu mặc định',
                      size: 12,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${_soc.round()}%',
                    style: AppFonts.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _soc,
                min: 50,
                max: 100,
                divisions: 10,
                label: '${_soc.round()}%',
                onChanged: (v) => setState(() => _soc = v),
              ),
              CheckboxListTile(
                value: _default,
                onChanged: (v) => setState(() => _default = v!),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Đặt làm xe mặc định',
                  style: AppFonts.body(size: 14, weight: FontWeight.w600),
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MutedText('Không thấy mẫu xe? ', size: 12),
                  LinkText('Đề xuất bổ sung danh mục', size: 12, onTap: () {}),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final m = vehicle.model;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: vehicle.isDefault ? AppColors.blue : AppColors.border,
          width: vehicle.isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBox(
                m.type == 'CAR' ? AppIcons.car : AppIcons.moto,
                radius: 12,
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BoldText(vehicle.nickname),
                    MutedText(
                      '${vehicle.plate} · ${m.brand} ${m.name}',
                      size: 12,
                    ),
                  ],
                ),
              ),
              if (vehicle.isDefault)
                const Pill(
                  'Mặc định',
                  bg: AppColors.sky100,
                  fg: AppColors.blue,
                  radius: 6,
                  size: 11,
                )
              else
                LinkText('Đặt mặc định', size: 13, onTap: () {}),
            ],
          ),
          const Gap(10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in [
                m.type,
                m.connector,
                '${vnDec(m.batteryKwh, 1)} kWh',
                '≤ ${vnDec(m.maxKw, m.maxKw % 1 == 0 ? 0 : 1)} kW',
                'Mục tiêu ${vehicle.defaultSoc}%',
              ])
                Pill.neutral(s),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MutedText(label, size: 12, weight: FontWeight.w700),
      const Gap(6),
      child,
    ],
  );
}

class _Spec extends StatelessWidget {
  const _Spec(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [MutedText(label, size: 12), BoldText(value, size: 14)],
    ),
  );
}
