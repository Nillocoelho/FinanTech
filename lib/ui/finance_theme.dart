import 'package:flutter/material.dart';

abstract final class FinanceColors {
  static const ink = Color(0xFF142B45);
  static const muted = Color(0xFF64748B);
  static const canvas = Color(0xFFF4F6F8);
  static const line = Color(0xFFE3E8EF);
  static const green = Color(0xFF087F5B);
  static const red = Color(0xFFB42332);
  static const amber = Color(0xFF966018);
}

ThemeData financeTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: FinanceColors.ink,
        brightness: Brightness.light,
      ).copyWith(
        primary: FinanceColors.ink,
        secondary: FinanceColors.green,
        surface: Colors.white,
        onSurface: FinanceColors.ink,
        onSurfaceVariant: FinanceColors.muted,
        outlineVariant: FinanceColors.line,
        error: FinanceColors.red,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
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
        fontFamily: 'Roboto',
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: FinanceColors.ink,
        letterSpacing: -0.5,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: FinanceColors.line),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: FinanceColors.line,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FinanceColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: FinanceColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: FinanceColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FinanceColors.canvas,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFE8EEF4),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: FinanceColors.ink,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: FinanceColors.ink,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: FinanceColors.muted,
    ),
  );
}
