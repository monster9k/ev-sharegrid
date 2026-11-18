import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../widgets/common.dart';

/// 3 màn onboarding (U0): tìm trạm · sạc đúng giờ · chia sẻ trụ sạc.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.step});

  /// 1, 2 hoặc 3.
  final int step;

  static const _titles = [
    'Tìm trạm sạc khắp Đà Nẵng',
    'Sạc đúng giờ, trả ít tiền hơn',
    'Chia sẻ trụ sạc, cùng giảm tải lưới điện',
  ];
  static const _bodies = [
    'Trạm công cộng và điểm sạc chia sẻ của người dân trên cùng một bản đồ, xem cổng trống, công suất và giá trước khi đi.',
    'Cho biết pin hiện tại và giờ cần xe. Hệ thống xếp lịch vào khung giờ giá thấp, không vượt trần công suất trạm, và xe vẫn đủ pin trước giờ lấy.',
    'Có trụ sạc ở nhà hoặc cửa hàng? Mở cho cộng đồng vào giờ rảnh, tự đặt giá và nhận thêm thu nhập.',
  ];

  @override
  Widget build(BuildContext context) {
    final i = step - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, c) {
          final heroH = math.min(480.0, c.maxHeight * .55);
          return Column(
            children: [
              SizedBox(
                height: heroH,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.sky200,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(36),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: switch (step) {
                          1 => const _MapHero(),
                          2 => const _PriceHero(),
                          _ => const _ShareHero(),
                        },
                      ),
                      if (step < 3)
                        Positioned(
                          right: 12,
                          top: 16 + MediaQuery.paddingOf(context).top,
                          child: TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(
                              'Bỏ qua',
                              style: AppFonts.body(
                                size: 14,
                                weight: FontWeight.w700,
                                color: AppColors.skyInk,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Dots(index: i),
                        const Gap(14),
                        Text(
                          _titles[i],
                          style: AppFonts.display(size: 30, height: 1.2),
                        ),
                        const Gap(14),
                        Flexible(
                          child: SingleChildScrollView(
                            child: MutedText(_bodies[i], size: 15),
                          ),
                        ),
                        const Spacer(),
                        AppButton(
                          label: step == 3 ? 'Bắt đầu' : 'Tiếp tục',
                          trailingIcon: step == 3
                              ? null
                              : Icons.arrow_forward_rounded,
                          onPressed: () => context.go(
                            step == 3 ? '/login' : '/onboarding/${step + 1}',
                          ),
                        ),
                        if (step == 3) ...[
                          const Gap(8),
                          Center(
                            child: LinkText(
                              'Tôi đã có tài khoản',
                              onTap: () => context.go('/login'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 3; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 6),
          width: i == index ? 24 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == index ? AppColors.blue : AppColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
    ],
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.dot, this.selected = false});
  final String text;
  final Color? dot;
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: selected ? AppColors.blue : Colors.white,
      borderRadius: BorderRadius.circular(999),
      boxShadow: const [
        BoxShadow(
          color: Color(0x290B3550),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected)
          const Icon(AppIcons.bolt, size: 14, color: Colors.white)
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        const Gap(5),
        Text(
          text,
          style: AppFonts.body(
            size: 12,
            weight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

/// Hero 1: bản đồ thu nhỏ có sông Hàn, biển và các ghim trạm.
class _MapHero extends StatelessWidget {
  const _MapHero();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final sx = c.maxWidth / 390, sy = c.maxHeight / 480;
        Widget at(double x, double y, Widget w) =>
            Positioned(left: x * sx, top: y * sy, child: w);
        return Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _MiniMapPainter())),
            at(44, 150, const _Tag('11 kW', dot: AppColors.success)),
            at(150, 228, const _Tag('60 kW · 2 trống', selected: true)),
            at(60, 330, const _Tag('Xe máy', dot: AppColors.success)),
            at(236, 120, const _Tag('Hết cổng', dot: AppColors.red)),
            at(300, 300, const _MapLabel('BIỂN MỸ KHÊ')),
            at(150, 400, const _MapLabel('SÔNG HÀN')),
          ],
        );
      },
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppFonts.body(
      size: 11,
      weight: FontWeight.w600,
      color: const Color(0xFF1A5A80),
    ).copyWith(letterSpacing: 1),
  );
}

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 390, sy = size.height / 480;
    canvas.scale(sx, sy);
    final road = Paint()
      ..color = Colors.white.withValues(alpha: .7)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(390, 70)
        ..cubicTo(330, 140, 330, 360, 390, 470)
        ..lineTo(390, 70),
      Paint()..color = const Color(0xFFA6D9EE),
    );
    canvas.drawPath(
      Path()
        ..moveTo(190, 0)
        ..cubicTo(170, 120, 230, 260, 190, 480),
      Paint()
        ..color = const Color(0xFFA6D9EE)
        ..strokeWidth = 34
        ..style = PaintingStyle.stroke,
    );
    for (final y in [110.0, 210.0, 300.0, 390.0]) {
      canvas.drawLine(Offset(0, y), Offset(330, y + 10), road);
    }
    canvas.drawLine(const Offset(100, 0), const Offset(120, 480), road);
    canvas.drawLine(const Offset(280, 0), const Offset(270, 480), road);
  }

  @override
  bool shouldRepaint(_MiniMapPainter old) => false;
}

