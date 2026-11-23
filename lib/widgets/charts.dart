import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../data/models.dart';
import '../theme.dart';

TextPainter _tp(
  String t, {
  double size = 10,
  Color color = AppColors.muted,
  FontWeight weight = FontWeight.w500,
}) => TextPainter(
  text: TextSpan(
    text: t,
    style: TextStyle(fontSize: size, color: color, fontWeight: weight),
  ),
  textDirection: TextDirection.ltr,
)..layout();

void _text(
  Canvas c,
  String t,
  Offset at, {
  double size = 10,
  Color color = AppColors.muted,
  FontWeight weight = FontWeight.w500,
  double anchor = .5, // 0 = trái, .5 = giữa, 1 = phải
}) {
  final tp = _tp(t, size: size, color: color, weight: weight);
  tp.paint(c, Offset(at.dx - tp.width * anchor, at.dy - tp.height / 2));
}

Color bandColor(TariffBand b) => switch (b) {
  TariffBand.offPeak => AppColors.offPeak,
  TariffBand.normal => AppColors.normal,
  TariffBand.peak => AppColors.peak,
};

/// Dải biểu giá 24 ô (mỗi ô 1 giờ) + nhãn 0h/6h/12h/18h/24h.
class TariffStrip extends StatelessWidget {
  const TariffStrip({super.key, this.height = 30, this.highlightHour});
  final double height;
  final int? highlightHour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Biểu giá theo giờ: thấp điểm 22h đến 4h, cao điểm 9h30 đến 11h30 và 17h đến 20h',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  for (var h = 0; h < 24; h++) ...[
                    if (h > 0) const SizedBox(width: 2),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: bandColor(Mock.bandAt(h + .5)),
                          border: h == highlightHour
                              ? Border.all(color: AppColors.ink, width: 2)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final l in ['0h', '6h', '12h', '18h', '24h'])
                Text(l, style: AppFonts.body(size: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Biểu đồ bậc giá điện trong ngày (đ/kWh), có vạch "bây giờ".
class TariffStepChart extends StatelessWidget {
  const TariffStepChart({super.key, this.height = 150, this.nowHour = 8.5});
  final double height;
  final double? nowHour;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Biểu đồ giá điện theo khung giờ trong ngày',
    child: SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _TariffStepPainter(nowHour),
      ),
    ),
  );
}

class _TariffStepPainter extends CustomPainter {
  _TariffStepPainter(this.now);
  final double? now;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 22.0, top = 10.0;
    final w = size.width - left - 4;
    final h = size.height - bottom - top;
    double x(double hour) => left + hour / 24 * w;
    double y(num price) => top + h - price / 4400 * h;

    final grid = Paint()..color = AppColors.grid;
    for (final p in [1600, 2400, 4000]) {
      canvas.drawLine(Offset(left, y(p)), Offset(left + w, y(p)), grid);
      _text(canvas, vnInt(p), Offset(left - 4, y(p)), anchor: 1, size: 9);
    }
    for (final win in Mock.tariff) {
      final r = RRect.fromRectAndCorners(
        Rect.fromLTRB(
          x(win.start) + .5,
          y(win.price),
          x(win.end) - .5,
          top + h,
        ),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(r, Paint()..color = bandColor(win.band));
    }
    canvas.drawLine(
      Offset(left, top + h),
      Offset(left + w, top + h),
      Paint()..color = AppColors.axis,
    );
    for (final hr in [0, 6, 12, 18, 24]) {
      _text(canvas, '${hr}h', Offset(x(hr.toDouble()), size.height - 8));
    }
    if (now != null) {
      final nx = x(now!);
      final p = Paint()
        ..color = AppColors.ink
        ..strokeWidth = 1.5;
      for (var yy = top - 4; yy < top + h; yy += 6) {
        canvas.drawLine(Offset(nx, yy), Offset(nx, yy + 3), p);
      }
      _text(
        canvas,
        'Bây giờ',
        Offset(nx + 4, top),
        anchor: 0,
        weight: FontWeight.w700,
        color: AppColors.ink,
      );
    }
  }

