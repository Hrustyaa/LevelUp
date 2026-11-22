import 'package:material_ui/material_ui.dart';

/// Design tokens and Material 3 theme configuration for Developer Lab.
abstract final class DevLabTheme {
  static const Color background = Color(0xFF101418);
  static const Color surface = Color(0xFF1C2429);
  static const Color surfaceElevated = Color(0xFF242F35);
  static const Color border = Color(0xFF2A353C);
  static const Color accent = Color(0xFFC7FA5B);
  static const Color accentVariant = Color(0xFFA6D63E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF85919A);
  static const Color textMuted = Color(0xFF556067);

  // Status Colors
  static const Color statusSuccess = Color(0xFFC7FA5B);
  static const Color statusWarning = Color(0xFFFFA726);
  static const Color statusError = Color(0xFFEF5350);
  static const Color statusNeutral = Color(0xFF85919A);
  static const Color statusSpecial = Color(0xFFAB47BC);

  /// Builds the complete Developer Lab theme data.
  static ThemeData get theme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        onPrimary: background,
        secondary: accentVariant,
        onSecondary: background,
        error: statusError,
        onError: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border, width: 1.2),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: textPrimary, fontSize: 24, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 13),
        bodySmall: TextStyle(color: textMuted, fontSize: 11),
      ),
    );
  }
}
