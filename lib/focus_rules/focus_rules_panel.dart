import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart' show DashboardLanguage;
import '../screens/levelup_focus_setup_screen.dart'
    show FocusCapabilities, FocusMode, FocusSetupDraft;
import 'focus_rules_policy.dart';

const _background = Color(0xFF0A0F10);
const _surface = Color(0xFF111718);
const _accent = Color(0xFFC7FA5B);
const _text = Color(0xFFF7F8F8);
const _secondary = Color(0xFFB0B8BA);
const _border = Color(0xFF293334);

String _t(DashboardLanguage language, String ru, String en, String kk) =>
    switch (language) {
      DashboardLanguage.ru => ru,
      DashboardLanguage.en => en,
      DashboardLanguage.kk => kk,
    };

String _modeName(DashboardLanguage language, FocusMode mode) => switch (mode) {
  FocusMode.alwaysOn => _t(language, 'Постоянно', 'Always on', 'Үнемі'),
  FocusMode.timedSession => _t(
    language,
    'Сеанс',
    'Focus session',
    'Фокус сеансы',
  ),
  FocusMode.customSchedule => _t(
    language,
    'По расписанию',
    'Schedule',
    'Кесте бойынша',
  ),
};

String _minutes(DashboardLanguage language, int value) =>
    '$value ${_t(language, 'мин', 'min', 'мин')}';

String _modeDescription(
  DashboardLanguage language,
  FocusSetupDraft draft,
) => switch (draft.mode) {
  FocusMode.alwaysOn => _t(
    language,
    'До ручного отключения',
    'Until turned off',
    'Қолмен өшіргенше',
  ),
  FocusMode.timedSession =>
    '${_modeName(language, draft.mode)} · ${_minutes(language, draft.sessionMinutes)}',
  FocusMode.customSchedule =>
    '${_modeName(language, draft.mode)} · '
        '${FocusRulesPolicy.clock(draft.startMinute)}–'
        '${FocusRulesPolicy.clock(draft.endMinute)}',
};

ThemeData _theme(BuildContext context) => Theme.of(context).copyWith(
  scaffoldBackgroundColor: _background,
  colorScheme: const ColorScheme.dark(
    primary: _accent,
    onPrimary: _background,
    surface: _surface,
    onSurface: _text,
    outline: _border,
  ),
  dividerColor: _border,
);

/// Place INSIDE the existing LevelUp Focus page (which already owns scrolling,
/// header, bottom navigation and real Android Focus state).
///
/// onSaveDraft MUST persist through the existing parent repository and throw
/// when saving fails. This widget NEVER enables Focus or changes its native gate.
class LevelUpFocusRulesPanel extends StatefulWidget {
  const LevelUpFocusRulesPanel({
    super.key,
    required this.draft,
    required this.language,
    required this.capabilities,
    this.onSaveDraft,
    this.onDisableFocus,
    this.onAccessOptions,
    this.focusActive,
    this.busy = false,
  });

  final FocusSetupDraft draft;
  final DashboardLanguage language;
  final FocusCapabilities capabilities;
  final Future<void> Function(FocusSetupDraft)? onSaveDraft;
  final Future<void> Function()? onDisableFocus;
  final VoidCallback? onAccessOptions;
  final bool? focusActive; // null = actual native state unknown
  final bool busy;

  @override
  State<LevelUpFocusRulesPanel> createState() => _LevelUpFocusRulesPanelState();
}

class _LevelUpFocusRulesPanelState extends State<LevelUpFocusRulesPanel> {
  bool _disabling = false;

  String t(String ru, String en, String kk) => _t(widget.language, ru, en, kk);

