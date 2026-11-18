import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// Cá nhân: hồ sơ, thống kê, xe, cài đặt, vào cổng chủ trạm / quản trị.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return UserScaffold(
      tab: UserTab.profile,
      gap: 14,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppColors.blue,
              child: Text(
                'NA',
                style: AppFonts.body(
                  size: 22,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nguyễn Văn An', style: AppFonts.display(size: 22)),
                  MutedText('Hải Châu, Đà Nẵng · thành viên từ 2026'),
                ],
              ),
            ),
            const CircleIconButton(Icons.edit_outlined, tooltip: 'Sửa hồ sơ'),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.sky200,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              for (final (l, v) in const [
                ('Phiên sạc', '24'),
                ('Đã tiết kiệm', '186k đ'),
                ('Đủ pin đúng hạn', '96%'),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MutedText(l, size: 12, color: AppColors.skyInk),
                      Text(
                        v,
                        style: AppFonts.numbers(
                          size: 20,
                          color: AppColors.skyInk,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionHeader(
          'Xe của tôi',
          action: 'Quản lý xe',
          onAction: () => context.go('/garage'),
        ),
        for (final v in Mock.vehicles)
          AppCard(
            onTap: () => context.go('/garage'),
            child: Row(
              children: [
                IconBox(
                  v.model.type == 'CAR' ? AppIcons.car : AppIcons.moto,
                  radius: 12,
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BoldText('${v.nickname} · ${v.plate}', maxLines: 1),
                      MutedText(
                        '${v.model.brand} ${v.model.name} · ${v.model.connector} · ${vnDec(v.model.batteryKwh, 1)} kWh${v.isDefault ? ' · mặc định' : ''}',
                        size: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _Row(
                Icons.storefront_outlined,
                'Chế độ chủ trạm',
                trailing: const Pill(
                  'Mới',
                  bg: AppColors.sky100,
                  fg: AppColors.blue,
                  radius: 6,
                ),
                onTap: () => context.go('/host/stations'),
              ),
              _Row(
                Icons.admin_panel_settings_outlined,
                'Bảng quản trị (ADMIN)',
                onTap: () => context.go('/admin/clusters'),
              ),
              _Row(AppIcons.money, 'Thanh toán'),
              _Row(
                AppIcons.bell,
                'Thông báo',
                onTap: () => context.go('/notifications'),
              ),
              _Row(
                Icons.health_and_safety_outlined,
                'An toàn khi sạc',
                value: 'Bật',
              ),
              _Row(
                Icons.language_rounded,
                'Ngôn ngữ',
                value: 'Tiếng Việt',
                last: true,
              ),
            ],
          ),
        ),
        AppButton(
          label: 'Đăng xuất',
          kind: AppButtonKind.outline,
          icon: Icons.logout_rounded,
          fontSize: 15,
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
    this.icon,
    this.title, {
    this.value,
    this.trailing,
    this.onTap,
    this.last = false,
  });
  final IconData icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap ?? () {},
    child: Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.blue),
          const Gap(14),
          Expanded(
            child: Text(
              title,
              style: AppFonts.body(size: 15, weight: FontWeight.w600),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (value != null)
            MutedText(value!)
          else
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    ),
  );
}