  @override
  bool shouldRepaint(_TariffStepPainter old) => old.now != now;
}

/// Lịch theo slot 15 phút: cột kW mỗi slot + dải giá ở chân.
class SlotScheduleChart extends StatelessWidget {
  const SlotScheduleChart({
    super.key,
    required this.slots,
    this.from = 8,
    this.to = 17.5,
    this.maxKw = 11,
    this.height = 160,
    this.highlightUntil,
    this.showTariffBands = true,
  });
  final List<ScheduleSlot> slots;
  final double from;
  final double to;
  final double maxKw;
  final double height;

  /// Slot trước mốc này vẽ đậm hơn (đã sạc / bị khoá).
  final double? highlightUntil;
  final bool showTariffBands;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Biểu đồ cột công suất theo slot 15 phút',
    child: SizedBox(
      height: height,
      child: CustomPaint(size: Size.infinite, painter: _SlotPainter(this)),
    ),
  );
}

class _SlotPainter extends CustomPainter {
  _SlotPainter(this.c);
  final SlotScheduleChart c;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0, bottom = 36.0, top = 12.0;
    final w = size.width - left - 4;
    final h = size.height - bottom - top;
    final span = math.max(0.25, c.to - c.from);
    double x(double hour) => left + (hour - c.from) / span * w;
    double y(double kw) => top + h - kw / c.maxKw * h;

    final grid = Paint()..color = AppColors.grid;
    for (final v in [c.maxKw / 2, c.maxKw]) {
      canvas.drawLine(Offset(left, y(v)), Offset(left + w, y(v)), grid);
      _text(
        canvas,
        vnDec(v, v % 1 == 0 ? 0 : 1),
        Offset(left - 5, y(v)),
        anchor: 1,
      );
    }
    canvas.drawLine(
      Offset(left, top + h),
      Offset(left + w, top + h),
      Paint()..color = AppColors.axis,
    );

    final slotW = w / (span * 4);
    for (final s in c.slots) {
      final locked = c.highlightUntil != null && s.start < c.highlightUntil!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x(s.start) + .6,
            y(s.kw),
            slotW - 1.2,
            top + h - y(s.kw),
          ),
          const Radius.circular(2),
        ),
        Paint()..color = locked ? AppColors.blue800 : AppColors.blue,
      );
    }

    // Dải giá ở chân biểu đồ.
    if (c.showTariffBands) {
      final bandY = top + h + 8;
      for (final win in Mock.tariff) {
        final a = math.max(win.start, c.from), b = math.min(win.end, c.to);
        if (b <= a) continue;
        final peak = win.band == TariffBand.peak;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x(a) + .5, bandY, x(b) - .5, bandY + 8),
            const Radius.circular(2),
          ),
          Paint()..color = peak ? const Color(0xFFF3C9A5) : AppColors.border,
        );
        if (peak && b - a >= 1.5) {
          final mid = x((a + b) / 2);
          _text(canvas, 'không sạc', Offset(mid, y(c.maxKw * .26)));
          _text(
            canvas,
            'Cao điểm',
            Offset(mid, y(c.maxKw * .12)),
            weight: FontWeight.w700,
            color: AppColors.warning,
          );
        }
      }
    }
    for (var hr = c.from.ceil(); hr <= c.to; hr += 2) {
      _text(canvas, '${hr}h', Offset(x(hr.toDouble()), size.height - 8));
    }
  }

  @override
  bool shouldRepaint(_SlotPainter old) => true;
}

/// Một chuỗi số cho biểu đồ đường.
class LineSeries {
  const LineSeries(
    this.values, {
    required this.color,
    this.label = '',
    this.dashed = false,
    this.startIndex = 0,
    this.area = false,
    this.dots = false,
  });
  final List<double> values;
  final Color color;
  final String label;
  final bool dashed;
  final int startIndex;
  final bool area;
  final bool dots;
}

