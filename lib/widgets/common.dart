import 'package:flutter/material.dart';

import '../theme.dart';

/// Nút chính / viền / chữ dùng chung toàn app.
enum AppButtonKind { primary, outline, soft, ghost, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.kind = AppButtonKind.primary,
    this.height = 52,
    this.expand = true,
    this.radius = 14,
    this.fontSize = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final AppButtonKind kind;
  final double height;
  final bool expand;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      AppButtonKind.primary => (AppColors.blue, Colors.white, null),
      AppButtonKind.outline => (
        Colors.white,
        AppColors.ink,
        const BorderSide(color: AppColors.border, width: 1.5),
      ),
      AppButtonKind.soft => (AppColors.sky200, AppColors.skyInk, null),
      AppButtonKind.ghost => (Colors.transparent, AppColors.blue, null),
      AppButtonKind.danger => (
        Colors.white,
        AppColors.red,
        const BorderSide(color: AppColors.red, width: 1.5),
      ),
    };
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: 19, color: fg), const Gap(8)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.body(
              size: fontSize,
              weight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
        if (trailingIcon != null) ...[
          const Gap(8),
          Icon(trailingIcon, size: 19, color: fg),
        ],
      ],
    );
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: border ?? BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed ?? () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Khoảng cách gọn.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// Nhãn nhỏ bo tròn.
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.bg = AppColors.sky100,
    this.fg = AppColors.skyInk,
    this.icon,
    this.radius = 999,
    this.size = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  factory Pill.success(String t, {IconData? icon}) =>
      Pill(t, bg: AppColors.successBg, fg: AppColors.success, icon: icon);
  factory Pill.warning(String t, {IconData? icon}) =>
      Pill(t, bg: AppColors.warningBg, fg: AppColors.warning, icon: icon);
  factory Pill.danger(String t, {IconData? icon}) =>
      Pill(t, bg: AppColors.redBg, fg: AppColors.red, icon: icon);
  factory Pill.neutral(String t, {IconData? icon}) =>
      Pill(t, bg: AppColors.bg, fg: AppColors.muted, icon: icon);
  factory Pill.sky(String t, {IconData? icon}) =>
      Pill(t, bg: AppColors.sky200, fg: AppColors.skyInk, icon: icon);
  factory Pill.blue(String t, {IconData? icon}) =>
      Pill(t, bg: AppColors.blue, fg: Colors.white, icon: icon);

  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final double radius;
  final double size;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size + 2, color: fg),
            const Gap(4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.body(
                size: size,
                weight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nhãn bắt buộc cho số liệu không đo thật.
class SimTag extends StatelessWidget {
  const SimTag({super.key, this.text = 'Mô phỏng'});
  final String text;
  @override
  Widget build(BuildContext context) => Pill(
    text,
    bg: AppColors.warningBg,
    fg: AppColors.warning,
    radius: 6,
    size: 11,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  );
}

/// Thẻ nền trắng viền mảnh.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = Colors.white,
    this.borderColor = AppColors.border,
    this.radius = 18,
    this.onTap,
    this.width,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: borderColor == null
          ? BorderSide.none
          : BorderSide(color: borderColor!),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Tiêu đề mục + liên kết bên phải.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppFonts.display(size: 19))),
        if (action != null) LinkText(action!, onTap: onAction),
      ],
    );
  }
}

class LinkText extends StatelessWidget {
  const LinkText(
    this.text, {
    super.key,
    this.onTap,
    this.size = 14,
    this.color = AppColors.blue,
  });
  final String text;
  final VoidCallback? onTap;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          text,
          style: AppFonts.body(
            size: size,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Chữ phụ màu xám.
class MutedText extends StatelessWidget {
  const MutedText(
    this.text, {
    super.key,
    this.size = 13,
    this.color = AppColors.muted,
    this.weight = FontWeight.w400,
    this.align,
    this.maxLines,
  });
  final String text;
  final double size;
  final Color color;
  final FontWeight weight;
  final TextAlign? align;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: AppFonts.body(size: size, color: color, weight: weight, height: 1.4),
  );
}

class BoldText extends StatelessWidget {
  const BoldText(
    this.text, {
    super.key,
    this.size = 15,
    this.color = AppColors.ink,
    this.maxLines,
  });
  final String text;
  final double size;
  final Color color;
  final int? maxLines;
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: AppFonts.body(size: size, weight: FontWeight.w700, color: color),
  );
}

