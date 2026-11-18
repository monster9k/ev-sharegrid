import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme.dart';
import 'common.dart';

enum Portal { host, admin }

class _NavItem {
  const _NavItem(this.route, this.icon, this.label, {this.badge});
  final String route;
  final IconData icon;
  final String label;
  final int? badge;
}

const _hostItems = [
  _NavItem('/host/stations', AppIcons.station, 'Trạm của tôi'),
  _NavItem('/host/ports', AppIcons.tool, 'Cổng sạc & bảo trì'),
  _NavItem('/host/schedule', AppIcons.calendar, 'Lịch đặt & doanh thu'),
];

const _adminItems = [
  _NavItem('/admin/clusters', Icons.hub_outlined, 'Cụm điều phối'),
  _NavItem('/admin/review', Icons.fact_check_outlined, 'Duyệt trạm', badge: 1),
  _NavItem('/admin/tariff', AppIcons.money, 'Biểu giá điện'),
  _NavItem('/admin/solver', Icons.monitor_heart_outlined, 'Giám sát solver'),
  _NavItem('/admin/benchmark', Icons.science_outlined, 'Mô phỏng & Benchmark'),
  _NavItem('/admin/forecast', AppIcons.chart, 'Dự báo & Audit'),
];

/// Khung web cho cổng HOST và ADMIN: sidebar sáng (kính), mục chọn Sky 200,
/// nền #F7FBFD có đốm Sky mờ. Màn hẹp (< 960) chuyển sidebar thành drawer.
class WebShell extends StatelessWidget {
  const WebShell({
    super.key,
    required this.portal,
    required this.route,
    required this.eyebrow,
    required this.title,
    required this.children,
    this.actions = const [],
  });

  final Portal portal;
  final String route;
  final String eyebrow;
  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final sidebar = _Sidebar(portal: portal, route: route);
    final content = ListView(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 28, wide ? 32 : 16, 40),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MutedText(eyebrow, weight: FontWeight.w600),
                const Gap(4),
                Text(title, style: AppFonts.display(size: wide ? 30 : 24)),
              ],
            ),
            if (actions.isNotEmpty)
              Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ),
        for (final c in children) ...[const Gap(20), c],
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.webBg,
      drawer: wide ? null : Drawer(width: 280, child: sidebar),
      appBar: wide
          ? null
          : AppBar(
              backgroundColor: Colors.white.withValues(alpha: .85),
              surfaceTintColor: Colors.transparent,
              title: Text(
                portal == Portal.host ? 'Cổng chủ trạm' : 'Quản trị',
                style: AppFonts.display(size: 17),
              ),
            ),
      body: Stack(
        children: [
          const _Blobs(),
          Row(
            children: [
              if (wide) SizedBox(width: 260, child: sidebar),
              Expanded(child: content),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.portal, required this.route});
  final Portal portal;
  final String route;

  @override
  Widget build(BuildContext context) {
    final items = portal == Portal.host ? _hostItems : _adminItems;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .78),
            border: const Border(right: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 20),
                  child: Row(
                    children: [
                      const BrandMark(size: 38),
                      const Gap(10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EV ShareGrid',
                            style: AppFonts.display(size: 17),
                          ),
                          MutedText(
                            portal == Portal.host
                                ? 'Cổng chủ trạm (HOST)'
                                : 'Bảng quản trị (ADMIN)',
                            size: 11,
                            weight: FontWeight.w600,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                for (final it in items) ...[
                  _SideLink(item: it, selected: it.route == route),
                  const Gap(6),
                ],
                const Spacer(),
                const Divider(color: AppColors.border, height: 1),
                const Gap(14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor: AppColors.blue,
                        child: Text(
                          portal == Portal.host ? 'CT' : 'QT',
                          style: AppFonts.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BoldText(
                              portal == Portal.host
                                  ? 'Nguyễn Văn Chủ Trạm'
                                  : 'Quản trị viên',
                              size: 13,
                            ),
                            MutedText(
                              portal == Portal.host
                                  ? 'HOST · host1@sharegrid.vn'
                                  : 'ADMIN · admin@sharegrid.vn',
                              size: 11,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(10),
                TextButton.icon(
                  onPressed: () => context.go('/home'),
                  icon: const Icon(Icons.phone_iphone_rounded, size: 18),
                  label: const Text('Mở app người dùng'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideLink extends StatelessWidget {
  const _SideLink({required this.item, required this.selected});
  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.skyInk : AppColors.body;
    return Material(
      color: selected ? AppColors.sky200 : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
            Navigator.of(context).pop();
          }
          context.go(item.route);
        },
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: fg),
                const Gap(12),
                Expanded(
                  child: Text(
                    item.label,
                    style: AppFonts.body(
                      size: 14,
                      weight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
                if (item.badge != null)
                  Pill(
                    '${item.badge}',
                    bg: AppColors.red,
                    fg: Colors.white,
                    size: 11,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Blobs extends StatelessWidget {
  const _Blobs();
  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
          child: Stack(
            children: [
              Positioned(
                left: MediaQuery.sizeOf(context).width * .22,
                top: -220,
                child: _circle(640),
              ),
              Positioned(right: -120, top: 520, child: _circle(520)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circle(double s) => Container(
    width: s,
    height: s,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AppColors.sky200.withValues(alpha: .75),
    ),
  );
}

/// Logo: ô vuông xanh, tia sét trắng, chấm đỏ.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(size * .29),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(AppIcons.bolt, color: Colors.white, size: size * .6),
          Positioned(
            right: size * .14,
            top: size * .14,
            child: Container(
              width: size * .15,
              height: size * .15,
              decoration: const BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thẻ kính cho trang web (card .62 + blur).
class WebCard extends StatelessWidget {
  const WebCard({
    super.key,
    required this.children,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    this.gap = 14,
  });
  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B1B3F),
            blurRadius: 36,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: .85)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(title!, style: AppFonts.display(size: 19)),
                      ),
                      ?trailing,
                    ],
                  ),
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0 || title != null) SizedBox(height: gap),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ô KPI dạng kính cho web.
class WebKpi extends StatelessWidget {
  const WebKpi(this.label, this.value, {super.key, this.note, this.noteColor});
  final String label;
  final String value;
  final String? note;
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    return WebCard(
      padding: const EdgeInsets.all(16),
      gap: 4,
      children: [
        MutedText(label, size: 12, weight: FontWeight.w600),
        Text(value, style: AppFonts.numbers(size: 26)),
        if (note != null)
          MutedText(
            note!,
            size: 12,
            weight: FontWeight.w600,
            color: noteColor ?? AppColors.muted,
          ),
      ],
    );
  }
}

/// Lưới tự co giãn: mỗi ô tối thiểu [minWidth].
class AutoGrid extends StatelessWidget {
  const AutoGrid({
    super.key,
    required this.children,
    this.minWidth = 180,
    this.gap = 12,
  });
  final List<Widget> children;
  final double minWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = ((c.maxWidth + gap) / (minWidth + gap)).floor().clamp(
          1,
          children.length,
        );
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final ch in children) SizedBox(width: w, child: ch)],
        );
      },
    );
  }
}

/// Ô nhập kiểu form web (nhãn + giá trị).
class WebField extends StatelessWidget {
  const WebField(this.label, this.value, {super.key, this.suffix});
  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(label, size: 12, weight: FontWeight.w700),
        const Gap(6),
        TextFormField(
          initialValue: value,
          style: AppFonts.body(size: 14, weight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            suffixText: suffix,
            fillColor: Colors.white.withValues(alpha: .8),
          ),
        ),
      ],
    );
  }
}
