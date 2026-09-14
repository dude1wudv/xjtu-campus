import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Named design tokens — radii, spacing, elevation, motion.
/// Keep navy/cream visual language; avoid magic numbers in feature UIs.
abstract final class AppTokens {
  // —— Radii ——
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
  static const double radiusPill = 999;

  static BorderRadius get borderSm => BorderRadius.circular(radiusSm);
  static BorderRadius get borderMd => BorderRadius.circular(radiusMd);
  static BorderRadius get borderLg => BorderRadius.circular(radiusLg);
  static BorderRadius get borderXl => BorderRadius.circular(radiusXl);
  static BorderRadius get borderPill => BorderRadius.circular(radiusPill);

  // —— Spacing ——
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;
  static const double spaceSection = 32;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(
    spaceXl,
    spaceMd,
    spaceXl,
    spaceSection,
  );

  static const EdgeInsets cardPadding = EdgeInsets.all(spaceLg);

  // —— Elevation / shadows ——
  static List<BoxShadow> get softCardShadow => [
        BoxShadow(
          color: AppColors.ink.withValues(alpha: 0.04),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  // —— Durations ——
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 400);
}
