import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';

/// U1 – Đăng nhập bằng thông tin máy chủ; JWT chỉ được giữ trong bộ nhớ.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  static const _demoPassword = String.fromEnvironment('DEMO_PASSWORD');
  static const _demoAccounts = [
    (
      'User',
      'user1@sharegrid.vn',
      String.fromEnvironment('DEMO_USER_PASSWORD', defaultValue: _demoPassword),
    ),
    (
      'Host',
      'host1@sharegrid.vn',
      String.fromEnvironment('DEMO_HOST_PASSWORD', defaultValue: _demoPassword),
    ),
    (
      'Admin',
      'admin@sharegrid.vn',
      String.fromEnvironment(
        'DEMO_ADMIN_PASSWORD',
        defaultValue: _demoPassword,
      ),
    ),
  ];

  void _selectDemo(String email, String demoPassword) {
    if (_email.text != email) _password.clear();
    _email.text = email;
    setState(() => _error = null);
    if (demoPassword.isNotEmpty) {
      _password.text = demoPassword;
      _login();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Nhập email và mật khẩu để đăng nhập.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await (widget.client ?? apiClient).login(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      final next = Uri.tryParse(
        GoRouterState.of(context).uri.queryParameters['next'] ?? '',
      );
      final route = switch (user['role']?.toString().toUpperCase()) {
        'ADMIN' => '/admin/clusters',
        'HOST' => '/host/stations',
        'USER'
            when next != null &&
                !next.hasAuthority &&
                !next.hasScheme &&
                next.path == '/booking' =>
          next.toString(),
        _ => '/home',
      };
      context.go(route);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error) {
          ApiException(statusCode: 401) => 'Email hoặc mật khẩu không đúng.',
          ApiException() => error.userMessage,
          _ => 'Không thể đăng nhập tới máy chủ.',
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              24,
              56 + MediaQuery.paddingOf(context).top,
              24,
              36,
            ),
            decoration: const BoxDecoration(
              color: AppColors.sky200,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BrandMark(),
                const Gap(14),
                Text(
                  'Chào mừng đến\nEV ShareGrid',
                  style: AppFonts.display(
                    size: 32,
                    height: 1.18,
                    color: AppColors.skyInk,
                  ),
                ),
                const Gap(14),
                MutedText(
                  'Mạng lưới sạc xe điện của người Đà Nẵng',
                  size: 15,
                  color: AppColors.skyInk,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Label('Email'),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  style: AppFonts.body(size: 15, weight: FontWeight.w600),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  onSubmitted: (_) => _busy ? null : _login(),
                ),
                const Gap(14),
                const _Label('Mật khẩu'),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  style: AppFonts.body(size: 15, weight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      AppIcons.lock,
                      color: AppColors.muted,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _busy ? null : _login(),
                ),
                if (_error != null) ...[
                  const Gap(12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.redBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: AppFonts.body(size: 13, color: AppColors.red),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const Gap(12),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                const Gap(18),
                AppButton(
                  label: _busy ? 'Đang đăng nhập…' : 'Đăng nhập',
                  height: 54,
                  onPressed: _busy ? null : _login,
                ),
                const Gap(12),
                const MutedText(
                  'Đăng nhập kết nối máy chủ. Mã truy cập chỉ được giữ trong bộ nhớ phiên này.',
                  size: 12,
                ),
                const Gap(28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, email, password) in _demoAccounts)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _selectDemo(email, password),
                        child: Text(label),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: BoldText(text, size: 13),
  );
}
