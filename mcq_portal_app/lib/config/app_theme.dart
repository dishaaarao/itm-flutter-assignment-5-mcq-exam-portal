import 'package:flutter/material.dart';

/// One place for colours and text styles.
///
/// Without this, a dozen screens each pick their own hex value and the app
/// looks assembled rather than designed.
class AppTheme {
  const AppTheme._();

  static const Color primary = Color(0xFF2F5BEA);
  static const Color primaryDark = Color(0xFF1E3FA8);
  static const Color accent = Color(0xFF12B76A);
  static const Color danger = Color(0xFFD92D20);
  static const Color warning = Color(0xFFF79009);
  static const Color surface = Color(0xFFF7F8FC);

  /// Palette colours, matching what a student expects from a paper exam.
  static const Color answered = Color(0xFF12B76A);
  static const Color marked = Color(0xFF7A5AF8);
  static const Color unanswered = Color(0xFFE4E7EC);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(primary: primary, error: danger);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF101828),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Color(0xFF101828),
          fontSize: 19,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFEAECF0)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: const BorderSide(color: Color(0xFFD0D5DD)),
          foregroundColor: const Color(0xFF344054),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFEAECF0), thickness: 1),
    );
  }

  /// Colour for a letter grade, so the same grade reads the same everywhere.
  static Color gradeColor(String grade) {
    switch (grade) {
      case 'A+':
      case 'A':
        return accent;
      case 'B+':
      case 'B':
        return primary;
      case 'C':
      case 'D':
        return warning;
      default:
        return danger;
    }
  }
}
