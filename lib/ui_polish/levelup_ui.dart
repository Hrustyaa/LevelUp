import 'package:material_ui/material_ui.dart';

/// Small, reusable visual primitives. No timers, storage, network or focus calls.
abstract final class LevelUpUi {
  static const background = Color(0xFF0A0F10);
  static const surface = Color(0xFF111718);
  static const lime = Color(0xFFC7FA5B);
  static const text = Color(0xFFF7F8F8);
  static const muted = Color(0xFFB0B8BA);
  static const border = Color(0xFF293334);

  static ThemeData theme() => ThemeData.dark(useMaterial3: true).copyWith(
    scaffoldBackgroundColor: background,
    dividerColor: border,
    colorScheme: const ColorScheme.dark(
      primary: lime,
      onPrimary: background,
      surface: surface,
      onSurface: text,
      outline: border,
    ),
  );
}

String levelUpText(String language, String ru, String en, String kk) =>
    switch (language) {
      'en' => en,
      'kk' => kk,
      _ => ru,
    };

class LevelUpActionButton extends StatelessWidget {
  const LevelUpActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: secondary
        ? OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              foregroundColor: LevelUpUi.text,
              side: const BorderSide(color: LevelUpUi.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(label),
          )
        : FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              backgroundColor: LevelUpUi.lime,
              foregroundColor: LevelUpUi.background,
              disabledBackgroundColor: LevelUpUi.border,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
  );
}

/// Honest empty/error/loading states; callers provide real status and callbacks.
class LevelUpContentState extends StatelessWidget {
  const LevelUpContentState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
    decoration: BoxDecoration(
      color: LevelUpUi.surface,
      border: Border.all(color: LevelUpUi.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: LevelUpUi.lime,
            ),
          )
        else
          Icon(icon, size: 28, color: LevelUpUi.muted),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LevelUpUi.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LevelUpUi.muted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          LevelUpActionButton(label: actionLabel!, onPressed: onAction),
        ],
      ],
    ),
  );
}

/// One consistent confirmation sheet. No destructive action is taken until
/// the user explicitly confirms. Returns false for Android Back/dismiss.
Future<bool> showLevelUpConfirmSheet({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool isDangerous = false,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: LevelUpUi.surface,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: LevelUpUi.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: LevelUpUi.muted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          LevelUpActionButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(sheetContext).pop(true),
            secondary: isDangerous,
          ),
          const SizedBox(height: 8),
          LevelUpActionButton(
            label: cancelLabel,
            secondary: !isDangerous,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    ),
  );
  return confirmed ?? false;
}