/// Ô KPI: nhãn, giá trị lớn, ghi chú.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.note,
    this.noteColor = AppColors.muted,
    this.tag,
    this.accent = false,
  });

  final String label;
  final String value;
  final String? unit;
  final String? note;
  final Color noteColor;
  final Widget? tag;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? AppColors.skyInk : AppColors.ink;
    return AppCard(
      color: accent ? AppColors.sky200 : Colors.white,
      borderColor: accent ? null : AppColors.border,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: MutedText(
                  label,
                  size: 13,
                  color: accent ? AppColors.skyInk : AppColors.muted,
                  weight: FontWeight.w600,
                ),
              ),
              ?tag,
            ],
          ),
          const Gap(6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppFonts.numbers(size: 26, color: fg),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: AppFonts.body(
                      size: 13,
                      weight: FontWeight.w600,
                      color: accent ? AppColors.skyInk : AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (note != null) ...[
            const Gap(4),
            MutedText(
              note!,
              size: 12,
              color: accent ? AppColors.skyInk : noteColor,
            ),
          ],
        ],
      ),
    );
  }
}

/// Dòng nhãn – giá trị.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.valueColor = AppColors.ink,
    this.bold = true,
    this.size = 14,
  });
  final String label;
  final String value;
  final Color valueColor;
  final bool bold;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: MutedText(label, size: size)),
          const Gap(12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppFonts.body(
                size: size,
                weight: bold ? FontWeight.w700 : FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Thanh tiến trình bo tròn.
class ProgressBar extends StatelessWidget {
  const ProgressBar(
    this.value, {
    super.key,
    this.height = 8,
    this.color = AppColors.blue,
    this.track = AppColors.sky100,
  });
  final double value;
  final double height;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: track)),
            FractionallySizedBox(
              widthFactor: value.clamp(0, 1).toDouble(),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ô icon vuông bo tròn.
class IconBox extends StatelessWidget {
  const IconBox(
    this.icon, {
    super.key,
    this.bg = AppColors.sky100,
    this.fg = AppColors.blue,
    this.size = 44,
    this.iconSize = 22,
    this.radius = 14,
  });
  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: iconSize, color: fg),
  );
}

/// Nút icon tròn có viền (thông báo, quay lại…).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton(
    this.icon, {
    super.key,
    this.onTap,
    this.badge = false,
    this.size = 44,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 22, color: AppColors.ink),
                if (badge)
                  Positioned(
                    top: size * .2,
                    right: size * .22,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
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

/// Đầu trang con trong app USER: nút quay lại + tiêu đề + phần phải.
class MobileHeader extends StatelessWidget {
  const MobileHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          CircleIconButton(
            Icons.arrow_back_rounded,
            onTap: onBack,
            size: 40,
            tooltip: 'Quay lại',
          ),
          const Gap(12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppFonts.display(size: 22)),
              if (subtitle != null) MutedText(subtitle!, size: 13),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Chip lọc (đang chọn = Sky 200).
class FilterChipX extends StatelessWidget {
  const FilterChipX(
    this.label, {
    super.key,
    this.selected = false,
    this.icon,
    this.onTap,
  });
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.skyInk : AppColors.ink;
    return Material(
      color: selected ? AppColors.sky200 : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.sky200 : AppColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const Gap(5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.body(
                    size: 13,
                    weight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bộ chọn phân đoạn (tab con).
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.items,
    required this.selected,
    this.onChanged,
  });
  final List<String> items;
  final int selected;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged?.call(i),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x140B1B3F),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    items[i],
                    style: AppFonts.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: i == selected ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hộp giải thích của bộ lập lịch (trỏ tới dữ liệu cụ thể).
class ExplainBox extends StatelessWidget {
  const ExplainBox({super.key, required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.sky100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.ai, size: 18, color: AppColors.blue),
              const Gap(8),
              Expanded(
                child: BoldText(title, size: 14, color: AppColors.skyInk),
              ),
            ],
          ),
          const Gap(8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: 8),
                    child: CircleAvatar(
                      radius: 2.5,
                      backgroundColor: AppColors.skyInk,
                    ),
                  ),
                  Expanded(
                    child: MutedText(l, size: 13, color: AppColors.skyInk),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Chú thích màu cho biểu đồ.
class LegendDot extends StatelessWidget {
  const LegendDot(
    this.color,
    this.label, {
    super.key,
    this.dashed = false,
    this.square = true,
  });
  final Color color;
  final String label;
  final bool dashed;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dashed
            ? SizedBox(
                width: 16,
                height: 3,
                child: Row(
                  children: [
                    Expanded(child: ColoredBox(color: color)),
                    const SizedBox(width: 3),
                    Expanded(child: ColoredBox(color: color)),
                  ],
                ),
              )
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(square ? 3 : 5),
                ),
              ),
        const Gap(5),
        MutedText(label, size: 11),
      ],
    );
  }
}

