import 'package:flutter/material.dart';

import 'finance_theme.dart';

/// Single place for the product name (rebrand = one-line change).
const kAppName = 'Diazen';

/// The "D" built from bars, with the lime side still filling. Geometry
/// follows the 120-unit grid of the brand sheet (single source in the app).
class AppMarkPainter extends CustomPainter {
  const AppMarkPainter({
    this.bar = Colors.white,
    this.accent = FinanceColors.lime,
  });
  final Color bar, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 120;
    final dx = (size.width - 120 * k) / 2;
    final dy = (size.height - 120 * k) / 2;
    void rect(
      double x,
      double y,
      double w,
      double h,
      Color color, [
      double r = 5,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(dx + x * k, dy + y * k, w * k, h * k),
          Radius.circular(r * k),
        ),
        Paint()
          ..color = color
          ..isAntiAlias = true,
      );
    }

    rect(28, 26, 18, 68, bar);
    rect(28, 26, 50, 16, bar);
    rect(28, 78, 50, 16, bar);
    rect(74, 38, 18, 44, accent, 6);
  }

  @override
  bool shouldRepaint(AppMarkPainter old) =>
      old.bar != bar || old.accent != accent;
}

/// App symbol on its graphite rounded square (radius 96/440 of the side).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Símbolo $kAppName',
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: FinanceColors.ink,
        borderRadius: BorderRadius.circular(size * 96 / 440),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size.square(size * 300 / 440),
        painter: const AppMarkPainter(),
      ),
    ),
  );
}

/// Symbol followed by the product name.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppLogo(size: size),
      SizedBox(width: size * 0.3),
      ExcludeSemantics(
        child: Text(
          kAppName,
          style: TextStyle(
            fontFamily: FinanceFonts.display,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.62,
            letterSpacing: -0.4,
            color: FinanceColors.ink,
          ),
        ),
      ),
    ],
  );
}
