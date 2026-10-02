import 'package:flutter/material.dart';

import 'tokens.dart';

/// The app theme for one appearance. Light and dark follow the system;
/// there is no in-app switch (docs/design-principles.md).
ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.label,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.destructive,
    onError: c.onAccent,
    surface: c.surface,
    onSurface: c.label,
    onSurfaceVariant: c.secondaryLabel,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceRaised,
    surfaceContainerHighest: c.fill,
    outline: c.separator,
    outlineVariant: c.separator,
  );
  final text = const TextTheme(
    displaySmall: AppText.largeTitle,
    headlineMedium: AppText.title,
    headlineSmall: AppText.title2,
    titleLarge: AppText.title3,
    titleMedium: AppText.headline,
    titleSmall: AppText.subheadline,
    bodyLarge: AppText.body,
    bodyMedium: AppText.callout,
    bodySmall: AppText.footnote,
    labelLarge: AppText.headline,
    labelMedium: AppText.footnote,
    labelSmall: AppText.caption2,
  ).apply(bodyColor: c.label, displayColor: c.label);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerTheme: DividerThemeData(
      color: c.separator,
      thickness: 0.5,
      space: 0.5,
    ),
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.label,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: AppText.headline.copyWith(color: c.label),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accentSoft,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => AppText.caption.copyWith(
          color: s.contains(WidgetState.selected) ? c.accent : c.secondaryLabel,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? c.accent : c.secondaryLabel,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.tertiaryLabel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.l)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceRaised,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: brightness == Brightness.dark
          ? c.surfaceRaised
          : const Color(0xFF2C2C2E),
      contentTextStyle: AppText.subheadline.copyWith(color: Colors.white),
      actionTextColor: AppColors.dark.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.m),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.fill,
      hintStyle: AppText.body.copyWith(color: c.secondaryLabel),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.m),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.m),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.m),
        borderSide: BorderSide(color: c.destructive, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        textStyle: AppText.headline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.m),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: const Size(48, 48),
        textStyle: AppText.body,
      ),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: c.surface,
      textColor: c.label,
      iconColor: c.secondaryLabel,
      titleTextStyle: AppText.body.copyWith(color: c.label),
      subtitleTextStyle: AppText.subheadline.copyWith(color: c.secondaryLabel),
      minTileHeight: 48,
    ),
  );
}
