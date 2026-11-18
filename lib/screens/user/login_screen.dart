import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/web_shell.dart';

/// U1 – Đăng nhập: SĐT/email + mật khẩu hoặc Google.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscure = true;

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
                const _Label('Số điện thoại hoặc email'),
                TextFormField(
                  initialValue: '905 123 456',
                  keyboardType: TextInputType.phone,
                  style: AppFonts.body(size: 15, weight: FontWeight.w600),
                  decoration: InputDecoration(
                    prefixIcon: Container(
                      width: 60,
                      margin: const EdgeInsets.only(right: 10),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: const BoldText('+84', size: 14),
                    ),
                  ),
                ),
                const Gap(14),
                const _Label('Mật khẩu'),
                TextFormField(
                  initialValue: 'matkhau123',
                  obscureText: _obscure,
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
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: LinkText('Quên mật khẩu?', onTap: () {}),
                  ),
                ),
                const Gap(14),
                AppButton(
                  label: 'Đăng nhập',
                  height: 54,
                  onPressed: () => context.go('/home'),
                ),
                const Gap(14),
                Row(
                  children: [
                    const Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: MutedText('hoặc'),
                    ),
                    const Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const Gap(14),
                AppButton(
                  label: 'Tiếp tục với Google',
                  kind: AppButtonKind.outline,
                  height: 54,
                  fontSize: 15,
                  icon: Icons.g_mobiledata_rounded,
                  onPressed: () => context.go('/home'),
                ),
                const Gap(28),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MutedText('Chưa có tài khoản? ', size: 14),
                    LinkText('Đăng ký', onTap: () => context.go('/garage')),
                  ],
                ),
                const Gap(12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    LinkText(
                      'Cổng chủ trạm',
                      size: 13,
                      color: AppColors.muted,
                      onTap: () => context.go('/host/stations'),
                    ),
                    MutedText('·'),
                    LinkText(
                      'Quản trị',
                      size: 13,
                      color: AppColors.muted,
                      onTap: () => context.go('/admin/clusters'),
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
