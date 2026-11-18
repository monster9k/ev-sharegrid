import 'package:flutter/material.dart';

import '../theme.dart';

/// Khi mở app USER trên màn rộng (web desktop), đặt nội dung vào khung
/// điện thoại 430 px ở giữa để giữ đúng bố cục di động.
class MobileFrame extends StatelessWidget {
  const MobileFrame({super.key, required this.child});
  final Widget child;

  static const maxWidth = 430.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width <= 600) return child;
    final height = size.height > 960 ? 932.0 : size.height - 32;
    return ColoredBox(
      color: AppColors.webBg,
      child: Stack(
        children: [
          const Positioned(
            left: -120,
            top: -100,
            child: _Blob(size: 420, color: AppColors.sky200),
          ),
          const Positioned(
            right: -140,
            bottom: -120,
            child: _Blob(size: 460, color: AppColors.sky100),
          ),
          Center(
            child: Container(
              width: maxWidth,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1F0B1B3F),
                    blurRadius: 40,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(size: Size(maxWidth, height)),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withValues(alpha: .9), color.withValues(alpha: 0)],
      ),
    ),
  );
}