/// Hero 2: thẻ "Giờ sạc tốt hôm nay".
class _PriceHero extends StatelessWidget {
  const _PriceHero();
  static const _bars = [
    Color(0xFFBFD0F7),
    Color(0xFFBFD0F7),
    AppColors.sky100,
    AppColors.sky100,
    Color(0xFFBFD0F7),
    Color(0xFF8AA9EE),
    Color(0xFF4F79DE),
    AppColors.blue,
    AppColors.blue,
    Color(0xFF4F79DE),
    Color(0xFF8AA9EE),
    AppColors.sky100,
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          right: 46,
          top: 78,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: .8),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Container(
          width: 310,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x290B3550),
                blurRadius: 40,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: BoldText('Giờ sạc tốt hôm nay', size: 14),
                  ),
                  Pill(
                    'AI',
                    bg: AppColors.sky100,
                    fg: AppColors.blue,
                    radius: 6,
                    size: 11,
                    icon: AppIcons.ai,
                  ),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  for (var i = 0; i < _bars.length; i++) ...[
                    if (i > 0) const Gap(2),
                    Expanded(
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: _bars[i],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Gap(6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final h in ['6h', '9h', '12h', '15h', '18h'])
                    MutedText(h, size: 10),
                ],
              ),
              const Gap(12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    IconBox(
                      AppIcons.clock,
                      size: 36,
                      iconSize: 20,
                      radius: 10,
                      bg: AppColors.warningBg,
                      fg: AppColors.warning,
                    ),
                    Gap(10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BoldText('Tránh 09:30–11:30 & 17–20h', size: 14),
                          MutedText('Giờ cao điểm 4.000 đ/kWh', size: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hero 3: trụ sạc ở giữa nối với nhà riêng, cửa hàng, chung cư, bãi đỗ.
class _ShareHero extends StatelessWidget {
  const _ShareHero();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final sx = c.maxWidth / 390, sy = c.maxHeight / 480;
        const nodes = [
          (52.0, 102.0, Icons.home_outlined, 'Nhà riêng'),
          (262.0, 102.0, Icons.storefront_outlined, 'Cửa hàng'),
          (52.0, 322.0, Icons.apartment_rounded, 'Chung cư'),
          (262.0, 322.0, Icons.local_parking_rounded, 'Bãi đỗ'),
        ];
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _LinksPainter(
                  center: Offset(195 * sx, 250 * sy),
                  points: [
                    for (final n in nodes)
                      Offset((n.$1 + 38) * sx, (n.$2 + 38) * sy),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 153 * sx,
              top: 208 * sy,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.blue.withValues(alpha: .18),
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  AppIcons.station,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            for (final (x, y, icon, label) in nodes)
              Positioned(
                left: x * sx,
                top: y * sy,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x240B3550),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: AppColors.blue, size: 26),
                      const Gap(4),
                      Text(
                        label,
                        style: AppFonts.body(size: 11, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LinksPainter extends CustomPainter {
  _LinksPainter({required this.center, required this.points});
  final Offset center;
  final List<Offset> points;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final pt in points) {
      final d = pt - center;
      final len = d.distance;
      for (var t = 0.0; t < len; t += 12) {
        final a = center + d / len * t;
        final b = center + d / len * math.min(t + 6, len);
        canvas.drawLine(a, b, p);
      }
    }
  }

  @override
  bool shouldRepaint(_LinksPainter old) => false;
}