  Future<void> _showEditor(_EditorKind kind) async {
    final save = widget.onSaveDraft;
    if (save == null || widget.busy || _disabling) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Theme(
        data: _theme(sheetContext),
        child: _FocusRuleEditor(
          kind: kind,
          initial: widget.draft,
          language: widget.language,
          capabilities: widget.capabilities,
          save: save,
        ),
      ),
    );
  }

  Future<void> _disable() async {
    final callback = widget.onDisableFocus;
    if (callback == null || _disabling) return;
    setState(() => _disabling = true);
    try {
      await callback();
      // Parent receives new native state from its existing gateway.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              t(
                'Не удалось отключить Focus. Повтори попытку.',
                'Could not turn off Focus. Try again.',
                'Фокусты өшіру мүмкін болмады. Қайталап көр.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _disabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final modeDraftOnly = FocusRulesPolicy.unsupportedMode(
      draft,
      widget.capabilities,
    );
    final accessDraftOnly = FocusRulesPolicy.unsupportedAccess(
      draft,
      widget.capabilities,
    );
    final editable = widget.onSaveDraft != null && !widget.busy && !_disabling;
    final status = widget.focusActive == null
        ? t(
            'Статус Focus не проверен',
            'Focus status not checked',
            'Фокус күйі тексерілмеді',
          )
        : widget.focusActive!
        ? t('Focus включён', 'Focus is on', 'Фокус қосулы')
        : t('Focus выключен', 'Focus is off', 'Фокус өшірулі');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t('Правила фокуса', 'Focus rules', 'Фокус ережелері'),
          style: const TextStyle(
            color: _text,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(status, style: const TextStyle(color: _secondary, fontSize: 12)),
        const SizedBox(height: 14),
        Material(
          color: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: _border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SettingsLine(
                key: const ValueKey('focus_rules_mode_row'),
                icon: Icons.calendar_today_outlined,
                title: t('Режим', 'Mode', 'Режим'),
                detail: _modeDescription(widget.language, draft),
                draftOnly: modeDraftOnly,
                draftLabel: t('Черновик', 'Draft', 'Жоба'),
                onTap: editable ? () => _showEditor(_EditorKind.mode) : null,
              ),
              const Divider(
                height: 1,
                indent: 15,
                endIndent: 15,
                color: _border,
              ),
              _SettingsLine(
                key: const ValueKey('focus_rules_access_row'),
                icon: Icons.timer_outlined,
                title: t(
                  'Временный доступ',
                  'Temporary access',
                  'Уақытша рұқсат',
                ),
                detail: _minutes(widget.language, draft.unlockMinutes),
                draftOnly: accessDraftOnly,
                draftLabel: t('Черновик', 'Draft', 'Жоба'),
                onTap: editable ? () => _showEditor(_EditorKind.access) : null,
              ),
              if (widget.onAccessOptions case final open?) ...[
                const Divider(
                  height: 1,
                  indent: 15,
                  endIndent: 15,
                  color: _border,
                ),
                _SettingsLine(
                  key: const ValueKey('focus_rules_access_options'),
                  icon: Icons.fitness_center_rounded,
                  title: t(
                    'Параметры доступа',
                    'Access options',
                    'Қолжетімділік параметрлері',
                  ),
                  detail: t(
                    'Упражнение или отключение фокуса',
                    'Exercise or turn off Focus',
                    'Жаттығу немесе фокусты өшіру',
                  ),
                  draftOnly: false,
                  draftLabel: '',
                  onTap: open,
                ),
              ],
            ],
          ),
        ),
        if (modeDraftOnly || accessDraftOnly || draft.packageIds.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            draft.packageIds.isEmpty
                ? t(
                    'Сначала выбери приложение. Эти параметры пока только черновик.',
                    'Select an app first. These settings are a draft.',
                    'Алдымен қолданбаны таңда. Бұл параметрлер әзірше жоба.',
                  )
                : t(
                    'Часть настроек пока не поддерживается Android-ядром. '
                        'Сохранение черновика не включает ограничения.',
                    'Some settings are not supported by the Android engine yet. '
                        'Saving a draft does not enable restrictions.',
                    'Кейбір баптауларға Android жүйесі әлі қолдау көрсетпейді. '
                        'Жобаны сақтау шектеуді қоспайды.',
                  ),
            style: const TextStyle(
              color: _secondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
        if (widget.focusActive == true) ...[
          const SizedBox(height: 10),
          Text(
            t(
              'Изменения сохраняются для следующего включения. '
                  'Текущий Focus не меняется.',
              'Changes are saved for the next activation. '
                  'Current Focus stays unchanged.',
              'Өзгерістер келесі қосуға сақталады. Ағымдағы Фокус өзгермейді.',
            ),
            style: const TextStyle(
              color: _secondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (widget.onDisableFocus != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('focus_rules_disable'),
              onPressed: widget.busy || _disabling ? null : _disable,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: Text(
                t('Отключить Focus', 'Turn off Focus', 'Фокусты өшіру'),
              ),
              style: TextButton.styleFrom(foregroundColor: _text),
            ),
          ],
        ],
      ],
    );
  }
}

