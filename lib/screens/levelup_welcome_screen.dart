import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

enum LevelUpLanguage { en, ru, kk }

/// First-run welcome only. The parent owns navigation, stored language and
/// onboarding completion. No Android permissions or focus changes here.
class LevelUpWelcomeScreen extends StatefulWidget {
  const LevelUpWelcomeScreen({
    super.key,
    required this.onGetStarted,
    this.initialLanguage = LevelUpLanguage.en,
    this.onLanguageChanged,
    this.markAsset = 'assets/images/levelup_mark.png',
  });

  static const background = Color(0xFF0A0F10);

  final ValueChanged<LevelUpLanguage> onGetStarted;
  final LevelUpLanguage initialLanguage;
  final ValueChanged<LevelUpLanguage>? onLanguageChanged;
  final String markAsset;

  @override
  State<LevelUpWelcomeScreen> createState() => _LevelUpWelcomeScreenState();
}

class _LevelUpWelcomeScreenState extends State<LevelUpWelcomeScreen> {
  static const background = LevelUpWelcomeScreen.background;
  static const surface = Color(0xFF111718);
  static const accent = Color(0xFFC7FA5B);
  static const ink = Color(0xFFF7F8F8);
  static const muted = Color(0xFFB0B8BA);
  static const outline = Color(0xFF293334);
  late LevelUpLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguage;
  }

  @override
  void didUpdateWidget(covariant LevelUpWelcomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLanguage != widget.initialLanguage) {
      _language = widget.initialLanguage;
    }
  }

  _WelcomeCopy get copy => _copy[_language]!;

  void _chooseLanguage(LevelUpLanguage language) {
    if (language == _language) return;
    setState(() => _language = language);
    widget.onLanguageChanged?.call(language);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: accent,
            onPrimary: background,
            surface: surface,
            onSurface: ink,
          ),
        ),
        child: Scaffold(
          backgroundColor: background,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 740;
                final padding = compact ? 12.0 : 20.0;
                final textScaler = MediaQuery.textScalerOf(context);
                final pinActions =
                    constraints.maxHeight >= 560 && textScaler.scale(17) <= 22;
                final actions = Padding(
                  padding: EdgeInsets.only(top: compact ? 12 : 16),
                  child: _actions(context),
                );

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: padding,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _languagePicker(),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _brand(compact),
                                  SizedBox(height: compact ? 10 : 18),
                                  _headline(compact),
                                  SizedBox(height: compact ? 14 : 22),
                                  _feature(
                                    Icons.lock_outline_rounded,
                                    copy.features[0],
                                    compact,
                                  ),
                                  const SizedBox(height: 8),
                                  _feature(
                                    Icons.directions_walk_rounded,
                                    copy.features[1],
                                    compact,
                                  ),
                                  const SizedBox(height: 8),
                                  _feature(
                                    Icons.timer_outlined,
                                    copy.features[2],
                                    compact,
                                  ),
                                  if (!pinActions) actions,
                                ],
                              ),
                            ),
                          ),
                          if (pinActions) actions,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _brand(bool compact) => Column(
    children: [
      ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 0.97,
          child: Image.asset(
            widget.markAsset,
            width: compact ? 88 : 102,
            height: compact ? 59 : 68,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            excludeFromSemantics: true,
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        'LevelUp',
        style: TextStyle(
          color: ink,
          fontSize: compact ? 27 : 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          height: 1.1,
        ),
      ),
    ],
  );

  Widget _headline(bool compact) => Column(
    children: [
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${copy.headline1}\n'),
            TextSpan(
              text: copy.headline2,
              style: const TextStyle(color: accent),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: ink,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 30 : 34,
          height: 1.13,
          letterSpacing: -0.8,
        ),
      ),
      SizedBox(height: compact ? 8 : 12),
      Text(
        copy.description,
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 15, height: 1.42),
      ),
    ],
  );

  Widget _feature(IconData icon, _Feature feature, bool compact) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 9 : 12),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: outline),
    ),
    child: Row(
      children: [
        SizedBox(width: 32, child: Icon(icon, size: 28, color: accent)),
        Container(
          width: 1,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          color: const Color(0xFF354142),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: const TextStyle(
                  color: ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                feature.description,
                style: const TextStyle(color: muted, fontSize: 13, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _actions(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        key: const Key('welcome_get_started'),
        onPressed: () => widget.onGetStarted(_language),
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                copy.start,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_rounded, size: 22),
          ],
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const Key('welcome_how_it_works'),
        onPressed: () => _showHowItWorks(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: Color(0xFF536062)),
          shape: const StadiumBorder(),
        ),
        child: Text(
          copy.how,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  Widget _languagePicker() => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _languageButton('EN', 'English', LevelUpLanguage.en),
      _languageDivider(),
      _languageButton('RU', 'Русский', LevelUpLanguage.ru),
      _languageDivider(),
      _languageButton('KZ', 'Қазақша', LevelUpLanguage.kk),
    ],
  );

  Widget _languageDivider() => Container(width: 1, height: 14, color: outline);

  Widget _languageButton(String label, String name, LevelUpLanguage language) {
    final selected = _language == language;
    return Semantics(
      selected: selected,
      label: name,
      child: TextButton(
        key: Key('welcome_language_$label'),
        onPressed: () => _chooseLanguage(language),
        style: TextButton.styleFrom(
          foregroundColor: selected ? accent : muted,
          minimumSize: const Size(56, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 5),
            Container(
              width: 24,
              height: 2,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHowItWorks(BuildContext context) async {
    final text = copy;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.how,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < text.steps.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: accent,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: background,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        text.steps[i],
                        style: const TextStyle(
                          color: ink,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Text(
              text.control,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: background,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(text.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature {
  const _Feature(this.title, this.description);
  final String title, description;
}

class _WelcomeCopy {
  const _WelcomeCopy({
    required this.headline1,
    required this.headline2,
    required this.description,
    required this.features,
    required this.start,
    required this.how,
    required this.steps,
    required this.control,
    required this.close,
  });
  final String headline1, headline2, description, start, how, control, close;
  final List<_Feature> features;
  final List<String> steps;
}

const _copy = <LevelUpLanguage, _WelcomeCopy>{
  LevelUpLanguage.en: _WelcomeCopy(
    headline1: 'Less scrolling.',
    headline2: 'More living.',
    description: 'Focus is optional. Pause it or turn it off anytime.',
    features: [
      _Feature('Choose apps', 'Pick an app to limit.'),
      _Feature('Do 5 squats', 'It’s up to you whether to try.'),
      _Feature('Get 5 minutes', 'Use the app after the challenge.'),
    ],
    start: 'Get started',
    how: 'How it works',
    close: 'Got it',
    steps: [
      'Choose an app to limit and turn on Focus when you’re ready.',
      'When you open that app, try 5 squats or skip the challenge.',
      'Finish the 5 squats to access the app for 5 minutes.',
    ],
    control:
        'To take a break, turn Focus off. You decide when to turn it back on.',
  ),
  LevelUpLanguage.ru: _WelcomeCopy(
    headline1: 'Меньше скроллинга.',
    headline2: 'Больше жизни.',
    description:
        'Фокус добровольный. Его можно приостановить или выключить в любой момент.',
    features: [
      _Feature('Выбери приложения', 'Укажи приложение для ограничения.'),
      _Feature('Сделай 5 приседаний', 'Задание можно пропустить.'),
      _Feature('Получи 5 минут', 'Доступ откроется после задания.'),
    ],
    start: 'Начать',
    how: 'Как это работает',
    close: 'Понятно',
    steps: [
      'Выбери приложение и включи фокус, когда будешь готов.',
      'При открытии приложения сделай 5 приседаний или пропусти задание.',
      'После 5 приседаний приложение откроется на 5 минут.',
    ],
    control:
        'Чтобы сделать паузу, выключи фокус. Ты сам решаешь, когда включить его снова.',
  ),
  LevelUpLanguage.kk: _WelcomeCopy(
    headline1: 'Телефонға аз уақыт.',
    headline2: 'Өмірге көп уақыт.',
    description:
        'Фокус ерікті. Оны кез келген уақытта кідіртуге немесе өшіруге болады.',
    features: [
      _Feature('Қолданбаларды таңда', 'Шектегің келетін қолданбаны таңда.'),
      _Feature('5 рет отырып-тұр', 'Тапсырмадан бас тарта аласың.'),
      _Feature('5 минут қолжетімділік', 'Тапсырмадан кейін қолданба ашылады.'),
    ],
    start: 'Бастау',
    how: 'Бұл қалай жұмыс істейді?',
    close: 'Түсінікті',
    steps: [
      'Шектегің келетін қолданбаны таңда да, дайын болғанда фокус режимін қос.',
      'Қолданбаны ашқанда 5 рет отырып-тұр немесе тапсырмадан бас тарт.',
      '5 рет отырып-тұрсаң, қолданба 5 минутқа ашылады.',
    ],
    control:
        'Үзіліс керек болса, фокусты өшір. Оны қашан қайта қосатыныңды өзің шешесің.',
  ),
};
