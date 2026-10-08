import 'package:flutter/material.dart';

abstract final class SolarColors {
  static const navy = Color(0xFF233656);
  static const yellow = Color(0xFFF6C445);
  static const coral = Color(0xFFE8553E);
  static const coralText = Color(0xFFA83527);
  static const background = Color(0xFFF6F5F1);
  static const muted = Color(0xFF647084);
  static const border = Color(0xFFE5E5DF);
}

ThemeData solarTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: SolarColors.navy).copyWith(
    primary: SolarColors.navy,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFE9EDF4),
    onPrimaryContainer: SolarColors.navy,
    secondary: SolarColors.navy,
    onSecondary: Colors.white,
    secondaryContainer: SolarColors.yellow,
    onSecondaryContainer: SolarColors.navy,
    tertiary: SolarColors.coralText,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFFFE8E1),
    onTertiaryContainer: SolarColors.coralText,
    surface: Colors.white,
    onSurface: SolarColors.navy,
    onSurfaceVariant: SolarColors.muted,
    outlineVariant: SolarColors.border,
    surfaceContainerHighest: const Color(0xFFF0F1F4),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: SolarColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: SolarColors.navy,
      displayColor: SolarColors.navy,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SolarColors.background,
      foregroundColor: SolarColors.navy,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: SolarColors.border),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: SolarColors.yellow,
      height: 76,
    ),
    chipTheme: base.chipTheme.copyWith(
      side: const BorderSide(color: SolarColors.border),
      selectedColor: SolarColors.yellow,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: SolarColors.yellow,
      foregroundColor: SolarColors.navy,
      elevation: 2,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}
