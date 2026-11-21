// Global look: colours, theme and small formatting helpers used by every component.
//
// Direction: a sober audit / finance tool. Paper and ink, one dark navy accent,
// and colour only where it carries meaning (ok / warning / blocked).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  // Neutrals
  static const paper = Color(0xFFF6F6F3); // page background
  static const surface = Colors.white; // cards
  static const ink = Color(0xFF16181D); // text
  static const muted = Color(0xFF6B6F76); // secondary text
  static const line = Color(0xFFE3E3DE); // borders, dividers

  // The one accent: actions, links, active state
  static const accent = Color(0xFF1F3A5F);
  static const accentSoft = Color(0xFFE8EDF3);

  // Status colours – only for meaning
  static const ok = Color(0xFF1E6B45);
  static const okSoft = Color(0xFFE6F2EB);
  static const warn = Color(0xFF8A5A00);
  static const warnSoft = Color(0xFFFBF1DC);
  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFCE9E7);
}

/// "12.34 €", or "—" when the value is missing.
String money(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)} €';

/// Heading style for page and card titles.
TextStyle headline(double size) =>
    GoogleFonts.ibmPlexSans(fontSize: size, fontWeight: FontWeight.w600, color: Brand.ink, letterSpacing: -0.2);

/// Monospace for amounts, codes, timestamps and quoted evidence.
TextStyle mono({double size = 12, Color color = Brand.ink}) => GoogleFonts.ibmPlexMono(fontSize: size, color: color);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.accent,
    primary: Brand.accent,
    onPrimary: Colors.white,
    secondary: Brand.accent,
    surface: Brand.surface,
    onSurface: Brand.ink,
    error: Brand.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final radius = BorderRadius.circular(8);
  return base.copyWith(
    scaffoldBackgroundColor: Brand.paper,
    textTheme: base.textTheme.apply(
      fontFamily: GoogleFonts.ibmPlexSans().fontFamily,
      bodyColor: Brand.ink,
      displayColor: Brand.ink,
    ),
    iconTheme: const IconThemeData(color: Brand.muted, size: 20),
    dividerColor: Brand.line,
    cardTheme: CardThemeData(
      color: Brand.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: Brand.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Brand.line,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink,
        side: const BorderSide(color: Brand.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Brand.accent)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.surface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Brand.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Brand.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Brand.accent, width: 1.5),
      ),
    ),
  );
}
