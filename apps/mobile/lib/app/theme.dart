/// Centralizes this app's theme, typography, and decoration choices that
/// diverge from plain Material defaults (Story 5.2, AD-12).
///
/// This is the **one** place app-level theme/typography/decoration choices
/// live — every other file references [lightTheme]/[darkTheme]/
/// [kMonospaceTextStyle]/[kBadgeCornerRadius]/[kBannerCornerRadius] rather
/// than redefining them inline. Before this story, a `'monospace'`
/// `TextStyle` was hand-duplicated across four call sites and two distinct
/// corner-radius values were hand-duplicated across five — both now defined
/// once, here.
library;

import 'package:flutter/material.dart';

/// Builds a theme for [brightness] — the **one** place light/dark theme
/// properties are set (Review fix): [lightTheme]/[darkTheme] both go through
/// this exact function, so a future property (an `AppBarTheme` override, a
/// `visualDensity`, ...) added here automatically applies to both. This
/// makes the two themes structurally incapable of drifting apart except in
/// brightness — a stronger guarantee than a test that only checks for drift
/// after the fact, since there is no second call site where one could be
/// edited without the other.
ThemeData _buildTheme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
      useMaterial3: true,
    );

/// Light theme — preserves the app's exact indigo seed color (unchanged
/// since Epic 1); only brightness differs from [darkTheme].
final ThemeData lightTheme = _buildTheme(Brightness.light);

/// Dark theme — same indigo seed as [lightTheme], `Brightness.dark` only.
final ThemeData darkTheme = _buildTheme(Brightness.dark);

/// Shared monospace style for raw markdown/code display — the base style
/// every call site previously duplicated as its own `TextStyle` literal.
const TextStyle kMonospaceTextStyle = TextStyle(fontFamily: 'monospace');

/// Corner radius for the smaller badge-style decoration (today's existing
/// value at `conflicts_page.dart`'s conflict badge) — preserved as-is, not
/// unified with [kBannerCornerRadius] (see Story 5.2's non-goals).
const double kBadgeCornerRadius = 4;

/// Corner radius for the larger banner-style decoration (today's existing
/// value at the other four call sites) — preserved as-is, not unified with
/// [kBadgeCornerRadius].
const double kBannerCornerRadius = 6;
