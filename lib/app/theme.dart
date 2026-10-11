import 'package:flutter/material.dart';

/// Palet mengikuti arahan Maybe Finance: whitespace lega, border 1px tipis,
/// tanpa drop shadow berat.
class AppTheme {
  AppTheme._();

  static const _lightBg = Color(0xFFFFFFFF);
  static const _lightSurface = Color(0xFFF8FAFC);
  static const _lightText = Color(0xFF0F172A);
  static const _lightBorder = Color(0xFFE2E8F0);

  static const _darkBg = Color(0xFF090D16);
  static const _darkSurface = Color(0xFF0F1524);
  static const _darkText = Color(0xFFF1F5F9);
  static const _darkBorder = Color(0xFF1E293B);

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: _lightBg,
        surface: _lightSurface,
        text: _lightText,
        border: _lightBorder,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: _darkBg,
        surface: _darkSurface,
        text: _darkText,
        border: _darkBorder,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color text,
    required Color border,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F172A),
      brightness: brightness,
    ).copyWith(
      surface: surface,
      onSurface: text,
      outline: border,
      outlineVariant: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      dividerColor: border,
    );
  }
}
