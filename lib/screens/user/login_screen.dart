import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';

/// U1 – Đăng nhập và đăng ký qua API.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.client});
  final ApiClient? client;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _confirmation = TextEditingController();
  bool _registering = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  static const _demoAccounts = [
    ('Tài xế', 'user1@sharegrid.vn'),
    ('Chủ trạm', 'host1@sharegrid.vn'),
    ('Quản trị', 'admin@sharegrid.vn'),
  ];

  void _selectDemo(String email) {
    _password.clear();
    _email.text = email;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _name.dispose();
    _confirmation.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_registering &&
        (_name.text.trim().isEmpty || _name.text.trim().runes.length > 100)) {
      return 'Họ tên cần từ 1 đến 100 ký tự.';
    }
    final email = _email.text.trim();
    if (email.runes.length > 100 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Địa chỉ email không hợp lệ.';
    }
    if (_registering &&
        (_password.text.runes.length < 8 ||
            _password.text.runes.length > 128)) {
      return 'Mật khẩu cần từ 8 đến 128 ký tự.';
    }
    if (_registering && _password.text != _confirmation.text) {
      return 'Hai mật khẩu chưa khớp.';
    }
    return _password.text.isEmpty ? 'Vui lòng nhập mật khẩu.' : null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.client ?? apiClient;
      if (_registering) {
        await api.register(
          fullName: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
        );
      } else {
        await api.login(email: _email.text.trim(), password: _password.text);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(Object error) {
    final profile = error is ProfileLoadException;
    final cause = error is ProfileLoadException ? error.cause : error;
    final message = switch (cause) {
      ApiException(statusCode: 401) when !profile && !_registering =>
        'Email hoặc mật khẩu không đúng.',
      ApiException(statusCode: 409 || 422 || 429) when !profile =>
        cause.message,
      ApiException(:final statusCode) => 'Máy chủ trả lỗi HTTP $statusCode.',
      TimeoutException() => 'Máy chủ phản hồi quá lâu. Vui lòng thử lại.',
      http.ClientException() =>
        'Không thể kết nối máy chủ. Hãy kiểm tra kết nối và thử lại.',
      FormatException() => 'Máy chủ trả dữ liệu không hợp lệ.',
      _ => 'Chưa thể hoàn tất thao tác. Vui lòng thử lại.',
    };
    if (!profile) return message;
    final action = _registering ? 'Đã tạo tài khoản' : 'Đã xác thực';
    return '$action nhưng chưa tải được hồ sơ. $message';
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
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Đăng nhập')),
                    ButtonSegment(value: true, label: Text('Đăng ký')),
                  ],
                  selected: {_registering},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) => setState(() {
                          _registering = selection.single;
                          _error = null;
                          _password.clear();
                          _confirmation.clear();
                        }),
                ),
                const Gap(18),
                if ((widget.client ?? apiClient).sessionExpired) ...[
                  const Text('Phiên đăng nhập đã hết hạn'),
                  const Gap(12),
                ],
                if (_registering) ...[
                  const _Label('Họ tên'),
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    keyboardType: TextInputType.name,
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.next,
                  ),
                  const Gap(14),
                ],
                const _Label('Email'),
                TextField(
                  key: const ValueKey('auth-email'),
                  enabled: !_busy,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  style: AppFonts.body(size: 15, weight: FontWeight.w600),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const Gap(14),
                const _Label('Mật khẩu'),
                TextField(
                  key: const ValueKey('auth-password'),
                  enabled: !_busy,
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: [
                    _registering
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
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
                  onSubmitted: _registering ? null : (_) => _submit(),
                ),
                if (_registering) ...[
                  const Gap(14),
                  const _Label('Nhập lại mật khẩu'),
                  TextField(
                    controller: _confirmation,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _submit(),
                  ),
                ],
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
                  label: _busy
                      ? 'Đang gửi…'
                      : (_registering ? 'Tạo tài khoản' : 'Vào ứng dụng'),
                  height: 54,
                  onPressed: _busy ? null : _submit,
                ),
                const Gap(12),
                const MutedText(
                  'Phiên đăng nhập được khôi phục khi tải lại trang.',
                  size: 12,
                ),
                if (!_registering) ...[
                  const Gap(20),
                  const _Label('Đăng nhập nhanh (Demo)'),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, email) in _demoAccounts)
                        OutlinedButton(
                          onPressed: _busy ? null : () => _selectDemo(email),
                          child: Text(label),
                        ),
                    ],
                  ),
                ],
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
