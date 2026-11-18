import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme.dart';

/// Bản đồ trung tâm Đà Nẵng vẽ tay theo phong cách Google Maps
/// (vịnh, sông Hàn, các cầu, biển Mỹ Khê). Hệ toạ độ gốc 390 × 844.
class DanangMap extends StatelessWidget {
  const DanangMap({
    super.key,
    this.stations = const [],
    this.selectedId,
    this.onPinTap,
    this.showLabels = true,
    this.alignment = Alignment.topCenter,
    this.userDot = const Offset(150, 360),
  });

  final List<Station> stations;
  final int? selectedId;
  final ValueChanged<Station>? onPinTap;
  final bool showLabels;
  final Alignment alignment;
  final Offset? userDot;

  static const base = Size(390, 844);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final scale = math.max(
          c.maxWidth / base.width,
          c.maxHeight / base.height,
        );
        final w = base.width * scale;
        final h = base.height * scale;
        final dx = (c.maxWidth - w) * (alignment.x + 1) / 2;
        final dy = (c.maxHeight - h) * (alignment.y + 1) / 2;
        Offset map(Offset p) => Offset(dx + p.dx * scale, dy + p.dy * scale);

        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: dx,
                top: dy,
                width: w,
                height: h,
                child: CustomPaint(
                  painter: _DanangPainter(showLabels: showLabels),
                ),
              ),
              if (userDot != null)
                Positioned(
                  left: map(userDot!).dx - 11,
                  top: map(userDot!).dy - 11,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.blue.withValues(alpha: .25),
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              for (final s in stations)
                _positionedPin(
                  s,
                  map(Offset(s.mapX * base.width, s.mapY * base.height)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _positionedPin(Station s, Offset at) {
    final selected = s.id == selectedId;
    final (bg, fg, dot) = switch (s.availability) {
      _ when selected => (AppColors.blue, Colors.white, Colors.white),
      Availability.free => (Colors.white, AppColors.ink, AppColors.success),
      Availability.busy => (Colors.white, AppColors.ink, AppColors.warning),
      Availability.full => (Colors.white, AppColors.muted, AppColors.red),
    };
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: FractionalTranslation(
        translation: const Offset(-.5, -1),
        child: GestureDetector(
          onTap: onPinTap == null ? null : () => onPinTap!(s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: selected ? 12 : 9,
                  vertical: selected ? 7 : 5,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x330B1B3F),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      Icon(Icons.bolt_rounded, size: 14, color: fg)
                    else
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      s.pinNote == null
                          ? s.pinLabel
                          : '${s.pinLabel} · ${s.pinNote}',
                      style: AppFonts.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
              CustomPaint(
                size: const Size(10, 6),
                painter: _TrianglePainter(bg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

class _DanangPainter extends CustomPainter {
  _DanangPainter({required this.showLabels});
  final bool showLabels;

  static const land = Color(0xFFF3F1EC);
  static const water = Color(0xFFAAD3F2);
  static const park = Color(0xFFCFE6C8);
  static const block = Color(0xFFE5E2DB);
  static const arterial = Color(0xFFF6D77A);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 390;
    canvas.save();
    canvas.scale(s);

    final fill = Paint()..style = PaintingStyle.fill;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 844), fill..color = land);

    // Vịnh Đà Nẵng.
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(250, 0)
        ..cubicTo(232, 40, 214, 72, 196, 96)
        ..cubicTo(150, 104, 80, 100, 0, 116)
        ..close(),
      fill..color = water,
    );
    // Bán đảo Sơn Trà.
    canvas.drawPath(
      Path()
        ..moveTo(250, 0)
        ..lineTo(390, 0)
        ..lineTo(390, 120)
        ..cubicTo(370, 110, 340, 95, 300, 92)
        ..cubicTo(270, 90, 252, 70, 250, 0)
        ..close(),
      fill..color = park,
    );
    // Biển Mỹ Khê.
    canvas.drawPath(
      Path()
        ..moveTo(354, 120)
        ..cubicTo(346, 250, 340, 420, 348, 600)
        ..cubicTo(352, 700, 356, 780, 360, 844)
        ..lineTo(390, 844)
        ..lineTo(390, 120)
        ..close(),
      fill..color = water,
    );

    void rrect(double x, double y, double w, double h, double r, Color c) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
        fill..color = c,
      );
    }

    rrect(0, 430, 112, 250, 8, block); // sân bay
    rrect(148, 338, 30, 42, 5, park);
    rrect(300, 226, 28, 44, 5, park);
    rrect(262, 600, 60, 70, 10, park);

    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white
      ..strokeWidth = 5;
    for (final seg in const [
      [70.0, 120.0, 70.0, 844.0],
      [120.0, 112.0, 120.0, 844.0],
      [150.0, 400.0, 192.0, 844.0],
      [0.0, 200.0, 120.0, 232.0],
      [0.0, 230.0, 184.0, 230.0],
      [0.0, 270.0, 184.0, 270.0],
      [240.0, 230.0, 340.0, 230.0],
      [260.0, 420.0, 340.0, 420.0],
      [245.0, 500.0, 340.0, 500.0],
      [0.0, 380.0, 140.0, 380.0],
    ]) {
      canvas.drawLine(Offset(seg[0], seg[1]), Offset(seg[2], seg[3]), road);
    }
    canvas.drawPath(
      Path()
        ..moveTo(186, 118)
        ..cubicTo(182, 250, 192, 340, 190, 520),
      road,
    );

    // Sông Hàn.
    canvas.drawPath(
      Path()
        ..moveTo(206, 844)
        ..cubicTo(200, 700, 216, 560, 212, 430)
        ..cubicTo(207, 330, 197, 240, 201, 150)
        ..cubicTo(203, 122, 199, 102, 191, 92),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = water
        ..strokeWidth = 30,
    );

    final main = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = arterial
      ..strokeWidth = 7;
    canvas.drawPath(
      Path()
        ..moveTo(242, 112)
        ..cubicTo(236, 300, 239, 500, 246, 844),
      main,
    );
    canvas.drawPath(
      Path()
        ..moveTo(332, 128)
        ..cubicTo(328, 300, 326, 500, 336, 844),
      main,
    );
    canvas.drawLine(const Offset(0, 330), const Offset(340, 330), main);

    // Cầu qua sông Hàn.
    final bridge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white
      ..strokeWidth = 6;
    canvas.drawLine(const Offset(180, 160), const Offset(244, 150), bridge);
    canvas.drawLine(const Offset(184, 255), const Offset(240, 255), bridge);
    canvas.drawLine(const Offset(190, 402), const Offset(242, 402), bridge);

    if (showLabels) {
      void label(
        String t,
        double x,
        double y, {
        Color color = const Color(0xFF5F6B7A),
        double size = 10,
        FontWeight weight = FontWeight.w700,
        bool italic = false,
        double spacing = 1.2,
        double rotate = 0,
      }) {
        final tp = TextPainter(
          text: TextSpan(
            text: t,
            style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: weight,
              letterSpacing: spacing,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(rotate * math.pi / 180);
        tp.paint(canvas, Offset(0, -tp.height * .8));
        canvas.restore();
      }

      label('THANH KHÊ', 34, 182);
      label('HẢI CHÂU', 86, 300);
      label('SƠN TRÀ', 262, 206);
      label('AN HẢI', 264, 384);
      label('NGŨ HÀNH SƠN', 252, 560);
      const sea = Color(0xFF3B6EA8);
      label(
        'Vịnh Đà Nẵng',
        70,
        62,
        color: sea,
        size: 11,
        weight: FontWeight.w600,
        italic: true,
        spacing: 0,
      );
      label(
        'Sông Hàn',
        222,
        520,
        color: sea,
        size: 11,
        weight: FontWeight.w600,
        italic: true,
        spacing: 0,
        rotate: -86,
      );
      label(
        'Biển Mỹ Khê',
        366,
        300,
        color: sea,
        size: 11,
        weight: FontWeight.w600,
        italic: true,
        spacing: 0,
        rotate: 90,
      );
      label(
        'Bán đảo Sơn Trà',
        300,
        48,
        color: const Color(0xFF2E7D32),
        weight: FontWeight.w600,
        spacing: 0,
      );
      for (final (t, x, y) in const [
        ('Nguyễn Văn Linh', 22.0, 324.0),
        ('Cầu Rồng', 196.0, 324.0),
        ('Sân bay Đà Nẵng', 14.0, 560.0),
      ]) {
        label(t, x, y, size: 9, weight: FontWeight.w600, spacing: 0);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DanangPainter old) => old.showLabels != showLabels;
}
