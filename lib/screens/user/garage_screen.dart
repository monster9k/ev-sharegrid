import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
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
  late var _models = _api.getVehicleModels();

  @override
  Widget build(BuildContext context) {
    final profile = _api.currentUser;
    final vehicles =
        (profile?['vehicles'] as List?)?.whereType<Map>() ?? const [];
    return UserScaffold(
      tab: UserTab.profile,
      showSimulationTag: false,
      children: [
        MobileHeader(title: 'Xe của tôi', onBack: () => context.go('/profile')),
        if (profile == null)
          const SignInCard('Đăng nhập để xem xe đã đăng ký.')
        else if (vehicles.isEmpty)
          const AppCard(child: MutedText('Tài khoản chưa có xe đăng ký.'))
        else
          for (final vehicle in vehicles)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BoldText(
                    '${vehicle['nickname'] ?? vehicle['model_name']} · ${vehicle['plate_number'] ?? '—'}',
                  ),
                  const Gap(4),
                  MutedText(
                    '${vehicle['brand']} ${vehicle['model_name']} · ${vehicle['connector_type']}',
                  ),
                  if (vehicle['is_default'] == true)
                    const MutedText('Xe mặc định'),
                ],
              ),
            ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _models,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LinearProgressIndicator();
            }
            if (snapshot.hasError) {
              return ApiErrorCard(
                error: snapshot.error!,
                onRetry: () =>
                    setState(() => _models = _api.getVehicleModels()),
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