/// Bảng đơn giản cho web HOST/ADMIN.
class SimpleTable extends StatelessWidget {
  const SimpleTable({
    super.key,
    required this.columns,
    required this.rows,
    this.flex,
  });
  final List<String> columns;
  final List<List<Widget>> rows;
  final List<int>? flex;

  @override
  Widget build(BuildContext context) {
    int f(int i) => flex == null ? 1 : flex![i];
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                Expanded(
                  flex: f(i),
                  child: Text(
                    columns[i].toUpperCase(),
                    style: AppFonts.body(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                for (var i = 0; i < r.length; i++)
                  Expanded(
                    flex: f(i),
                    child: Align(alignment: Alignment.centerLeft, child: r[i]),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ô chữ bảng.
Widget cellText(
  String t, {
  bool bold = false,
  Color color = AppColors.ink,
  double size = 13,
}) => Text(
  t,
  style: AppFonts.body(
    size: size,
    weight: bold ? FontWeight.w700 : FontWeight.w500,
    color: color,
  ),
);

/// Bộ icon thống nhất (Material Symbols bo tròn). "Sạc thông minh" = chip AI.
class AppIcons {
  AppIcons._();
  static const ai = Icons.memory_rounded;
  static const home = Icons.home_rounded;
  static const homeOutline = Icons.home_outlined;
  static const map = Icons.map_outlined;
  static const mapFilled = Icons.map_rounded;
  static const bookings = Icons.event_note_outlined;
  static const bookingsFilled = Icons.event_note_rounded;
  static const profile = Icons.person_outline_rounded;
  static const profileFilled = Icons.person_rounded;
  static const bell = Icons.notifications_none_rounded;
  static const bolt = Icons.bolt_rounded;
  static const station = Icons.ev_station_rounded;
  static const car = Icons.directions_car_filled_rounded;
  static const moto = Icons.electric_moped_rounded;
  static const pin = Icons.location_on_outlined;
  static const clock = Icons.schedule_rounded;
  static const calendar = Icons.calendar_month_rounded;
  static const plug = Icons.electrical_services_rounded;
  static const money = Icons.payments_outlined;
  static const warn = Icons.warning_amber_rounded;
  static const check = Icons.check_circle_rounded;
  static const lock = Icons.lock_outline_rounded;
  static const tool = Icons.build_outlined;
  static const chart = Icons.insights_rounded;
  static const search = Icons.search_rounded;
  static const filter = Icons.tune_rounded;
  static const garage = Icons.garage_outlined;
  static const star = Icons.star_rounded;
  static const route = Icons.directions_rounded;
  static const battery = Icons.battery_charging_full_rounded;
}
