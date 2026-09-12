import 'package:flutter/material.dart';

/// Centralised Material 3 theming for REmind.
///
/// The seed colour is drawn from the REmind logo's blue-purple gradient so
/// generated Material tones stay on-brand.
class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF5338FC);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );
}