class _SettingsLine extends StatelessWidget {
  const _SettingsLine({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.draftOnly,
    required this.draftLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool draftOnly;
  final String draftLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 21, color: _secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(color: _secondary, fontSize: 12),
                ),
                if (draftOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    draftLabel,
                    style: const TextStyle(color: _secondary, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: _secondary, size: 19),
        ],
      ),
    ),
  );
}

enum _EditorKind { mode, access }

class _FocusRuleEditor extends StatefulWidget {
  const _FocusRuleEditor({
    required this.kind,
    required this.initial,
    required this.language,
    required this.capabilities,
    required this.save,
  });

  final _EditorKind kind;
  final FocusSetupDraft initial;
  final DashboardLanguage language;
  final FocusCapabilities capabilities;
  final Future<void> Function(FocusSetupDraft) save;

  @override
  State<_FocusRuleEditor> createState() => _FocusRuleEditorState();
}

class _FocusRuleEditorState extends State<_FocusRuleEditor> {
  late FocusSetupDraft _draft;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
  }

  String t(String ru, String en, String kk) => _t(widget.language, ru, en, kk);

  void _change(FocusSetupDraft next) => setState(() {
    _draft = next;
    _error = null;
  });

  Future<void> _save() async {
    if (_saving || !FocusRulesPolicy.canSaveDraft(_draft)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_draft);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = t(
            'Не удалось сохранить изменения. Попробуй ещё раз.',
            'Could not save changes. Try again.',
            'Өзгерістер сақталмады. Қайталап көр.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickClock(bool isStart) async {
    final current = isStart ? _draft.startMinute : _draft.endMinute;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _surface,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Theme(
        data: _theme(ctx),
        child: _ClockSheet(
          initial: current,
          title: isStart
              ? t('Начало', 'Start time', 'Басталуы')
              : t('Конец', 'End time', 'Аяқталуы'),
          cancelLabel: t('Отмена', 'Cancel', 'Бас тарту'),
          confirmLabel: t('Выбрать', 'Select', 'Таңдау'),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    _change(
      isStart
          ? _draft.copyWith(startMinute: picked)
          : _draft.copyWith(endMinute: picked),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMode = widget.kind == _EditorKind.mode;
    final unsupported =
        FocusRulesPolicy.unsupportedMode(_draft, widget.capabilities) ||
        FocusRulesPolicy.unsupportedAccess(_draft, widget.capabilities) ||
        _draft.packageIds.isEmpty ||
        (_draft.packageIds.length > 1 && !widget.capabilities.multipleApps);
    final valid = FocusRulesPolicy.canSaveDraft(_draft);
    final size = MediaQuery.sizeOf(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * .83),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                isMode
                    ? t('Режим Focus', 'Focus mode', 'Фокус режимі')
                    : t(
                        'Временный доступ',
                        'Temporary access',
                        'Уақытша рұқсат',
                      ),
                style: const TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isMode
                    ? t(
                        'Когда будет действовать ограничение',
                        'When restrictions should apply',
                        'Шектеу қай уақытта жұмыс істейді',
                      )
                    : t(
                        'Время доступа после выполнения задания',
                        'Access time after a completed task',
                        'Тапсырмадан кейінгі рұқсат уақыты',
                      ),
                style: const TextStyle(color: _secondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isMode) ..._modeBody() else ..._accessBody(),
                      if (!valid) ...[
                        const SizedBox(height: 10),
                        Text(
                          t(
                            'Выбери корректные дни и время в пределах одних суток.',
                            'Select valid days and times within one day.',
                            'Күн мен уақытты бір күннің шегінде дұрыс таңда.',
                          ),
                          style: const TextStyle(
                            color: _secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (unsupported) ...[
                        const SizedBox(height: 12),
                        Text(
                          t(
                            'Эти параметры сохраняются как черновик. '
                                'Пока Android-ядро их не поддерживает, действующий Focus не изменится.',
                            'These settings are saved as a draft. Until the Android engine supports them, '
                                'the active Focus will not change.',
                            'Бұл параметрлер жоба ретінде сақталады. Android жүйесі қолдағанша '
                                'ағымдағы Фокус өзгермейді.',
                          ),
                          style: const TextStyle(
                            color: _secondary,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFFA6A6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('focus_rules_save'),
                  onPressed: _saving || !valid ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _background,
                    disabledBackgroundColor: _border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: _background,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          unsupported
                              ? t(
                                  'Сохранить черновик',
                                  'Save draft',
                                  'Жобаны сақтау',
                                )
                              : t('Сохранить', 'Save', 'Сақтау'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _modeBody() => [
    _choices<FocusMode>(
      options: FocusMode.values,
      current: _draft.mode,
      label: (item) => _modeName(widget.language, item),
      keyFor: (item) => ValueKey('focus_rules_mode_${item.name}'),
      onChange: (item) => _change(_draft.copyWith(mode: item)),
    ),
    if (_draft.mode == FocusMode.timedSession) ...[
      const SizedBox(height: 16),
      _sectionTitle(
        t('Длительность сеанса', 'Session duration', 'Сеанс ұзақтығы'),
      ),
      const SizedBox(height: 9),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final minutes in FocusRulesPolicy.sessionChoices)
            _choiceChip(
              label: _minutes(widget.language, minutes),
              selected: minutes == _draft.sessionMinutes,
              key: ValueKey('focus_rules_session_$minutes'),
              onTap: () => _change(_draft.copyWith(sessionMinutes: minutes)),
            ),
        ],
      ),
    ],
    if (_draft.mode == FocusMode.customSchedule) ...[
      const SizedBox(height: 16),
      _sectionTitle(t('Дни недели', 'Weekdays', 'Апта күндері')),
      const SizedBox(height: 9),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var day = 1; day <= 7; day++)
            _choiceChip(
              key: ValueKey('focus_rules_day_$day'),
              label: _weekday(widget.language, day),
              selected: _draft.weekdays.contains(day),
              onTap: () {
                final days = {..._draft.weekdays};
                if (!days.remove(day)) days.add(day);
                _change(_draft.copyWith(weekdays: days));
              },
            ),
        ],
      ),
      const SizedBox(height: 15),
      _sectionTitle(
        t('Часы ограничения', 'Restriction hours', 'Шектеу уақыты'),
      ),
      const SizedBox(height: 8),
      Material(
        color: _surface,
        child: Column(
          children: [
            _TimeLine(
              key: const ValueKey('focus_rules_start'),
              title: t('Начало', 'Start', 'Басы'),
              time: FocusRulesPolicy.clock(_draft.startMinute),
              onTap: () => _pickClock(true),
            ),
            const Divider(height: 1, color: _border),
            _TimeLine(
              key: const ValueKey('focus_rules_end'),
              title: t('Конец', 'End', 'Аяғы'),
              time: FocusRulesPolicy.clock(_draft.endMinute),
              onTap: () => _pickClock(false),
            ),
          ],
        ),
      ),
      const SizedBox(height: 9),
      Text(
        t(
          'Начало и конец — в пределах одного дня. Часовой пояс телефона.',
          'Start and end must be on the same day. Device local time.',
          'Басы мен соңы бір күн ішінде. Телефонның жергілікті уақыты.',
        ),
        style: const TextStyle(color: _secondary, fontSize: 12),
      ),
    ],
  ];

  List<Widget> _accessBody() => [
    _choices<int>(
      options: FocusRulesPolicy.accessChoices,
      current: _draft.unlockMinutes,
      label: (minutes) => _minutes(widget.language, minutes),
      keyFor: (minutes) => ValueKey('focus_rules_access_$minutes'),
      onChange: (minutes) => _change(_draft.copyWith(unlockMinutes: minutes)),
    ),
    if (!widget.capabilities.configurableAccess) ...[
      const SizedBox(height: 10),
      Text(
        t(
          'Сейчас Focus действительно выдаёт 5 минут доступа. '
              'Остальные значения доступны только как черновик.',
          'The current Focus engine grants 5 minutes. '
              'Other durations are drafts only.',
          'Қазір Фокус 5 минут рұқсат береді. '
              'Басқа ұзақтықтар тек жоба ретінде сақталады.',
        ),
        style: const TextStyle(color: _secondary, fontSize: 12),
      ),
    ],
  ];

  Widget _sectionTitle(String label) => Text(
    label,
    style: const TextStyle(
      color: _text,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Key key,
  }) => ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    onSelected: _saving ? null : (_) => onTap(),
    selectedColor: const Color(0xFF263719),
    showCheckmark: false,
    side: BorderSide(color: selected ? _accent : _border),
    labelStyle: TextStyle(color: selected ? _accent : _text, fontSize: 12),
    backgroundColor: _surface,
  );

  Widget _choices<T>({
    required List<T> options,
    required T current,
    required String Function(T) label,
    required Key Function(T) keyFor,
    required void Function(T) onChange,
  }) => Material(
    color: _surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: _border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i != 0) const Divider(height: 1, color: _border),
          InkWell(
            key: keyFor(options[i]),
            onTap: _saving ? null : () => onChange(options[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label(options[i]),
                      style: const TextStyle(color: _text, fontSize: 14),
                    ),
                  ),
                  Icon(
                    options[i] == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: options[i] == current ? _accent : _secondary,
                    size: 21,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _TimeLine extends StatelessWidget {
  const _TimeLine({
    super.key,
    required this.title,
    required this.time,
    required this.onTap,
  });
  final String title;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: _text, fontSize: 14),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: _accent,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: _secondary, size: 18),
        ],
      ),
    ),
  );
}

String _weekday(DashboardLanguage language, int day) {
  final names = switch (language) {
    DashboardLanguage.ru => ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
    DashboardLanguage.en => ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
    DashboardLanguage.kk => ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'],
  };
  return names[day - 1];
}

/// A small, 24-hour local-time sheet (no device clock, no scheduled jobs).
/// Returns selected minute-of-day only after confirmation.
class _ClockSheet extends StatefulWidget {
  const _ClockSheet({
    required this.initial,
    required this.title,
    required this.cancelLabel,
    required this.confirmLabel,
  });
  final int initial;
  final String title;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_ClockSheet> createState() => _ClockSheetState();
}

class _ClockSheetState extends State<_ClockSheet> {
  late int hour;
  late int minute;

  @override
  void initState() {
    super.initState();
    final safe = widget.initial.clamp(0, 1439);
    hour = safe ~/ 60;
    minute = safe % 60;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: _text,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  value: hour,
                  upper: 23,
                  key: const ValueKey('focus_clock_hour'),
                  onChanged: (n) => setState(() => hour = n),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(':', style: TextStyle(fontSize: 24, color: _text)),
              ),
              Expanded(
                child: _dropdown(
                  value: minute,
                  upper: 59,
                  key: const ValueKey('focus_clock_minute'),
                  onChanged: (n) => setState(() => minute = n),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _border),
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(widget.cancelLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('focus_clock_confirm'),
                  onPressed: () =>
                      Navigator.of(context).pop(hour * 60 + minute),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _background,
                    minimumSize: const Size(0, 48),
                  ),
                  child: Text(widget.confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _dropdown({
    required int value,
    required int upper,
    required Key key,
    required void Function(int) onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        key: key,
        value: value,
        isExpanded: true,
        dropdownColor: _surface,
        style: const TextStyle(color: _text, fontSize: 18),
        items: [
          for (var n = 0; n <= upper; n++)
            DropdownMenuItem(
              value: n,
              child: Text(n.toString().padLeft(2, '0')),
            ),
        ],
        onChanged: (n) {
          if (n != null) onChanged(n);
        },
      ),
    ),
  );
}
