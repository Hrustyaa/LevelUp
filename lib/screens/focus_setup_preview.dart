import 'package:material_ui/material_ui.dart';

import 'levelup_welcome_screen.dart' show LevelUpLanguage;

class FocusSetupPreview extends StatelessWidget {
  const FocusSetupPreview({
    super.key,
    required this.language,
    required this.packageIds,
  });

  final LevelUpLanguage language;
  final Set<String> packageIds;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0A0F10);
    const accent = Color(0xFFC7FA5B);
    final count = packageIds.length;
    final (title, summary, description) = switch (language) {
      LevelUpLanguage.en => (
        'Focus Setup · Preview',
        count == 0 ? 'App selection skipped' : 'Selected apps: $count',
        'This step is a preview. Go back to change your selection.',
      ),
      LevelUpLanguage.ru => (
        'Настройка фокуса · предпросмотр',
        count == 0 ? 'Выбор приложений пропущен' : 'Выбрано приложений: $count',
        'Здесь появятся настройки фокуса. Можно вернуться и изменить выбор.',
      ),
      LevelUpLanguage.kk => (
        'Фокусты баптау · алдын ала қарау',
        count == 0
            ? 'Қолданба таңдау өткізілді'
            : 'Таңдалған қолданбалар: $count',
        'Мұнда фокус баптаулары болады. Артқа оралып, таңдауыңды өзгерте аласың.',
      ),
    };

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: accent, fontSize: 20),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFA5AFB7)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
