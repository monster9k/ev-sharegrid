import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bảng màu "kết hợp" (chốt 18/11/2026): nền trắng, nút/icon/link Blue 600,
/// mảng nhấn lớn Sky 200 với chữ [skyInk], nền nhấn nhỏ Sky 100.
class AppColors {
  AppColors._();

  static const blue = Color(0xFF3465D6);
  static const blue800 = Color(0xFF284FB0);
  static const sky200 = Color(0xFFC3E7F5);
  static const sky100 = Color(0xFFE3F4FB);
  static const skyInk = Color(0xFF0B3550);
  static const navy = Color(0xFF0B1B3F);
  static const ink = navy;
  static const body = Color(0xFF3A4560);
  static const muted = Color(0xFF56627D);
  static const border = Color(0xFFE1E6EF);
  static const divider = Color(0xFFEEF1F6);
  static const bg = Color(0xFFF4F6FA);
  static const webBg = Color(0xFFF7FBFD);
  static const surface = Colors.white;
  static const red = Color(0xFFD8232A);
  static const redBg = Color(0xFFFDECEC);
  static const success = Color(0xFF13804A);
  static const successBg = Color(0xFFE7F4EC);
  static const warning = Color(0xFFB45309);
  static const warningBg = Color(0xFFFDF1E3);
  static const neutralBg = Color(0xFFF1F3F2);

  // Biểu đồ (đã kiểm tra mù màu): chuỗi 1/2/3.
  static const chart1 = blue;
  static const chart2 = Color(0xFFC47F00);
  static const chart3 = Color(0xFF0E8F7E);
  static const chartGrey = Color(0xFFA9B3C7);
  static const grid = Color(0xFFEEF1F6);
  static const axis = Color(0xFFC5CCDA);

  // Biểu giá theo khung giờ.
  static const offPeak = sky200;
  static const normal = Color(0xFF7FA3EA);
  static const peak = warning;
  static const peakSoft = Color(0xFFFBE3CF);
}

/// Font: Bricolage Grotesque cho tiêu đề, Plus Jakarta Sans cho nội dung.
/// Demo offline và widget test dùng font mặc định.
class AppFonts {
  AppFonts._();

  static bool enabled = !const bool.fromEnvironment('DEMO_OFFLINE');

  static TextStyle display({
    double size = 22,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
    double? height,
  }) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: -0.2,
    );
    return enabled ? GoogleFonts.bricolageGrotesque(textStyle: base) : base;
  }

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
    double? height,
  }) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
    return enabled ? GoogleFonts.plusJakartaSans(textStyle: base) : base;
  }

  static TextStyle numbers({
    double size = 20,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.ink,
  }) {
    return display(
      size: size,
      weight: weight,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      primary: AppColors.blue,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.surface,
  );
  final family = AppFonts.enabled
      ? GoogleFonts.plusJakartaSans().fontFamily
      : null;
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: family,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.blue,
      thumbColor: AppColors.blue,
      inactiveTrackColor: AppColors.sky100,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
      ),
    ),
  );
}

/// Định dạng số kiểu Việt Nam: 54.700 · 22,77.
String vnInt(num value) {
  final s = value.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return value < 0 ? '-$buf' : buf.toString();
}

String vnDec(num value, [int digits = 1]) =>
    value.toStringAsFixed(digits).replaceAll('.', ',');
