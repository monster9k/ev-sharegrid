import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/common.dart';

/// Ô ghi chú xanh nhạt dùng chung cho trang quản trị.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key, this.warn = false});
  final String text;
  final bool warn;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: (warn ? AppColors.warningBg : AppColors.sky100).withValues(
        alpha: .85,
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: AppFonts.body(
        size: 12,
        color: warn ? const Color(0xFF7A3E06) : AppColors.blue800,
        height: 1.5,
      ),
    ),
  );
}

enum CheckState { ok, warn, fail }

/// Dòng kiểm tra có biểu tượng ✓ / ! / ✗.
class CheckLine extends StatelessWidget {
  const CheckLine(this.state, this.title, this.body, {super.key});
  final CheckState state;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, t) = switch (state) {
      CheckState.ok => (AppColors.successBg, AppColors.success, '✓'),
      CheckState.warn => (AppColors.warningBg, AppColors.warning, '!'),
      CheckState.fail => (AppColors.redBg, AppColors.red, '✗'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text(
              t,
              style: AppFonts.body(
                size: 12,
                weight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
          const Gap(10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppFonts.body(
                  size: 13,
                  color: AppColors.body,
                  height: 1.45,
                ),
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
      ),
    );
  }
}

/// Nút nhỏ bo tròn cho trang web.
class WebBtn extends StatelessWidget {
  const WebBtn(
    this.label, {
    super.key,
    this.primary = false,
    this.icon,
    this.color,
    this.onTap,
  });
  final String label;
  final bool primary;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return AppButton(
        label: label,
        icon: icon,
        expand: false,
        height: 42,
        radius: 999,
        fontSize: 14,
        onPressed: onTap,
      );
    }
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon == null ? null : Icon(icon, size: 18),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: .65),
          foregroundColor: color ?? AppColors.ink,
          side: BorderSide(color: Colors.white.withValues(alpha: .9)),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        label: Text(
          label,
          style: AppFonts.body(
            size: 14,
            weight: FontWeight.w700,
            color: color ?? AppColors.ink,
          ),
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
