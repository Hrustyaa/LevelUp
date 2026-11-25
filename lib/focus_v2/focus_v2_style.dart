import 'package:material_ui/material_ui.dart';

abstract final class FocusV2Style {
  static const background = Color(0xFF0A0F10);
  static const surface = Color(0xFF111718);
  static const accent = Color(0xFFC7FA5B);
  static const foreground = Color(0xFFF7F8F8);
  static const secondary = Color(0xFFB0B8BA);
  static const border = Color(0xFF293334);

  static ThemeData theme() => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: background,
      surface: surface,
      onSurface: foreground,
      outline: border,
    ),
  );
}

/// Same language values already used in LevelUp: ru, en, kk.
String focusV2Tr(String language, String ru, String en, String kk) =>
    switch (language) {
      'en' => en,
      'kk' => kk,
      _ => ru,
    };

class FocusV2PrimaryButton extends StatelessWidget {
  const FocusV2PrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
  });
  final String title;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,

    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: FocusV2Style.accent,
        foregroundColor: FocusV2Style.background,
        disabledBackgroundColor: FocusV2Style.border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
  );
}
