import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_page.dart';

/// Brand colours: orange surfaces and actions, purple symbols.
class Brand {
  static const orange = Color(0xFFF97316);
  static const orangeDark = Color(0xFFC2410C);
  static const orangeSoft = Color(0xFFFFEDD5);
  static const cream = Color(0xFFFFF7ED);
  static const purple = Color(0xFF7C3AED);
  static const purpleSoft = Color(0xFFEDE9FE);
  static const ink = Color(0xFF1C1917);
  static const muted = Color(0xFF78716C);
  static const line = Color(0xFFFED7AA);
  static const green = Color(0xFF15803D);
  static const red = Color(0xFFDC2626);
}

void main() => runApp(const BelegGuardApp());

class BelegGuardApp extends StatelessWidget {
  const BelegGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.orange,
      primary: Brand.orange,
      onPrimary: Colors.white,
      secondary: Brand.purple,
      surface: Colors.white,
      onSurface: Brand.ink,
      error: Brand.red,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return MaterialApp(
      title: 'BelegGuard',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: Brand.cream,
        textTheme: base.textTheme.apply(fontFamily: GoogleFonts.inter().fontFamily, bodyColor: Brand.ink, displayColor: Brand.ink),
        iconTheme: const IconThemeData(color: Brand.purple),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Brand.line),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Brand.ink,
            side: const BorderSide(color: Brand.line, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Brand.cream,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.line)),
          enabledBorder:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Brand.orange, width: 2)),
        ),
      ),
      home: const HomePage(),
    );
  }
}
