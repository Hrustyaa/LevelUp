import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart';
import '../data/levelup_permissions.dart';
import '../focus_experience/focus_exercises.dart';
import '../focus_experience/focus_style.dart';
import 'settings_permissions.dart';

String _tr(DashboardLanguage language, String ru, String en, String kk) =>
    focusTr(language.name, ru, en, kk);

final _squat = focusExercises.firstWhere(
  (exercise) => exercise.id == FocusExerciseId.squat,
);

String _languageName(DashboardLanguage language) => switch (language) {
  DashboardLanguage.ru => 'Русский',
  DashboardLanguage.en => 'English',
  DashboardLanguage.kk => 'Қазақша',
};

/// Settings content only: the existing LevelUpHomeScreen keeps the page's
/// outer ListView, the LevelUp header, and its five-tab bottom navigation.
/// Never manipulates Focus, permissions or selected apps by itself.
class LevelUpSettingsTab extends StatefulWidget {
  const LevelUpSettingsTab({
    super.key,
    required this.language,
    required this.onLanguageChanged,
    this.onManageApps,
    this.onFocusRules,
    this.onOpenPermissions,
    this.onOpenNotifications,
    this.permissionGateway = const AndroidPermissionGateway(),
    this.appVersion,
  });

  final DashboardLanguage language;
  final ValueChanged<DashboardLanguage> onLanguageChanged;
  final Future<void> Function()? onManageApps;
  final VoidCallback? onFocusRules;
  final Future<void> Function()? onOpenPermissions;
  final Future<void> Function()? onOpenNotifications;
  final LevelUpPermissionGateway permissionGateway;
  final String? appVersion;

  @override
  State<LevelUpSettingsTab> createState() => _LevelUpSettingsTabState();
}

