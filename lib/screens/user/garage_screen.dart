import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key, this.client});

  final ApiClient? client;

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  late var _modelsFuture = _api.getVehicleModels();
  List<Map<String, dynamic>>? _vehicles;
  List<Map<String, dynamic>> _models = [];
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await _modelsFuture;
      if (mounted) setState(() => _models = models);
    } catch (_) {}
  }

  Future<void> _loadVehicles() async {
    if (_api.accessToken == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      List<Map<String, dynamic>> list;
      try {
        list = await _api.getVehicles();
      } catch (_) {
        // Fallback to getMe if getVehicles is unavailable
        final me = await _api.getMe();
        list =
            (me['vehicles'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      }
      if (mounted) {
        setState(() {
          _vehicles = list;
        });
      }
    } catch (err) {
      if (mounted) setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDefault(Map<String, dynamic> vehicle) async {
    final id = (vehicle['vehicle_id'] as num).toInt();
    try {
      await _api.updateVehicle(id, isDefault: true);
      await _api.getMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã đặt ${vehicle['nickname'] ?? vehicle['plate_number']} làm xe mặc định.',
          ),
        ),
      );
      await _loadVehicles();
    } catch (err) {
      if (!mounted) return;
      final msg = err is ApiException ? err.userMessage : err.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể đặt mặc định: $msg')));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> vehicle) async {
    final id = (vehicle['vehicle_id'] as num).toInt();
    final plate =
        vehicle['plate_number'] ?? vehicle['license_plate'] ?? 'xe này';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xóa xe $plate?'),
        content: const Text(
          'Hành động này sẽ xóa xe khỏi tài khoản của bạn. Không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Xác nhận xóa'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.deleteVehicle(id);
      await _api.getMe();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã xóa xe $plate thành công.')));
      await _loadVehicles();
    } catch (err) {
      if (!mounted) return;
      final msg = err is ApiException ? err.userMessage : err.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi xóa xe: $msg')));
    }
  }

  void _openVehicleFormDialog({Map<String, dynamic>? editingVehicle}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _VehicleFormDialog(
        editingVehicle: editingVehicle,
        models: _models,
        onSave: (modelId, plate, nickname, isDefault) async {
          if (editingVehicle != null) {
            final id = (editingVehicle['vehicle_id'] as num).toInt();
            await _api.updateVehicle(
              id,
              modelId: modelId,
              licensePlate: plate,
              nickname: nickname,
              isDefault: isDefault,
            );
          } else {
            await _api.createVehicle(
              modelId: modelId,
              licensePlate: plate,
              nickname: nickname,
              isDefault: isDefault,
            );
          }
          await _api.getMe();
          await _loadVehicles();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _api.currentUser;
    final vehicles =
        _vehicles ??
        (profile?['vehicles'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];

    return UserScaffold(
      tab: UserTab.profile,
      showSimulationTag: false,
      children: [
        MobileHeader(
          title: 'Xe của tôi',
          onBack: () => context.go('/profile'),
          trailing: profile != null
              ? AppButton(
                  label: '+ Thêm xe',
                  expand: false,
                  height: 38,
                  radius: 999,
                  fontSize: 13,
                  onPressed: () => _openVehicleFormDialog(),
                )
              : null,
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          ApiErrorCard(error: _error!, onRetry: _loadVehicles),
        if (profile == null)
          const SignInCard('Đăng nhập để xem xe đã đăng ký.')
        else if (vehicles.isEmpty && !_loading)
          AppCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.directions_car_outlined,
                      size: 44,
                      color: AppColors.muted,
                    ),
                    const Gap(10),
                    const BoldText('Tài khoản chưa có xe đăng ký.', size: 15),
                    const Gap(4),
                    const MutedText(
                      'Thêm phương tiện để bắt đầu đặt lịch sạc tại các trạm.',
                      size: 13,
                    ),
                    const Gap(14),
                    AppButton(
                      label: 'Thêm xe ngay',
                      radius: 999,
                      fontSize: 13,
                      onPressed: () => _openVehicleFormDialog(),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          for (final vehicle in vehicles)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: BoldText(
                            '${vehicle['brand'] ?? ''} ${vehicle['model_name'] ?? 'Mẫu xe'}',
                            size: 16,
                          ),
                        ),
                        if (vehicle['is_default'] == true)
                          Pill(
                            'Mặc định',
                            bg: AppColors.successBg,
                            fg: AppColors.success,
                          ),
                      ],
                    ),
                    const Gap(6),
                    Text(
                      '${vehicle['nickname'] != null ? '${vehicle['nickname']} · ' : ''}${vehicle['plate_number'] ?? vehicle['license_plate'] ?? '—'}',
                      style: AppFonts.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                    const Gap(4),
                    MutedText(
                      '${vehicle['connector_type'] ?? 'CCS2'} · ${vehicle['battery_kwh'] ?? '—'} kWh · Tối đa ${vehicle['max_kw'] ?? '—'} kW',
                      size: 12,
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        if (vehicle['is_default'] != true) ...[
                          AppButton(
                            label: 'Đặt làm mặc định',
                            kind: AppButtonKind.outline,
                            radius: 999,
                            fontSize: 12,
                            onPressed: () => _setDefault(vehicle),
                          ),
                          const Gap(8),
                        ],
                        AppButton(
                          label: 'Sửa',
                          kind: AppButtonKind.ghost,
                          radius: 999,
                          fontSize: 12,
                          onPressed: () =>
                              _openVehicleFormDialog(editingVehicle: vehicle),
                        ),
                        const Spacer(),
                        AppButton(
                          label: 'Xóa',
                          kind: AppButtonKind.danger,
                          radius: 999,
                          fontSize: 12,
                          onPressed: () => _confirmDelete(vehicle),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const Gap(10),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _modelsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return ApiErrorCard(
                error: snapshot.error!,
                onRetry: () =>
                    setState(() => _modelsFuture = _api.getVehicleModels()),
              );
            }
            final models = snapshot.data ?? const [];
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BoldText('Danh mục mẫu xe · ${models.length} mẫu'),
                  if (models.isEmpty) const MutedText('Chưa có mẫu xe.'),
                  for (final model in models)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: BoldText(
                        '${model['brand']} ${model['model_name']}',
                      ),
                      subtitle: MutedText(
                        '${model['connector_type']} · ${model['battery_kwh']} kWh · ${model['max_kw']} kW',
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _VehicleFormDialog extends StatefulWidget {
  const _VehicleFormDialog({
    this.editingVehicle,
    required this.models,
    required this.onSave,
  });

  final Map<String, dynamic>? editingVehicle;
  final List<Map<String, dynamic>> models;
  final Future<void> Function(
    int modelId,
    String plate,
    String? nickname,
    bool isDefault,
  )
  onSave;

  @override
  State<_VehicleFormDialog> createState() => _VehicleFormDialogState();
}

class _VehicleFormDialogState extends State<_VehicleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late int? _selectedModelId;
  late TextEditingController _plateCtrl;
  late TextEditingController _nickCtrl;
  late bool _isDefault;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final v = widget.editingVehicle;
    _selectedModelId =
        (v?['model_id'] as num?)?.toInt() ??
        (widget.models.isNotEmpty
            ? (widget.models.first['model_id'] as num).toInt()
            : null);
    _plateCtrl = TextEditingController(
      text:
          v?['plate_number']?.toString() ??
          v?['license_plate']?.toString() ??
          '',
    );
    _nickCtrl = TextEditingController(text: v?['nickname']?.toString() ?? '');
    _isDefault = v?['is_default'] == true;
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedModelId == null) {
      setState(() => _errorMessage = 'Vui lòng chọn mẫu xe');
      return;
    }
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    try {
      await widget.onSave(
        _selectedModelId!,
        _plateCtrl.text.trim().toUpperCase(),
        _nickCtrl.text.trim().isEmpty ? null : _nickCtrl.text.trim(),
        _isDefault,
      );
      if (mounted) Navigator.pop(context);
    } catch (err) {
      if (mounted) {
        setState(() {
          _errorMessage = err is ApiException
              ? err.userMessage
              : err.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editingVehicle != null;

    return AlertDialog(
      title: Text(isEditing ? 'Chỉnh sửa xe' : 'Đăng ký xe mới'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.redBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: AppFonts.body(size: 12, color: AppColors.red),
                  ),
                ),
                const Gap(10),
              ],
              DropdownButtonFormField<int>(
                initialValue: _selectedModelId,
                decoration: const InputDecoration(
                  labelText: 'Mẫu xe',
                  prefixIcon: Icon(Icons.electric_car),
                ),
                items: [
                  for (final m in widget.models)
                    DropdownMenuItem<int>(
                      value: (m['model_id'] as num).toInt(),
                      child: Text(
                        '${m['brand']} ${m['model_name']} (${m['connector_type']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (val) => setState(() => _selectedModelId = val),
                validator: (val) => val == null ? 'Vui lòng chọn mẫu xe' : null,
              ),
              const Gap(12),
              TextFormField(
                controller: _plateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Biển số xe',
                  hintText: 'Ví dụ: 43A-123.45',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Vui lòng nhập biển số xe';
                  }
                  return null;
                },
              ),
              const Gap(12),
              TextFormField(
                controller: _nickCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên gợi nhớ (tùy chọn)',
                  hintText: 'Ví dụ: Xe Cưng, VF8 Đi Làm',
                  prefixIcon: Icon(Icons.edit_note),
                ),
              ),
              const Gap(12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Đặt làm xe mặc định'),
                value: _isDefault,
                onChanged: (val) => setState(() => _isDefault = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        AppButton(
          label: _saving
              ? 'Đang lưu…'
              : (isEditing ? 'Lưu thay đổi' : 'Thêm xe'),
          radius: 999,
          fontSize: 13,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}
