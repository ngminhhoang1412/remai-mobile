import 'package:flutter/material.dart';

/// Colours from remai-central-specs/designs/design-tokens.md (light theme only for the MVP).
abstract final class AppColors {
  static const bg = Color(0xFFFFFFFF);
  static const bgSidebar = Color(0xFFF7F7F5);
  static const bgHover = Color(0xFFEFEFED);
  static const bgSelected = Color(0xFFE8E8E6);
  static const text = Color(0xFF37352F);
  static const textMuted = Color(0xFF787774);
  static const textFaint = Color(0xFFACABA9);
  static const border = Color(0xFFE9E9E7);
  static const accent = Color(0xFF2383E2);
  static const danger = Color(0xFFE03E3E);
  static const success = Color(0xFF0F7B6C);
  static const codeBg = Color(0xFFF7F6F3);
  static const overlay = Color(0x660F0F0F);
}

/// `space-1` … `space-6`.
abstract final class Space {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
}

abstract final class Radii {
  static const sm = 4.0;
  static const md = 8.0;
}

/// Mobile type scale.
abstract final class FontSizes {
  static const title = 30.0;
  static const h1 = 26.0;
  static const h2 = 22.0;
  static const h3 = 19.0;
  static const body = 16.0;
  static const small = 14.0;
  static const code = 14.0;
}

/// `font-mono`: Menlo on iOS, monospace on Android.
const String monoFamily = 'monospace';
const List<String> monoFallback = ['Menlo', 'Courier'];

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      error: AppColors.danger,
      surface: AppColors.bg,
      onSurface: AppColors.text,
      outline: AppColors.border,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accent, width: 1.5)),
      hintStyle: TextStyle(color: AppColors.textFaint),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : null),
      side: const BorderSide(color: AppColors.textMuted, width: 1.5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: AppColors.overlay,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.bg, surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(color: AppColors.bg, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