class _LevelUpSettingsTabState extends State<LevelUpSettingsTab>
    with WidgetsBindingObserver {
  var _permissionCheck = SettingsPermissionCheck.unchecked;
  int _permissionRead = 0;

  String t(String ru, String en, String kk) => _tr(widget.language, ru, en, kk);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
    }
  }

  Future<void> _refreshPermissions() async {
    final read = ++_permissionRead;
    final check = await readSettingsPermissions(widget.permissionGateway);
    if (mounted && read == _permissionRead && check != _permissionCheck) {
      setState(() => _permissionCheck = check);
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    final next = await showModalBottomSheet<DashboardLanguage>(
      context: context,
      backgroundColor: FocusStyle.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Язык', 'Language', 'Тіл'),
                style: const TextStyle(
                  color: FocusStyle.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in DashboardLanguage.values)
                _SettingsRow(
                  icon: item == widget.language
                      ? Icons.check_circle_outline
                      : Icons.language,
                  title: _languageName(item),
                  selected: item == widget.language,
                  iconColor: item == widget.language
                      ? FocusStyle.accent
                      : FocusStyle.muted,
                  onTap: () => Navigator.pop(sheetContext, item),
                  showArrow: false,
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && next != null && next != widget.language) {
      widget.onLanguageChanged(next);
    }
  }

  Future<void> _openPermissions() async {
    final action = widget.onOpenPermissions;
    if (action == null) return;
    await action();
    if (mounted) await _refreshPermissions();
  }

  String get _unavailable => t('Недоступно', 'Unavailable', 'Қолжетімсіз');

  String? get _permissionDetail {
    if (widget.onOpenPermissions == null) return _unavailable;
    return switch (_permissionCheck) {
      SettingsPermissionCheck.unchecked => t(
        'Не проверено',
        'Not checked',
        'Тексерілмеген',
      ),
      SettingsPermissionCheck.partial => t(
        'Часть не проверена',
        'Some not checked',
        'Кейбірі тексерілмеген',
      ),
      SettingsPermissionCheck.checked => null,
    };
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('levelup_settings_content'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionTitle(t('ОБЩИЕ', 'GENERAL', 'ЖАЛПЫ')),
      _SettingsRow(
        key: const ValueKey('settings_language'),
        icon: Icons.language,
        title: t('Язык', 'Language', 'Тіл'),
        detail: _languageName(widget.language),
        onTap: () => _chooseLanguage(context),
      ),
      const _Separator(),
      _SettingsRow(
        key: const ValueKey('settings_notifications'),
        icon: Icons.notifications_none_outlined,
        title: t('Уведомления', 'Notifications', 'Хабарландырулар'),
        detail: widget.onOpenNotifications == null ? _unavailable : null,
        onTap: widget.onOpenNotifications,
      ),
      const _Separator(),
      _SettingsRow(
        key: const ValueKey('settings_permissions'),
        icon: Icons.shield_outlined,
        title: t('Разрешения', 'Permissions', 'Рұқсаттар'),
        detail: _permissionDetail,
        onTap: widget.onOpenPermissions == null ? null : _openPermissions,
      ),
      const SizedBox(height: 25),
      _SectionTitle(t('ФОКУС', 'FOCUS', 'ФОКУС')),
      _SettingsRow(
        key: const ValueKey('settings_manage_apps'),
        icon: Icons.smartphone_outlined,
        title: t(
          'Управление приложениями',
          'Manage apps',
          'Қолданбаларды басқару',
        ),
        detail: widget.onManageApps == null ? _unavailable : null,
        onTap: widget.onManageApps,
      ),
      const _Separator(),
      _SettingsRow(
        key: const ValueKey('settings_focus_rules'),
        icon: Icons.timer_outlined,
        title: t('Правила фокуса', 'Focus rules', 'Фокус ережелері'),
        detail: widget.onFocusRules == null ? _unavailable : null,
        onTap: widget.onFocusRules,
      ),
      const _Separator(),
      _SettingsRow(
        key: const ValueKey('settings_focus_challenge'),
        icon: Icons.fitness_center_outlined,
        title: t('Задание для доступа', 'Unlock challenge', 'Кіру тапсырмасы'),
        detail: t(
          '${_squat.target} приседаний',
          '${_squat.target} squats',
          '${_squat.target} рет отырып-тұру',
        ),
        onTap: () => _push(
          context,
          LevelUpUnlockChallengeSettingsScreen(language: widget.language),
        ),
      ),
      const SizedBox(height: 25),
      _SectionTitle(t('ИНФОРМАЦИЯ', 'INFORMATION', 'АҚПАРАТ')),
      _SettingsRow(
        key: const ValueKey('settings_privacy'),
        icon: Icons.lock_outline,
        title: t('Конфиденциальность', 'Privacy', 'Құпиялылық'),
        onTap: () => _push(
          context,
          LevelUpPrivacySettingsScreen(language: widget.language),
        ),
      ),
      const _Separator(),
      _SettingsRow(
        key: const ValueKey('settings_about'),
        icon: Icons.info_outline,
        title: t('О LevelUp', 'About LevelUp', 'LevelUp туралы'),
        onTap: () => _push(
          context,
          LevelUpAboutSettingsScreen(
            language: widget.language,
            appVersion: widget.appVersion,
          ),
        ),
      ),
      const SizedBox(height: 20),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: FocusStyle.muted,
      ),
    ),
  );
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, thickness: 1, color: FocusStyle.border);
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.onTap,
    this.iconColor = FocusStyle.muted,
    this.showArrow = true,
    this.selected,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;
  final Color iconColor;
  final bool showArrow;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    enabled: onTap != null,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: FocusStyle.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (detail case final subtitle?) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: FocusStyle.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showArrow && onTap != null) ...[
                const SizedBox(width: 7),
                const Icon(
                  Icons.chevron_right,
                  color: FocusStyle.muted,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _InnerSettingsPage extends StatelessWidget {
  const _InnerSettingsPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusStyle.theme(),
    child: Scaffold(
      backgroundColor: FocusStyle.background,
      appBar: AppBar(
        toolbarHeight: 20 + 2 * MediaQuery.textScalerOf(context).scale(18),
        title: Text(title, maxLines: 2, style: const TextStyle(fontSize: 18)),
        backgroundColor: FocusStyle.background,
        foregroundColor: FocusStyle.text,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [child],
        ),
      ),
    ),
  );
}

class LevelUpUnlockChallengeSettingsScreen extends StatelessWidget {
  const LevelUpUnlockChallengeSettingsScreen({
    super.key,
    required this.language,
  });

  final DashboardLanguage language;

