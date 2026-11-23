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

  Future<void> _openEditProfileDialog(Map<String, dynamic> profile) async {
    final messenger = ScaffoldMessenger.of(context);
    final nameCtrl = TextEditingController(
      text: profile['full_name']?.toString() ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: profile['phone']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    String? errorMessage;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Chỉnh sửa hồ sơ'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        errorMessage!,
                        style: AppFonts.body(size: 12, color: AppColors.red),
                      ),
                    ),
                    const Gap(10),
                  ],
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Vui lòng nhập họ và tên';
                      }
                      return null;
                    },
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      hintText: 'Ví dụ: 0901234567',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Hủy'),
            ),
            AppButton(
              label: saving ? 'Đang lưu…' : 'Lưu thay đổi',
              expand: false,
              radius: 999,
              fontSize: 13,
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        saving = true;
                        errorMessage = null;
                      });
                      try {
                        await _api.updateProfile(
                          fullName: nameCtrl.text.trim(),
                          phone: phoneCtrl.text.trim().isEmpty
                              ? null
                              : phoneCtrl.text.trim(),
                        );
                        await _api.getMe();
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          setState(() => _profile = _api.getMe());
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Cập nhật hồ sơ thành công!'),
                            ),
                          );
                        }
                      } catch (err) {
                        if (dialogCtx.mounted) {
                          setDialogState(() {
                            saving = false;
                            errorMessage = err is ApiException
                                ? err.userMessage
                                : err.toString();
                          });
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    final messenger = ScaffoldMessenger.of(context);
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? errorMessage;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Đổi mật khẩu'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        errorMessage!,
                        style: AppFonts.body(size: 12, color: AppColors.red),
                      ),
                    ),
                    const Gap(10),
                  ],
                  TextFormField(
                    controller: curCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu hiện tại',
                      prefixIcon: Icon(Icons.lock_clock_outlined),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Vui lòng nhập mật khẩu hiện tại';
                      }
                      return null;
                    },
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới',
                      helperText: 'Tối thiểu 6 ký tự',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (val) {
                      if (val == null || val.length < 6) {
                        return 'Mật khẩu mới cần tối thiểu 6 ký tự';
                      }
                      return null;
                    },
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Xác nhận mật khẩu mới',
                      prefixIcon: Icon(Icons.check_circle_outline),
                    ),
                    validator: (val) {
                      if (val != newCtrl.text) {
                        return 'Mật khẩu xác nhận không khớp';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Hủy'),
            ),
            AppButton(
              label: saving ? 'Đang đổi…' : 'Đổi mật khẩu',
              expand: false,
              radius: 999,
              fontSize: 13,
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() {
                        saving = true;
                        errorMessage = null;
                      });
                      try {
                        await _api.changePassword(
                          currentPassword: curCtrl.text,
                          newPassword: newCtrl.text,
                        );
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Đổi mật khẩu thành công!'),
                            ),
                          );
                        }
                      } catch (err) {
                        if (dialogCtx.mounted) {
                          setDialogState(() {
                            saving = false;
                            errorMessage = err is ApiException
                                ? err.userMessage
                                : err.toString();
                          });
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconBox(AppIcons.profile, size: 44),
                    title: BoldText(
                      profile['full_name']?.toString() ?? 'Tài khoản',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MutedText(profile['email']?.toString() ?? ''),
                        if (profile['phone'] != null &&
                            profile['phone'].toString().isNotEmpty)
                          MutedText(profile['phone'].toString(), size: 13),
                      ],
                    ),
                    trailing: Pill(profile['role']?.toString() ?? '—'),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Chỉnh sửa hồ sơ',
                          kind: AppButtonKind.soft,
                          height: 38,
                          fontSize: 13,
                          icon: Icons.edit_outlined,
                          onPressed: () => _openEditProfileDialog(profile),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: AppButton(
                          label: 'Đổi mật khẩu',
                          kind: AppButtonKind.outline,
                          height: 38,
                          fontSize: 13,
                          icon: Icons.lock_outline_rounded,
                          onPressed: _openChangePasswordDialog,
                        ),
                      ),
                    ],
                  ),
                ],
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
                _api.logout();
                context.go('/login');
              },
            ),
          ],
        ],
      );
    },
  );
}
