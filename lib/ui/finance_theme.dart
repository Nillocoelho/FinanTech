import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens of the 2.0 visual system.
///
/// Lime is an accent that only appears on graphite surfaces (hero card,
/// "+" button, active counters). State colors are always used as a pair
/// (foreground on its tinted background) to keep the specified contrast.
abstract final class FinanceColors {
  static const ink = Color(0xFF14161A);
  static const lime = Color(0xFFD2F35A);
  static const canvas = Color(0xFFF3F3EF);
  static const surface = Colors.white;
  static const line = Color(0xFFE4E4DE);
  static const lineSoft = Color(0xFFEEEEE9);
  static const outline = Color(0xFFD9D9D2);
  static const muted = Color(0xFF5E636B);
  static const body = Color(0xFF3D4148);
  static const chip = Color(0xFFF0F0EA);
  static const chipActive = Color(0xFFDCDCD5);
  static const track = Color(0xFFE7E7E1);
  static const toggle = Color(0xFFBDBEB6);

  // Graphite surfaces.
  static const onInkMuted = Color(0xFFB4B9C0);
  static const inkTrack = Color(0xFF33363C);
  static const inkNext = Color(0xFF6E7178);
  static const coral = Color(0xFFFF7A66);

  // Planning.
  static const olive = Color(0xFF6B8A1E);
  static const oliveSoft = Color(0xFFA3B46E);
  static const inkSoft = Color(0xFF5B5E64);
  static const nextRow = Color(0xFFF7FBE6);

  // States.
  static const late = Color(0xFFB42318);
  static const lateBg = Color(0xFFFDECEA);
  static const lateText = Color(0xFF7A1A12);
  static const soon = Color(0xFF9A5B00);
  static const soonBg = Color(0xFFFFF4DE);
  static const paid = Color(0xFF0B7A55);
  static const paidBg = Color(0xFFE3F4EC);

  // Names kept for screens that only consume the theme (Ajustes).
  static const green = paid;
  static const red = late;
  static const amber = soon;
}

abstract final class FinanceFonts {
  static const ui = 'Inter';
  static const display = 'SpaceGrotesk';
  static const tabular = [FontFeature.tabularFigures()];
}

/// Text styles shared by the screens. Space Grotesk is reserved for
/// amounts and titles; everything else uses Inter from the theme.
abstract final class FinanceText {
  static const title = TextStyle(
    fontFamily: FinanceFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    letterSpacing: -0.5,
    height: 1.1,
    color: FinanceColors.ink,
  );
  static const section = TextStyle(
    fontFamily: FinanceFonts.display,
    fontWeight: FontWeight.w700,
    fontSize: 19,
    letterSpacing: -0.2,
    color: FinanceColors.ink,
  );
  static const amount = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 15,
    fontFeatures: FinanceFonts.tabular,
    color: FinanceColors.ink,
  );
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: FinanceColors.body,
  );
  static const caption = TextStyle(fontSize: 13, color: FinanceColors.muted);
  static const overline = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: FinanceColors.body,
  );
}

var _licensesRegistered = false;

/// Bundled fonts are OFL; their licenses are listed in the licenses page.
void registerFontLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    for (final (package, file) in [
      ('Inter', 'assets/fonts/OFL-Inter.txt'),
      ('Space Grotesk', 'assets/fonts/OFL-SpaceGrotesk.txt'),
    ]) {
      try {
        yield LicenseEntryWithLineBreaks([
          package,
        ], await rootBundle.loadString(file));
      } catch (_) {
        // Asset missing in a test bundle: nothing to list.
      }
    }
  });
}

ThemeData financeTheme() {
  registerFontLicenses();
  final scheme =
      ColorScheme.fromSeed(
        seedColor: FinanceColors.ink,
        brightness: Brightness.light,
      ).copyWith(
        primary: FinanceColors.ink,
        onPrimary: Colors.white,
        secondary: FinanceColors.paid,
        surface: FinanceColors.surface,
        onSurface: FinanceColors.ink,
        onSurfaceVariant: FinanceColors.muted,
        outline: FinanceColors.outline,
        outlineVariant: FinanceColors.line,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: FinanceColors.canvas,
        surfaceContainer: FinanceColors.canvas,
        surfaceContainerHigh: FinanceColors.chip,
        surfaceContainerHighest: FinanceColors.track,
        error: FinanceColors.late,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: FinanceFonts.ui,
  );
  final rounded14 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  return base.copyWith(
    scaffoldBackgroundColor: FinanceColors.canvas,
    textTheme: base.textTheme.apply(
      bodyColor: FinanceColors.ink,
      displayColor: FinanceColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: FinanceColors.canvas,
      foregroundColor: FinanceColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: FinanceFonts.display,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: FinanceColors.ink,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: FinanceColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: FinanceColors.lineSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      hintStyle: const TextStyle(color: FinanceColors.muted),
      labelStyle: const TextStyle(color: FinanceColors.body),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FinanceColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FinanceColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: FinanceColors.ink, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FinanceColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: rounded14,
        textStyle: const TextStyle(
          fontFamily: FinanceFonts.ui,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FinanceColors.ink,
        backgroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: FinanceColors.line),
        shape: rounded14,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FinanceColors.ink,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(
          fontFamily: FinanceFonts.ui,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: FinanceColors.ink,
        minimumSize: const Size(44, 44),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: FinanceColors.ink,
      side: const BorderSide(color: FinanceColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
        fontFamily: FinanceFonts.ui,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: FinanceColors.ink,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: FinanceFonts.ui,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: Colors.white,
      ),
      checkmarkColor: Colors.white,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? FinanceColors.lime : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? FinanceColors.ink : null,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FinanceColors.ink,
      linearTrackColor: FinanceColors.line,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FinanceColors.canvas,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        fontFamily: FinanceFonts.display,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: FinanceColors.ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: FinanceColors.chip,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: FinanceFonts.ui,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: FinanceColors.ink,
      actionTextColor: FinanceColors.lime,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: FinanceColors.ink,
      foregroundColor: FinanceColors.lime,
      elevation: 2,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: FinanceColors.body,
    ),
  );
}
