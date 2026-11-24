import 'package:material_ui/material_ui.dart';

/// Same matte Dark Lime palette as the existing LevelUp dashboard.
abstract final class FocusStyle {
  static const background = Color(0xFF0A0F10);
  static const surface = Color(0xFF111718);
  static const accent = Color(0xFFC7FA5B);
  static const text = Color(0xFFF7F8F8);
  static const muted = Color(0xFFB0B8BA);
  static const border = Color(0xFF293334);

  static ThemeData theme() => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: background,
      surface: surface,
      onSurface: text,
      outline: border,
    ),
  );
}

String focusTr(String language, String ru, String en, String kk) =>
    switch (language) {
      'en' => en,
      'kk' => kk,
      _ => ru,
    };

class FocusPrimaryButton extends StatelessWidget {
  const FocusPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
  });
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: FocusStyle.accent,
        foregroundColor: FocusStyle.background,
        disabledBackgroundColor: FocusStyle.border,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
