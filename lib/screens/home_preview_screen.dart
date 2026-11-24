import 'package:material_ui/material_ui.dart';

import '../data/levelup_permissions.dart';
import 'levelup_focus_setup_screen.dart';
import 'levelup_welcome_screen.dart' show LevelUpLanguage;

/// Preview placeholder for LevelUp Home screen.
/// Focus remains strictly OFF unless explicitly activated after full implementation.
class HomePreviewScreen extends StatelessWidget {
  const HomePreviewScreen({
    super.key,
    required this.language,
    required this.draft,
    required this.outcome,
  });

  final LevelUpLanguage language;
  final FocusSetupDraft? draft;
  final PermissionsOutcome outcome;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0A0F10);
    const surface = Color(0xFF111718);
    const accent = Color(0xFFC7FA5B);
    const ink = Color(0xFFF7F8F8);
    const muted = Color(0xFFB0B8BA);
    const border = Color(0xFF293334);

    final appCount = draft?.packageIds.length ?? 0;
    final (title, headline, status, description) = switch (language) {
      LevelUpLanguage.en => (
        'LevelUp · Home',
        'Setup completed',
        outcome.skipped
            ? 'Permissions skipped · Focus is OFF'
            : outcome.accessibilityGranted
            ? 'Permissions granted · Focus is OFF (ready to enable)'
            : 'Permissions incomplete · Focus is OFF',
        'Welcome to LevelUp. Focus Mode will be activated here in the full home dashboard.',
      ),
      LevelUpLanguage.ru => (
        'LevelUp · Главная',
        'Настройка завершена',
        outcome.skipped
            ? 'Разрешения пропущены · Фокус ВЫКЛЮЧЕН'
            : outcome.accessibilityGranted
            ? 'Разрешения выданы · Фокус ВЫКЛЮЧЕН (готов к включению)'
            : 'Разрешения неполные · Фокус ВЫКЛЮЧЕН',
        'Добро пожаловать в LevelUp. Управление фокусом появится на главном экране.',
      ),
      LevelUpLanguage.kk => (
        'LevelUp · Басты бет',
        'Баптау аяқталды',
        outcome.skipped
            ? 'Рұқсаттар өткізілді · Фокус ӨШІРУЛІ'
            : outcome.accessibilityGranted
            ? 'Рұқсаттар берілді · Фокус ӨШІРУЛІ (қосуға дайын)'
            : 'Рұқсаттар толық емес · Фокус ӨШІРУЛІ',
        'LevelUp-қа қош келдіңіз. Фокусты басқару басты бетте болады.',
      ),
    };

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: accent,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  if (draft != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configured apps: $appCount',
                            style: const TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Mode: ${draft!.mode.name}, Unlock: ${draft!.unlockMinutes} min',
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
