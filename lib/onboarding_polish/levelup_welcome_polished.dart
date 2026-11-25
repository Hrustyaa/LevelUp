import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../ui_polish/levelup_ui.dart';

/// Refined Welcome UI. Parent owns saved language, navigation and first-run
/// completion. This screen never requests permissions or enables Focus.
class LevelUpWelcomePolishedScreen extends StatelessWidget {
  const LevelUpWelcomePolishedScreen({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    required this.onContinue,
    this.markAsset = 'assets/images/levelup_mark.png',
  });

  /// 'ru', 'en', or 'kk'. Read it from the app's EXISTING language state.
  final String language;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback onContinue;
  final String markAsset;

  String t(String ru, String en, String kk) =>
      levelUpText(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => Theme(
    data: LevelUpUi.theme(),
    child: Scaffold(
      backgroundColor: LevelUpUi.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 680;
            return SingleChildScrollView(
              key: const Key('onboarding_scroll'),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0.0, constraints.maxHeight - 44),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _brand(context),
                            SizedBox(height: compact ? 34 : 64),
                            Text(
                              t(
                                'Меньше отвлечений.\nБольше свободы.',
                                'Fewer distractions.\nMore choice.',
                                'Алаңдататын нәрсе аз.\nТаңдау өзіңде.',
                              ),
                              style: TextStyle(
                                fontSize: compact ? 27 : 30,
                                color: LevelUpUi.text,
                                height: 1.17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              t(
                                'Управляй временем в приложениях и двигайся в своём темпе.',
                                'Manage app time and move at your own pace.',
                                'Қолданба уақытын өзің басқар, өз қарқыныңмен қимылда.',
                              ),
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: LevelUpUi.muted,
                              ),
                            ),
                            SizedBox(height: compact ? 24 : 38),
                            _step(
                              Icons.apps_outlined,
                              t(
                                'Выбери приложение',
                                'Choose an app',
                                'Қолданбаны таңда',
                              ),
                              t(
                                'Focus помогает сделать паузу перед входом.',
                                'Focus adds a pause before you open it.',
                                'Focus оны ашпас бұрын кідіріс береді.',
                              ),
                            ),
                            const Divider(color: LevelUpUi.border, height: 1),
                            _step(
                              Icons.directions_walk_outlined,
                              t(
                                'Короткое задание',
                                'A short activity',
                                'Қысқа тапсырма',
                              ),
                              t(
                                '5 приседаний — временный доступ на 5 минут.',
                                '5 squats — 5 minutes of temporary access.',
                                '5 отырып-тұру — 5 минут уақытша қолжетімділік.',
                              ),
                            ),
                            const Divider(color: LevelUpUi.border, height: 1),
                            _step(
                              Icons.toggle_on_outlined,
                              t(
                                'Ты управляешь Focus',
                                'You control Focus',
                                'Focus өз бақылауыңда',
                              ),
                              t(
                                'Его можно отключить без выполнения задания.',
                                'You can turn it off without completing an activity.',
                                'Тапсырма орындамай-ақ өшіруге болады.',
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            const SizedBox(height: 34),
                            LevelUpActionButton(
                              label: t('Начать', 'Get started', 'Бастау'),
                              onPressed: onContinue,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              key: const Key('onboarding_how'),
                              onPressed: () => _explain(context),
                              child: Text(
                                t(
                                  'Как это работает',
                                  'How it works',
                                  'Қалай жұмыс істейді',
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _languages(),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _brand(BuildContext context) => Row(
    children: [
      Image.asset(
        markAsset,
        width: 35,
        height: 35,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.bolt_rounded, color: LevelUpUi.lime, size: 30),
      ),
      const SizedBox(width: 8),
      const Text(
        'LevelUp',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: LevelUpUi.text,
        ),
      ),
    ],
  );

  Widget _step(IconData icon, String title, String description) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Icon(icon, size: 22, color: LevelUpUi.muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  color: LevelUpUi.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: LevelUpUi.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _languages() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _languageButton('RU', 'ru'),
      _languageButton('KZ', 'kk'),
      _languageButton('EN', 'en'),
    ],
  );

  Widget _languageButton(String label, String code) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Semantics(
      selected: language == code,
      child: TextButton(
        key: Key('onboarding_language_$code'),
        onPressed: () => onLanguageChanged(code),
        style: TextButton.styleFrom(
          minimumSize: const Size(60, 48),
          foregroundColor: language == code ? LevelUpUi.lime : LevelUpUi.muted,
        ),
        child: Text(label),
      ),
    ),
  );

  Future<void> _explain(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: LevelUpUi.surface,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              'Как работает LevelUp',
              'How LevelUp works',
              'LevelUp қалай жұмыс істейді',
            ),
            style: const TextStyle(
              color: LevelUpUi.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            t(
              'Выбери одно приложение, которое хочешь ограничить. '
                  'Предоставь нужные разрешения только при согласии. '
                  'Focus предложит 5 приседаний для временного доступа. '
                  'Самостоятельные тренировки не открывают приложения. '
                  'Ты всегда можешь отключить Focus.',
              'Choose one app to limit. Grant permissions only when '
                  'you agree. Focus offers 5 squats for temporary access. '
                  'Independent workouts do not unlock apps. '
                  'You can always disable Focus.',
              'Шектейтін бір қолданбаны таңда. Рұқсаттарды тек өз '
                  'келісіміңмен бер. Focus уақытша қолжетімділік үшін '
                  '5 отырып-тұру ұсынады. Еркін жаттығулар қолданбаларды '
                  'ашпайды. Focus режимін әрқашан өшіре аласың.',
            ),
            style: const TextStyle(
              color: LevelUpUi.muted,
              fontSize: 14,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 24),
          LevelUpActionButton(
            label: t('Понятно', 'Got it', 'Түсінікті'),
            onPressed: () => Navigator.pop(sheet),
          ),
        ],
      ),
    ),
  );
}
