import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

/// U7 – Thông báo: lịch đổi version, bảo trì, xếp lịch, shortfall, phiên xong.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _filter = 0;
  bool _allRead = false;

  @override
  Widget build(BuildContext context) {
    final items = Mock.notifications.where((n) {
      return switch (_filter) {
        1 =>
          n.kind == NotifKind.scheduleChanged ||
              n.kind == NotifKind.maintenance,
        2 => n.kind == NotifKind.sessionDone || n.kind == NotifKind.scheduled,
        _ => true,
      };
    });
    return UserScaffold(
      tab: UserTab.bookings,
      gap: 12,
      children: [
        MobileHeader(
          title: 'Thông báo',
          onBack: () => context.go('/home'),
          trailing: LinkText(
            'Đọc hết',
            size: 13,
            onTap: () => setState(() => _allRead = true),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (i, l) in const [
                (0, 'Tất cả'),
                (1, 'Lịch thay đổi (2)'),
                (2, 'Phiên sạc'),
              ]) ...[
                FilterChipX(
                  l,
                  selected: _filter == i,
                  onTap: () => setState(() => _filter = i),
                ),
                const Gap(8),
              ],
            ],
          ),
        ),
        for (final n in items) _NotifCard(item: n, read: _allRead),
      ],
    );
  }
}

class _NotifCard extends StatelessWidget {
  const _NotifCard({required this.item, required this.read});
  final NotificationItem item;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = switch (item.kind) {
      NotifKind.scheduleChanged => (
        AppIcons.ai,
        AppColors.sky100,
        AppColors.blue,
      ),
      NotifKind.maintenance => (
        AppIcons.tool,
        AppColors.warningBg,
        AppColors.warning,
      ),
      NotifKind.scheduled => (
        AppIcons.check,
        AppColors.successBg,
        AppColors.success,
      ),
      NotifKind.shortfall => (AppIcons.warn, AppColors.redBg, AppColors.red),
      NotifKind.sessionDone => (AppIcons.battery, AppColors.bg, AppColors.ink),
    };
    final unread = item.unread && !read;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unread ? const Color(0xFFF6FBFE) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBox(icon, bg: bg, fg: fg, size: 40, iconSize: 20, radius: 12),
              const Gap(12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: unread ? 12 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BoldText(item.title, size: 14),
                      const Gap(4),
                      MutedText(item.body, color: AppColors.body),
                      const Gap(8),
                      Row(
                        children: [
                          if (item.action != null) ...[
                            LinkText(
                              item.action!,
                              size: 13,
                              onTap: () => context.go('/schedule'),
                            ),
                            MutedText(' · ', size: 12),
                          ],
                          MutedText(item.time, size: 12),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (unread)
            Positioned(
              right: 0,
              top: 4,
              child: Semantics(
                label: 'Chưa đọc',
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