  String t(String ru, String en, String kk) => _tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => _InnerSettingsPage(
    title: t('Задание для доступа', 'Unlock challenge', 'Кіру тапсырмасы'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t(
            'Задание, которое используется при добровольно включённом Focus.',
            'The challenge used when Focus is voluntarily enabled.',
            'Фокус ерікті түрде қосылғандағы тапсырма.',
          ),
          style: const TextStyle(color: FocusStyle.muted),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FocusStyle.surface,
            border: Border.all(color: FocusStyle.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: FocusStyle.accent,
                size: 22,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _squat.name(language.name),
                      style: const TextStyle(
                        color: FocusStyle.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      t(
                        '${_squat.target} повторений',
                        '${_squat.target} repetitions',
                        '${_squat.target} қайталау',
                      ),
                      style: const TextStyle(color: FocusStyle.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        _SectionTitle(
          t('ДРУГИЕ УПРАЖНЕНИЯ', 'OTHER EXERCISES', 'БАСҚА ЖАТТЫҒУЛАР'),
        ),
        for (final exercise in focusExercises.where(
          (exercise) => !exercise.ready,
        )) ...[
          _SettingsRow(
            icon: Icons.lock_outline,
            title: exercise.name(language.name),
            detail: t('Недоступно', 'Unavailable', 'Қолжетімсіз'),
            showArrow: false,
          ),
          const _Separator(),
        ],
        const SizedBox(height: 19),
        _InfoNote(
          t(
            'Фокус можно выключить в любой момент без выполнения задания.',
            'You can turn off Focus at any time without doing the challenge.',
            'Фокусты кез келген уақытта тапсырмасыз өшіруге болады.',
          ),
        ),
      ],
    ),
  );
}

class LevelUpPrivacySettingsScreen extends StatelessWidget {
  const LevelUpPrivacySettingsScreen({super.key, required this.language});

  final DashboardLanguage language;

  String t(String ru, String en, String kk) => _tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => _InnerSettingsPage(
    title: t('Конфиденциальность', 'Privacy', 'Құпиялылық'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InformationSection(
          title: t('Камера', 'Camera', 'Камера'),
          body: t(
            'Камера используется для распознавания позы во время упражнения. Модуль свободных тренировок не сохраняет видео.',
            'The camera is used to detect your pose during an exercise. The free-workout module does not save video.',
            'Камера жаттығуда дене қалпын анықтау үшін қолданылады. Еркін жаттығу модулі бейнені сақтамайды.',
          ),
        ),
        const _Separator(),
        _InformationSection(
          title: t(
            'История тренировок',
            'Workout history',
            'Жаттығулар тарихы',
          ),
          body: t(
            'Результаты самостоятельных тренировок и подходов сохраняются локально на устройстве.',
            'Completed free workouts and sets are stored locally on this device.',
            'Аяқталған еркін жаттығулар мен тәсілдер құрылғыда жергілікті сақталады.',
          ),
        ),
        const _Separator(),
        _InformationSection(
          title: t(
            'Focus и экранное время',
            'Focus and screen time',
            'Фокус және экран уақыты',
          ),
          body: t(
            'Для Focus и статистики использования LevelUp обращается к предоставленным разрешениям Android. Их можно отозвать в системных настройках.',
            'Focus and usage statistics rely on Android permissions you grant. You can revoke them in system settings.',
            'Фокус пен пайдалану статистикасы Android рұқсаттарына сүйенеді. Оларды жүйелік баптаулардан өшіруге болады.',
          ),
        ),
      ],
    ),
  );
}

class LevelUpAboutSettingsScreen extends StatelessWidget {
  const LevelUpAboutSettingsScreen({
    super.key,
    required this.language,
    this.appVersion,
  });

  final DashboardLanguage language;
  final String? appVersion;

  String t(String ru, String en, String kk) => _tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => _InnerSettingsPage(
    title: t('О LevelUp', 'About LevelUp', 'LevelUp туралы'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset('assets/images/levelup_mark.png', width: 32, height: 32),
        const SizedBox(height: 14),
        const Text(
          'LevelUp',
          style: TextStyle(
            color: FocusStyle.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t(
            'Добровольный Focus и самостоятельная физическая активность.',
            'Voluntary Focus and independent physical activity.',
            'Ерікті фокус және дербес дене белсенділігі.',
          ),
          style: const TextStyle(color: FocusStyle.muted),
        ),
        const SizedBox(height: 28),
        _InformationSection(
          title: t('Версия', 'Version', 'Нұсқа'),
          body: appVersion?.trim().isNotEmpty == true
              ? appVersion!.trim()
              : t('Не определена', 'Not available', 'Анықталмаған'),
        ),
      ],
    ),
  );
}

class _InformationSection extends StatelessWidget {
  const _InformationSection({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: FocusStyle.text,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(
            color: FocusStyle.muted,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: FocusStyle.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: FocusStyle.border),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: FocusStyle.muted,
        fontSize: 13,
        height: 1.45,
      ),
    ),
  );
}
