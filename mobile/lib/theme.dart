import 'package:flutter/material.dart';

/// Design tokens from `design/` — see design/README.md for the source palette.
class MtColors {
  static const petrol = Color(0xFF1B4965);
  static const petrolHover = Color(0xFF2D7AA9);
  static const petrolTint = Color(0xFFEAF3FA);
  static const petrolBorder = Color(0xFFCFE4F2);
  static const rust = Color(0xFFB84F20);
  static const graphite = Color(0xFF0F172A);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate500 = Color(0xFF64748B);
  static const background = Color(0xFFF7FAFC);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFEAB308);
  static const warningText = Color(0xFF854D0E);
  static const successText = Color(0xFF166534);
  static const danger = Color(0xFFEF4444);
}

/// Spacing and shape constants shared by every screen.
class MtSizes {
  static const screenPadding = 20.0;
  static const cardRadius = 10.0;
  static const controlRadius = 8.0;
  static const controlHeight = 44.0;
  static const primaryButtonHeight = 48.0;
}

ThemeData buildMototecaTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: MtColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: MtColors.petrol,
      secondary: MtColors.rust,
      surface: Colors.white,
      error: MtColors.danger,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MtColors.petrolTint,
      foregroundColor: MtColors.graphite,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: MtColors.graphite,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      shape: Border(bottom: BorderSide(color: MtColors.petrolBorder)),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: MtColors.graphite,
      displayColor: MtColors.graphite,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(color: MtColors.slate500, fontSize: 15),
      border: _inputBorder(MtColors.slate200),
      enabledBorder: _inputBorder(MtColors.slate200),
      focusedBorder: _inputBorder(MtColors.petrol),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MtColors.petrol,
        foregroundColor: MtColors.slate50,
        minimumSize: const Size.fromHeight(MtSizes.primaryButtonHeight),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MtSizes.controlRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MtColors.graphite,
        minimumSize: const Size.fromHeight(MtSizes.controlHeight),
        side: const BorderSide(color: MtColors.slate200),
        backgroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MtSizes.controlRadius),
        ),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(MtSizes.controlRadius),
  borderSide: BorderSide(color: color),
);

/// Monospaced style used for plates, chassis numbers and money.
const mtMono = TextStyle(fontFamily: 'monospace', fontFeatures: []);
