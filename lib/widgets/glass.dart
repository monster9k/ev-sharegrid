import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'common.dart';

/// Lớp kính mờ (liquid glass): nền trắng 62%, blur 22, viền trắng, highlight.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 999,
    this.padding = EdgeInsets.zero,
    this.opacity = .62,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0B1B3F),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: r,
              color: Colors.white.withValues(alpha: opacity),
              border: Border.all(color: Colors.white.withValues(alpha: .75)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: opacity + .12),
                  Colors.white.withValues(alpha: opacity),
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Các tab chính của app USER.
enum UserTab { home, map, smart, bookings, profile }

/// Thanh tab nổi bo tròn kiểu liquid glass, 5 tab, badge ở "Lịch đặt".
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.current, this.badge = 1});
  final UserTab? current;
  final int badge;

  static const _items = [
    (UserTab.home, AppIcons.homeOutline, AppIcons.home, 'Trang chủ', '/home'),
    (UserTab.map, AppIcons.map, AppIcons.mapFilled, 'Bản đồ', '/map'),
    (UserTab.smart, AppIcons.ai, AppIcons.ai, 'Thông minh', '/schedule'),
    (
      UserTab.bookings,
      AppIcons.bookings,
      AppIcons.bookingsFilled,
      'Lịch đặt',
      '/sessions',
    ),
    (
      UserTab.profile,
      AppIcons.profile,
      AppIcons.profileFilled,
      'Cá nhân',
      '/profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            for (final (tab, icon, iconOn, label, route) in _items)
              Expanded(
                child: Semantics(
                  label: label,
                  selected: tab == current,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => context.go(route),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: tab == current
                            ? AppColors.sky200
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            tab == current ? iconOn : icon,
                            size: 26,
                            color: tab == current
                                ? AppColors.blue
                                : AppColors.ink,
                          ),
                          if (tab == UserTab.bookings && badge > 0)
                            Positioned(
                              top: 1,
                              left: 0,
                              right: 0,
                              child: Transform.translate(
                                offset: const Offset(13, 0),
                                child: Center(
                                  child: Container(
                                    height: 20,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.red,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                    child: Text(
                                      '$badge',
                                      style: AppFonts.body(
                                        size: 10,
                                        weight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Thanh hành động đáy dạng kính (nút chính nổi).
class GlassActionBar extends StatelessWidget {
  const GlassActionBar({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 26,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Gap(8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Khung một màn app USER: nội dung cuộn + thanh tab nổi (hoặc thanh hành động).
class UserScaffold extends StatelessWidget {
  const UserScaffold({
    super.key,
    required this.children,
    this.tab,
    this.actionBar,
    this.showNav = true,
    this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 0),
    this.background = Colors.white,
    this.gap = 16,
  });

  final List<Widget> children;
  final UserTab? tab;
  final Widget? actionBar;
  final bool showNav;
  final EdgeInsets padding;
  final Color background;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final bottomSpace = (showNav || actionBar != null) ? 104.0 : 24.0;
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListView(
                padding: padding.copyWith(bottom: bottomSpace),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SimTag(text: 'Dữ liệu mô phỏng'),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) SizedBox(height: gap),
                    children[i],
                  ],
                ],
              ),
            ),
            if (actionBar != null || showNav)
              Positioned(
                left: 12,
                right: 12,
                bottom: 14 + MediaQuery.paddingOf(context).bottom,
                child: actionBar ?? GlassNavBar(current: tab),
              ),
          ],
        ),
      ),
    );
  }
}
