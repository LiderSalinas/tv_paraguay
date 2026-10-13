import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF070D18);
  static const surface = Color(0xFF101B2A);
  static const selected = Color(0xFF142E50);
  static const blue = Color(0xFF2F80ED);
  static const focus = Color(0xFF8DBEFF);
  static const red = Color(0xFFE21C3A);
  static const text = Color(0xFFF5F7FA);
  static const secondary = Color(0xFFB7C4D4);
}

ThemeData buildAppTheme() => ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.blue,
        secondary: AppColors.red,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        onPrimary: Colors.white,
        error: AppColors.red,
      ),
      useMaterial3: true,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: TextStyle(fontFamily: 'Manrope', color: AppColors.text),
        behavior: SnackBarBehavior.floating,
      ),
    );