/// Biểu đồ đường tổng quát (hỗ trợ trục log, đường ngưỡng).
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    required this.xLabels,
    this.height = 200,
    this.maxY,
    this.minY = 0,
    this.log = false,
    this.yTicks,
    this.threshold,
    this.thresholdLabel,
    this.yFormat,
    this.semantics = 'Biểu đồ đường',
    this.dividerAt,
    this.dividerLabel,
  });
  final List<LineSeries> series;
  final List<String> xLabels;
  final double height;
  final double? maxY;
  final double minY;
  final bool log;
  final List<double>? yTicks;
  final double? threshold;
  final String? thresholdLabel;
  final String Function(double)? yFormat;
  final String semantics;
  final double? dividerAt;
  final String? dividerLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    child: SizedBox(
      height: height,
      child: CustomPaint(size: Size.infinite, painter: _LinePainter(this)),
    ),
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.c);
  final LineChart c;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, bottom = 22.0, top = 12.0, right = 8.0;
    final w = size.width - left - right;
    final h = size.height - bottom - top;
    final n = c.xLabels.length;
    final maxV =
        c.maxY ??
        c.series.expand((s) => s.values).fold<double>(0, math.max) * 1.1;
    double tr(double v) => c.log ? math.log(math.max(v, 1e-3)) / math.ln10 : v;
    final lo = tr(c.log ? math.max(c.minY, 1e-3) : c.minY), hi = tr(maxV);
    double x(num i) => left + (n <= 1 ? 0 : i / (n - 1) * w);
    double y(double v) => top + h - (tr(v) - lo) / (hi - lo) * h;

    final ticks =
        c.yTicks ??
        [for (var i = 0; i <= 4; i++) c.minY + (maxV - c.minY) * i / 4];
    final grid = Paint()..color = AppColors.grid;
    for (final t in ticks) {
      canvas.drawLine(Offset(left, y(t)), Offset(left + w, y(t)), grid);
      _text(
        canvas,
        c.yFormat?.call(t) ?? vnDec(t, t % 1 == 0 ? 0 : 1),
        Offset(left - 6, y(t)),
        anchor: 1,
      );
    }
    canvas.drawLine(
      Offset(left, top + h),
      Offset(left + w, top + h),
      Paint()..color = AppColors.axis,
    );
    final every = (n / 7).ceil();
    for (var i = 0; i < n; i += every) {
      _text(canvas, c.xLabels[i], Offset(x(i), size.height - 8));
    }

    if (c.dividerAt != null) {
      final dx = x(c.dividerAt!);
      final p = Paint()
        ..color = AppColors.axis
        ..strokeWidth = 1;
      for (var yy = top; yy < top + h; yy += 6) {
        canvas.drawLine(Offset(dx, yy), Offset(dx, yy + 3), p);
      }
      if (c.dividerLabel != null) {
        _text(canvas, c.dividerLabel!, Offset(dx + 4, top + 2), anchor: 0);
      }
    }

    if (c.threshold != null) {
      final ty = y(c.threshold!);
      final p = Paint()
        ..color = AppColors.red
        ..strokeWidth = 1.5;
      for (var xx = left; xx < left + w; xx += 8) {
        canvas.drawLine(
          Offset(xx, ty),
          Offset(math.min(xx + 4, left + w), ty),
          p,
        );
      }
      if (c.thresholdLabel != null) {
        _text(
          canvas,
          c.thresholdLabel!,
          Offset(left + w, ty - 9),
          anchor: 1,
          color: AppColors.red,
          weight: FontWeight.w700,
        );
      }
    }

    for (final s in c.series) {
      final path = Path();
      for (var i = 0; i < s.values.length; i++) {
        final p = Offset(x(i + s.startIndex), y(s.values[i]));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      if (s.area && s.values.isNotEmpty) {
        final area = Path.from(path)
          ..lineTo(x(s.values.length - 1 + s.startIndex), top + h)
          ..lineTo(x(s.startIndex), top + h)
          ..close();
        canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: .12));
      }
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (s.dashed) {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 10) {
            canvas.drawPath(m.extractPath(d, math.min(d + 6, m.length)), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
      if (s.dots) {
        for (var i = 0; i < s.values.length; i++) {
          final p = Offset(x(i + s.startIndex), y(s.values[i]));
          canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
          canvas.drawCircle(
            p,
            3.5,
            Paint()
              ..color = s.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

/// Biểu đồ cột đứng (mức đông theo giờ, tải trạm…), có đường trần tuỳ chọn.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.xLabels,
    this.height = 140,
    this.maxY,
    this.cap,
    this.capLabel,
    this.highlight,
    this.color = AppColors.sky200,
    this.highlightColor = AppColors.blue,
    this.showYAxis = false,
    this.semantics = 'Biểu đồ cột',
    this.colorFor,
  });
  final List<double> values;
  final List<String> xLabels;
  final double height;
  final double? maxY;
  final double? cap;
  final String? capLabel;
  final int? highlight;
  final Color color;
  final Color highlightColor;
  final bool showYAxis;
  final String semantics;
  final Color Function(int i, double v)? colorFor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    child: SizedBox(
      height: height,
      child: CustomPaint(size: Size.infinite, painter: _BarPainter(this)),
    ),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.c);
  final BarChart c;

  @override
  void paint(Canvas canvas, Size size) {
    final left = c.showYAxis ? 32.0 : 0.0;
    const bottom = 20.0, top = 14.0;
    final w = size.width - left;
    final h = size.height - bottom - top;
    final maxV = c.maxY ?? c.values.fold<double>(0, math.max) * 1.1;
    double y(double v) => top + h - v / maxV * h;
    final n = c.values.length;
    final slot = w / n;

    if (c.showYAxis) {
      final grid = Paint()..color = AppColors.grid;
      for (var i = 1; i <= 2; i++) {
        final v = maxV * i / 2;
        canvas.drawLine(Offset(left, y(v)), Offset(left + w, y(v)), grid);
        _text(canvas, vnInt(v), Offset(left - 5, y(v)), anchor: 1);
      }
    }
    for (var i = 0; i < n; i++) {
      final v = c.values[i];
      final color =
          c.colorFor?.call(i, v) ??
          (i == c.highlight ? c.highlightColor : c.color);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            left + i * slot + slot * .12,
            y(v),
            slot * .76,
            top + h - y(v),
          ),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = color,
      );
    }
    canvas.drawLine(
      Offset(left, top + h),
      Offset(left + w, top + h),
      Paint()..color = AppColors.axis,
    );
    if (c.cap != null) {
      final cy = y(c.cap!);
      final p = Paint()
        ..color = AppColors.red
        ..strokeWidth = 1.5;
      for (var xx = left; xx < left + w; xx += 8) {
        canvas.drawLine(
          Offset(xx, cy),
          Offset(math.min(xx + 4, left + w), cy),
          p,
        );
      }
      if (c.capLabel != null) {
        _text(
          canvas,
          c.capLabel!,
          Offset(left + w, cy - 8),
          anchor: 1,
          color: AppColors.red,
          weight: FontWeight.w700,
        );
      }
    }
    final every = math.max(1, (n / 6).ceil());
    for (var i = 0; i < c.xLabels.length; i += every) {
      _text(
        canvas,
        c.xLabels[i],
        Offset(left + i * slot + slot / 2, size.height - 7),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}

/// Thanh ngang so sánh (KPI benchmark…).
class HBar extends StatelessWidget {
  const HBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.display,
    this.color = AppColors.blue,
    this.labelWidth = 110,
  });
  final String label;
  final double value;
  final double max;
  final String display;
  final Color color;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: AppFonts.body(size: 12, weight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Row(
                children: [
                  Container(
                    width: math.max(3, c.maxWidth * .78 * (value / max)),
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      display,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.body(
                        size: 12,
                        weight: FontWeight.w600,
                        color: AppColors.body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gantt cổng × giờ cho HOST (khối request, bảo trì, slot đã khoá).
class PortGantt extends StatelessWidget {
  const PortGantt({
    super.key,
    required this.rows,
    required this.blocks,
    this.from = 6,
    this.to = 22,
    this.now = 9.25,
    this.rowHeight = 34,
  });
  final List<String> rows;
  final List<GanttBlock> blocks;
  final double from;
  final double to;
  final double? now;
  final double rowHeight;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Biểu đồ Gantt sử dụng cổng theo giờ',
    child: SizedBox(
      height: rows.length * rowHeight + 30,
      child: CustomPaint(size: Size.infinite, painter: _GanttPainter(this)),
    ),
  );
}

class _GanttPainter extends CustomPainter {
  _GanttPainter(this.c);
  final PortGantt c;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 40.0, top = 4.0;
    final w = size.width - left - 4;
    final span = math.max(0.25, c.to - c.from);
    double x(double hour) => left + (hour - c.from) / span * w;

    final grid = Paint()..color = AppColors.grid;
    for (var hr = c.from; hr <= c.to; hr += 2) {
      canvas.drawLine(
        Offset(x(hr), top),
        Offset(x(hr), top + c.rows.length * c.rowHeight),
        grid,
      );
      _text(
        canvas,
        '${hr.toInt()}h',
        Offset(x(hr), top + c.rows.length * c.rowHeight + 12),
      );
    }
    for (var r = 0; r < c.rows.length; r++) {
      final cy = top + r * c.rowHeight + c.rowHeight / 2;
      _text(
        canvas,
        c.rows[r],
        Offset(0, cy),
        anchor: 0,
        weight: FontWeight.w700,
        color: AppColors.ink,
        size: 12,
      );
    }
    for (final b in c.blocks) {
      final rect = Rect.fromLTRB(
        x(b.start) + 1,
        top + b.row * c.rowHeight + 5,
        x(b.end) - 1,
        top + (b.row + 1) * c.rowHeight - 5,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      if (b.maintenance) {
        canvas.drawRRect(rr, Paint()..color = AppColors.warningBg);
        canvas.save();
        canvas.clipRRect(rr);
        final hatch = Paint()
          ..color = const Color(0xFFF0C48E)
          ..strokeWidth = 2;
        for (var xx = rect.left - rect.height; xx < rect.right; xx += 8) {
          canvas.drawLine(
            Offset(xx, rect.bottom),
            Offset(xx + rect.height, rect.top),
            hatch,
          );
        }
        canvas.restore();
        _label(canvas, rect, b.label, AppColors.warning);
        continue;
      }
      final color = b.shortfall
          ? AppColors.warning
          : b.locked
          ? AppColors.blue800
          : AppColors.blue;
      canvas.drawRRect(rr, Paint()..color = color);
      if (b.lockedUntil != null && b.lockedUntil! > b.start) {
        final lr = Rect.fromLTRB(
          rect.left,
          rect.top,
          x(b.lockedUntil!),
          rect.bottom,
        );
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            lr,
            topLeft: const Radius.circular(6),
            bottomLeft: const Radius.circular(6),
          ),
          Paint()..color = AppColors.blue800,
        );
      }
      _label(canvas, rect, b.label, Colors.white);
    }
    if (c.now != null) {
      final nx = x(c.now!);
      canvas.drawLine(
        Offset(nx, top - 2),
        Offset(nx, top + c.rows.length * c.rowHeight),
        Paint()
          ..color = AppColors.red
          ..strokeWidth = 2,
      );
    }
  }

  void _label(Canvas canvas, Rect r, String t, Color color) {
    if (t.isEmpty) return;
    final tp = _tp(t, size: 10, color: color, weight: FontWeight.w700);
    if (tp.width > r.width - 6) return;
    tp.paint(canvas, Offset(r.left + 5, r.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_GanttPainter old) => true;
}

/// Biểu đồ vòng (tỉ lệ) đơn giản.
class Donut extends StatelessWidget {
  const Donut({super.key, required this.parts, this.size = 120, this.center});
  final List<(double, Color)> parts;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _DonutPainter(parts),
      child: Center(child: center),
    ),
  );
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts);
  final List<(double, Color)> parts;
  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold<double>(0, (s, p) => s + p.$1);
    final rect = Offset.zero & size;
    var a = -math.pi / 2;
    for (final (v, color) in parts) {
      final sweep = v / total * math.pi * 2;
      canvas.drawArc(
        rect.deflate(9),
        a,
        sweep - .04,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 16,
      );
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}
