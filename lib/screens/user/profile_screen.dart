import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.client});

  final ApiClient? client;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ApiClient get _api => widget.client ?? apiClient;
  late Future<Map<String, dynamic>>? _profile = _api.accessToken == null
      ? null
      : _api.getMe();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _profile,
    builder: (context, snapshot) {
      final profile = snapshot.data;
      return UserScaffold(
        tab: UserTab.profile,
        showSimulationTag: false,
        children: [
          Text('Tài khoản', style: AppFonts.display(size: 26)),
          if (_profile == null)
            const SignInCard('Đăng nhập để xem thông tin tài khoản.')
          else if (snapshot.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            ApiErrorCard(
              error: snapshot.error!,
              onRetry: () => setState(() => _profile = _api.getMe()),
            )
          else if (profile != null)
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const IconBox(AppIcons.profile, size: 44),
                title: BoldText(
                  profile['full_name']?.toString() ?? 'Tài khoản',
                ),
                subtitle: MutedText(profile['email']?.toString() ?? ''),
                trailing: Pill(profile['role']?.toString() ?? '—'),
              ),
            ),
          if (_api.accessToken != null) ...[
            AppCard(
              onTap: () => context.go('/garage'),
              child: const BoldText('Quản lý xe'),
            ),
            AppCard(
              onTap: () => context.go('/notifications'),
              child: const BoldText('Thông báo'),
            ),
            if (_api.role case 'HOST' || 'ADMIN')
              AppCard(
                onTap: () =>
                    context.go(_api.role == 'HOST' ? '/host' : '/admin'),
                child: Text(_api.role == 'HOST' ? 'Cổng chủ trạm' : 'Quản trị'),
              ),
            AppButton(
              label: 'Đăng xuất',
              kind: AppButtonKind.outline,
              onPressed: () {
                _api.clearSession();
                context.go('/login');
              },
            ),
          ],
        ],
      );
    },
  );
}
