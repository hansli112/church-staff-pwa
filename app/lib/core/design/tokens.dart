import 'package:flutter/material.dart';

/// Design tokens from docs/design-principles.md: neutral colors plus one
/// accent, system font, 17pt body, an 8pt grid.
abstract final class Space {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Minimum tap target: 44pt on iOS, 48dp on Android.
  static double minTap(TargetPlatform platform) =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS ? 44 : 48;
}

abstract final class Radii {
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
}

/// Colors for one appearance. Contrast was checked against [background]
/// and [surface]: text 4.5:1 or better, [accent] and [destructive] as text
/// 4.5:1 or better, [tertiaryLabel] is for disabled text only.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.separator,
    required this.fill,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.destructive,
    required this.success,
  });

  /// Page background behind grouped lists.
  final Color background;

  /// Cells, cards, sheets.
  final Color surface;

  /// Sheets and dialogs above [surface].
  final Color surfaceRaised;
  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color separator;

  /// Search fields, chips, pressed rows.
  final Color fill;
  final Color accent;
  final Color onAccent;

  /// Tinted backgrounds for the accent: selected chips, my-service badges.
  final Color accentSoft;
  final Color destructive;
  final Color success;

  static const light = AppColors(
    background: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    label: Color(0xFF000000),
    secondaryLabel: Color(0xFF5C5C62), // 6.5:1 on white, 5.8:1 on F2F2F7
    tertiaryLabel: Color(0xFF9A9AA0),
    separator: Color(0xFFD1D1D6),
    fill: Color(0xFFE9E9EE),
    accent: Color(0xFF1F5FD1), // 5.9:1 on white
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE3ECFB),
    destructive: Color(0xFFC81E1E), // 5.9:1 on white
    success: Color(0xFF1E7B34),
  );

  static const dark = AppColors(
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF2C2C2E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0xFFAEAEB2), // 7.4:1 on 1C1C1E
    tertiaryLabel: Color(0xFF6C6C70),
    separator: Color(0xFF38383A),
    fill: Color(0xFF2C2C2E),
    accent: Color(0xFF6EA2FF), // 6.4:1 on 1C1C1E
    onAccent: Color(0xFF00194A),
    accentSoft: Color(0xFF1B2B4A),
    destructive: Color(0xFFFF6B61), // 5.9:1 on 1C1C1E
    success: Color(0xFF5BD27A),
  );

  static AppColors of(BuildContext context) => Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 ? this : other ?? this;
}

/// The palette offered for special-event tags. Stored by index; each entry
/// has its own light and dark shade so the label stays readable (4.5:1
/// against the tag background in both appearances).
abstract final class EventColors {
  static const _light = [
    (bg: Color(0xFFFCE4E4), fg: Color(0xFF9B1C1C)), // red
    (bg: Color(0xFFFDEBD3), fg: Color(0xFF8A4B08)), // orange
    (bg: Color(0xFFFBF3C4), fg: Color(0xFF6B5A00)), // yellow
    (bg: Color(0xFFDDF3E2), fg: Color(0xFF1C6B32)), // green
    (bg: Color(0xFFDDEBFB), fg: Color(0xFF1D4F9A)), // blue
    (bg: Color(0xFFEDE3FA), fg: Color(0xFF5B2E99)), // purple
  ];
  static const _dark = [
    (bg: Color(0xFF4A1F1F), fg: Color(0xFFFFB4AB)),
    (bg: Color(0xFF4A3014), fg: Color(0xFFFFC98A)),
    (bg: Color(0xFF423A10), fg: Color(0xFFF2DE7A)),
    (bg: Color(0xFF173D22), fg: Color(0xFF93E0A6)),
    (bg: Color(0xFF172F52), fg: Color(0xFFA9C8FF)),
    (bg: Color(0xFF33214F), fg: Color(0xFFD4BBFF)),
  ];

  static int get count => _light.length;

  static ({Color bg, Color fg}) of(BuildContext context, int index) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = dark ? _dark : _light;
    return palette[index.clamp(0, palette.length - 1)];
  }
}

/// Text styles on top of the system font. Sizes follow the iOS text styles
/// so Dynamic Type and Android font scale both apply through MediaQuery.
abstract final class AppText {
  static const largeTitle = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const title = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const title2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );
  static const title3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );
  static const headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static const body = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const callout = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const subheadline = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const footnote = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
  static const caption2 = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}
