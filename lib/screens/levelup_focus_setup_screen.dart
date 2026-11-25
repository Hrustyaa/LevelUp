import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android_app_catalog.dart';
import 'levelup_welcome_screen.dart';

enum FocusMode { alwaysOn, timedSession, customSchedule }

/// Draft only. This model does not enable the Android gate or start timers.
/// ISO weekday numbers: Monday=1, Sunday=7. Clock values are local minutes.
@immutable
class FocusSetupDraft {
  FocusSetupDraft({
    required Set<String> packageIds,
    this.mode = FocusMode.alwaysOn,
    this.unlockMinutes = FocusCapabilities.defaultAccessMinutes,
    this.sessionMinutes = 60,
    Set<int> weekdays = const {1, 2, 3, 4, 5},
    this.startMinute = 540,
    this.endMinute = 1020,
  }) : packageIds = Set.unmodifiable(packageIds),
       weekdays = Set.unmodifiable(weekdays);

  final Set<String> packageIds;
  final FocusMode mode;
  final int unlockMinutes, sessionMinutes, startMinute, endMinute;
  final Set<int> weekdays;

  bool get isValid =>
      packageIds.isNotEmpty &&
      packageIds.every((id) => id.trim().isNotEmpty) &&
      hasValidRules;

  bool get hasValidRules =>
      const [3, 5, 10, 15].contains(unlockMinutes) &&
      (mode != FocusMode.timedSession ||
          const [15, 30, 60, 120].contains(sessionMinutes)) &&
      (mode != FocusMode.customSchedule ||
          (weekdays.isNotEmpty &&
              weekdays.every((d) => d >= 1 && d <= 7) &&
              startMinute >= 0 &&
              endMinute < 1440 &&
              startMinute < endMinute));

  FocusSetupDraft copyWith({
    Set<String>? packageIds,
    FocusMode? mode,
    int? unlockMinutes,
    int? sessionMinutes,
    Set<int>? weekdays,
    int? startMinute,
    int? endMinute,
  }) => FocusSetupDraft(
    packageIds: packageIds ?? this.packageIds,
    mode: mode ?? this.mode,
    unlockMinutes: unlockMinutes ?? this.unlockMinutes,
    sessionMinutes: sessionMinutes ?? this.sessionMinutes,
    weekdays: weekdays ?? this.weekdays,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
  );

  Map<String, Object> toJson() => {
    'packageIds': packageIds.toList()..sort(),
    'mode': mode.name,
    'unlockMinutes': unlockMinutes,
    'sessionMinutes': sessionMinutes,
    'weekdays': weekdays.toList()..sort(),
    'startMinute': startMinute,
    'endMinute': endMinute,
  };
}

/// Supply true only after the corresponding backend behavior is implemented
/// and tested. Never infer support just from the presence of this UI.
@immutable
class FocusCapabilities {
  const FocusCapabilities({
    this.multipleApps = false,
    this.timedSession = false,
    this.customSchedule = false,
    this.configurableAccess = false,
  });
  static const defaultAccessMinutes = 5;
  final bool multipleApps, timedSession, customSchedule, configurableAccess;

  bool supports(FocusSetupDraft d) =>
      d.isValid &&
      (multipleApps || d.packageIds.length == 1) &&
      (d.mode != FocusMode.timedSession || timedSession) &&
      (d.mode != FocusMode.customSchedule || customSchedule) &&
      (configurableAccess || d.unlockMinutes == defaultAccessMinutes);
}

/// First-run Step 2. Receives real catalog entries from the parent.
/// onContinue returns a validated draft, never activates Focus itself.
class LevelUpFocusSetupScreen extends StatefulWidget {
  const LevelUpFocusSetupScreen({
    super.key,
    required this.selectedApps,
    required this.onContinue,
    required this.onSkip,
    required this.onBack,
    this.onEditApps,
    this.onDraftChanged,
    this.initialDraft,
    this.language = LevelUpLanguage.en,
    this.capabilities = const FocusCapabilities(),
  });

  final List<SelectableApp> selectedApps;
  final LevelUpLanguage language;
  final FocusSetupDraft? initialDraft;
  final FocusCapabilities capabilities;
  final ValueChanged<FocusSetupDraft> onContinue;
  final ValueChanged<FocusSetupDraft>? onDraftChanged;
  final VoidCallback onSkip, onBack;
  final VoidCallback? onEditApps;

  @override
  State<LevelUpFocusSetupScreen> createState() => _FocusSetupState();
}

class _FocusSetupState extends State<LevelUpFocusSetupScreen> {
  static const bg = Color(0xFF0A0F10),
      surface = Color(0xFF111718),
      selectedSurface = Color(0xFF182119),
      accent = Color(0xFFC7FA5B),
      ink = Color(0xFFF7F8F8),
      muted = Color(0xFFB0B8BA),
      border = Color(0xFF293334);
  late FocusSetupDraft _draft;
  final _scroll = ScrollController();
  Set<String> get _ids => widget.selectedApps
      .map((a) => a.packageId)
      .where((id) => id.isNotEmpty)
      .toSet();
  _Strings get s => _strings[widget.language]!;
  Duration get _motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 160);

  @override
  void initState() {
    super.initState();
    _draft = (widget.initialDraft ?? FocusSetupDraft(packageIds: _ids))
        .copyWith(packageIds: _ids);
  }

  @override
  void didUpdateWidget(covariant LevelUpFocusSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _draft = _draft.copyWith(packageIds: _ids);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _change(FocusSetupDraft next) {
    HapticFeedback.selectionClick();
    setState(() => _draft = next);
    widget.onDraftChanged?.call(next);
  }

  void _leave(VoidCallback action) {
    FocusScope.of(context).unfocus();
    action();
  }

  String _clock(int minute) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  Future<void> _pickTime(bool start) async {
    final old = start ? _draft.startMinute : _draft.endMinute;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: old ~/ 60, minute: old % 60),
      helpText: start ? s.start : s.end,
      cancelText: s.cancel,
      confirmText: s.done,
    );
    if (!mounted || time == null) return;
    final minute = time.hour * 60 + time.minute;
    _change(
      start
          ? _draft.copyWith(startMinute: minute)
          : _draft.copyWith(endMinute: minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Theme(
        data: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: accent,
            onPrimary: bg,
            surface: surface,
            onSurface: ink,
            outline: border,
          ),
        ),
        child: Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, limits) {
                final footerInList =
                    limits.maxHeight < 440 ||
                    MediaQuery.textScalerOf(context).scale(16) > 23;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 540),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _header(),
                          Expanded(
                            child: RawScrollbar(
                              controller: _scroll,
                              thickness: 3,
                              radius: const Radius.circular(4),
                              thumbColor: border,
                              child: ListView(
                                controller: _scroll,
                                padding: const EdgeInsets.only(
                                  top: 22,
                                  bottom: 12,
                                ),
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      text: s.title1,
                                      children: [
                                        TextSpan(
                                          text: s.title2,
                                          style: const TextStyle(color: accent),
                                        ),
                                      ],
                                    ),
                                    style: const TextStyle(
                                      color: ink,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -.7,
                                      height: 1.18,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _muted(s.subtitle, size: 15),
                                  const SizedBox(height: 20),
                                  _appsCard(),
                                  const SizedBox(height: 20),
                                  _section(s.modeTitle, s.modeHint),
                                  const SizedBox(height: 10),
                                  _modeTile(
                                    FocusMode.alwaysOn,
                                    Icons.all_inclusive_rounded,
                                    s.always,
                                    s.alwaysHint,
                                  ),
                                  _modeTile(
                                    FocusMode.timedSession,
                                    Icons.schedule_rounded,
                                    s.session,
                                    s.sessionHint,
                                  ),
                                  if (_draft.mode ==
                                      FocusMode.timedSession) ...[
                                    _panel(
                                      s.sessionLength,
                                      _minutes(
                                        [15, 30, 60, 120],
                                        _draft.sessionMinutes,
                                        (v) => _change(
                                          _draft.copyWith(sessionMinutes: v),
                                        ),
                                        hours: true,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  _modeTile(
                                    FocusMode.customSchedule,
                                    Icons.calendar_today_outlined,
                                    s.schedule,
                                    s.scheduleHint,
                                  ),
                                  if (_draft.mode == FocusMode.customSchedule)
                                    _schedulePanel(),
                                  const SizedBox(height: 14),
                                  _section(
                                    s.accessTitle,
                                    widget.capabilities.configurableAccess
                                        ? s.accessHint
                                        : s.fixedAccessHint,
                                  ),
                                  const SizedBox(height: 12),
                                  _minutes(
                                    [3, 5, 10, 15],
                                    _draft.unlockMinutes,
                                    (v) => _change(
                                      _draft.copyWith(unlockMinutes: v),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  if (_draft.isValid &&
                                      !widget.capabilities.supports(_draft))
                                    _notice(
                                      Icons.info_outline_rounded,
                                      s.notSupported,
                                    ),
                                  if (footerInList) _footer(),
                                ],
                              ),
                            ),
                          ),
                          if (!footerInList) _footer(),
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

  Widget _header() => Column(
    children: [
      Row(
        children: [
          IconButton(
            tooltip: s.back,
            onPressed: () => _leave(widget.onBack),
            icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 23),
          ),
          Expanded(
            child: Text(
              s.step,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: .5,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
      Row(
        children: [
          for (int i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < 2 ? accent : border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _muted(String text, {double size = 13}) => Text(
    text,
    style: TextStyle(color: muted, fontSize: size, height: 1.4),
  );
  Widget _heading(String t, {double size = 17}) => Text(
    t,
    style: TextStyle(
      color: ink,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );
  Widget _section(String title, String hint) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [_heading(title), const SizedBox(height: 4), _muted(hint)],
  );
  BoxDecoration _card({bool selected = false}) => BoxDecoration(
    color: selected ? selectedSurface : surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: selected ? accent : border),
  );

  Widget _appsCard() {
    final apps = <String, SelectableApp>{
      for (final a in widget.selectedApps) a.packageId: a,
    }.values;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heading(s.apps),
                    const SizedBox(height: 3),
                    _muted(s.appCount(_ids.length)),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _leave(widget.onEditApps ?? widget.onBack),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: const BorderSide(color: border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(48, 44),
                ),
                child: Text(s.edit),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (apps.isEmpty)
            _muted(s.emptyApps)
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final app in apps)
                  Tooltip(
                    message: app.name,
                    child: Semantics(
                      label: app.name,
                      image: true,
                      child: _appIcon(app),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _appIcon(SelectableApp a) {
    final fallback = Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: border,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(Icons.apps_rounded, color: muted, size: 23),
    );
    final bytes = a.icon;
    if (bytes == null || bytes.isEmpty) return fallback;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.5;
    final pixelSize = (42 * dpr).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        bytes,
        width: 42,
        height: 42,
        cacheWidth: pixelSize,
        cacheHeight: pixelSize,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _modeTile(FocusMode mode, IconData icon, String title, String hint) {
    final checked = _draft.mode == mode;
    void tap() => _change(_draft.copyWith(mode: mode));
    return Padding(
      key: ValueKey('mode_${mode.name}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        checked: checked,
        inMutuallyExclusiveGroup: true,
        onTap: tap,
        label: '$title. $hint',
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: _motion,
            decoration: _card(selected: checked),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: tap,
                splashColor: const Color(0x1AC7FA5B),
                highlightColor: const Color(0x0AC7FA5B),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 29,
                        child: Icon(
                          icon,
                          size: 25,
                          color: checked ? accent : muted,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30,
                        color: border,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heading(title, size: 15),
                            const SizedBox(height: 4),
                            _muted(hint),
                          ],
                        ),
                      ),
                      const SizedBox(width: 9),
                      Icon(
                        checked
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 23,
                        color: checked ? accent : muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(String title, Widget child) => Container(
    decoration: _card(),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_heading(title, size: 14), const SizedBox(height: 10), child],
    ),
  );

  Widget _minutes(
    List<int> values,
    int current,
    ValueChanged<int> onChanged, {
    bool hours = false,
  }) => LayoutBuilder(
    builder: (context, c) {
      final columns =
          c.maxWidth < 310 || MediaQuery.textScalerOf(context).scale(14) > 18
          ? 2
          : 4;
      final width = (c.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in values)
            SizedBox(
              width: width,
              child: _choice(
                key: ValueKey('${hours ? 'session' : 'access'}_$v'),
                label: hours && v % 60 == 0 ? s.hours(v ~/ 60) : s.minutes(v),
                selected: current == v,
                onTap: () => onChanged(v),
              ),
            ),
        ],
      );
    },
  );

  Widget _choice({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => Semantics(
    selected: selected,
    button: true,
    child: AnimatedContainer(
      key: key,
      duration: _motion,
      decoration: BoxDecoration(
        color: selected ? accent : surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: selected ? accent : border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 11),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? bg : ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _schedulePanel() => _panel(
    s.days,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (int i = 1; i <= 7; i++)
              SizedBox(
                width: 48,
                child: _choice(
                  key: ValueKey('day_$i'),
                  label: s.weekdays[i - 1],
                  selected: _draft.weekdays.contains(i),
                  onTap: () {
                    final days = {..._draft.weekdays};
                    if (!days.add(i)) days.remove(i);
                    _change(_draft.copyWith(weekdays: days));
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _timeRow(s.start, _draft.startMinute, true),
        _timeRow(s.end, _draft.endMinute, false),
        const SizedBox(height: 6),
        _muted(s.sameDay),
        if (_draft.weekdays.isEmpty ||
            _draft.startMinute >= _draft.endMinute) ...[
          const SizedBox(height: 8),
          Text(
            s.invalidSchedule,
            style: const TextStyle(color: Color(0xFFFFB4AB), fontSize: 13),
          ),
        ],
      ],
    ),
  );
  Widget _timeRow(String label, int minute, bool start) => Row(
    children: [
      Expanded(child: _muted(label)),
      TextButton(
        key: ValueKey(start ? 'start_time' : 'end_time'),
        onPressed: () => _pickTime(start),
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(48, 48),
        ),
        child: Text(_clock(minute)),
      ),
    ],
  );

  Widget _notice(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: muted, size: 19),
        const SizedBox(width: 8),
        Expanded(child: _muted(text, size: 12)),
      ],
    ),
  );

  Widget _footer() => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _notice(Icons.verified_user_outlined, s.safety),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('focus_continue'),
            onPressed: _draft.isValid
                ? () => _leave(() => widget.onContinue(_draft))
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: bg,
              disabledBackgroundColor: border,
              disabledForegroundColor: muted,
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    s.next,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('focus_skip'),
          onPressed: () => _leave(widget.onSkip),
          style: TextButton.styleFrom(
            foregroundColor: muted,
            minimumSize: const Size(48, 44),
          ),
          child: Text(s.skip),
        ),
      ],
    ),
  );
}

class _Strings {
  const _Strings(
    this.language, {
    required this.step,
    required this.title1,
    required this.title2,
    required this.subtitle,
    required this.apps,
    required this.edit,
    required this.emptyApps,
    required this.modeTitle,
    required this.modeHint,
    required this.always,
    required this.alwaysHint,
    required this.session,
    required this.sessionHint,
    required this.schedule,
    required this.scheduleHint,
    required this.sessionLength,
    required this.accessTitle,
    required this.accessHint,
    required this.fixedAccessHint,
    required this.days,
    required this.weekdays,
    required this.start,
    required this.end,
    required this.sameDay,
    required this.invalidSchedule,
    required this.safety,
    required this.notSupported,
    required this.next,
    required this.skip,
    required this.back,
    required this.done,
    required this.cancel,
  });
  final LevelUpLanguage language;
  final String step,
      title1,
      title2,
      subtitle,
      apps,
      edit,
      emptyApps,
      modeTitle,
      modeHint,
      always,
      alwaysHint,
      session,
      sessionHint,
      schedule,
      scheduleHint,
      sessionLength,
      accessTitle,
      accessHint,
      fixedAccessHint,
      days,
      start,
      end,
      sameDay,
      invalidSchedule,
      safety,
      notSupported,
      next,
      skip,
      back,
      done,
      cancel;
  final List<String> weekdays;
  String minutes(int n) => switch (language) {
    LevelUpLanguage.en => '$n min',
    LevelUpLanguage.ru => '$n мин',
    LevelUpLanguage.kk => '$n мин',
  };
  String hours(int n) => switch (language) {
    LevelUpLanguage.en => '$n ${n == 1 ? 'hour' : 'hours'}',
    LevelUpLanguage.ru => '$n ч',
    LevelUpLanguage.kk => '$n сағ',
  };
  String appCount(int n) => switch (language) {
    LevelUpLanguage.en => '$n ${n == 1 ? 'app' : 'apps'}',
    LevelUpLanguage.ru => 'Выбрано: $n',
    LevelUpLanguage.kk => '$n қолданба',
  };
}

const _strings = {
  LevelUpLanguage.en: _Strings(
    LevelUpLanguage.en,
    step: 'STEP 2 OF 3',
    title1: 'Set your ',
    title2: 'Focus.',
    subtitle: 'Build a focus routine that works for you.',
    apps: 'Selected apps',
    edit: 'Edit',
    emptyApps: 'Choose apps before continuing.',
    modeTitle: 'Focus mode',
    modeHint: 'When should your apps be restricted?',
    always: 'Always on',
    alwaysHint: 'Keep apps restricted until you turn it off.',
    session: 'Focus session',
    sessionHint: 'Restrict apps for a set period of time.',
    schedule: 'Custom schedule',
    scheduleHint: 'Restrict apps on specific days and times.',
    sessionLength: 'Session length',
    accessTitle: 'Temporary access',
    accessHint: 'How long should an app stay unlocked?',
    fixedAccessHint:
        'A verified challenge grants 5 minutes. Other durations are saved as a draft.',
    days: 'Days and time',
    weekdays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    start: 'Start time',
    end: 'End time',
    sameDay: 'The schedule starts and ends on the same day.',
    invalidSchedule: 'Choose at least one day and an end time after the start.',
    safety: 'Pause or disable Focus anytime. Exercise is optional.',
    notSupported:
        'These settings can be saved as a draft. Some are not supported by the current Focus engine yet.',
    next: 'Continue',
    skip: 'Skip for now',
    back: 'Back',
    done: 'Done',
    cancel: 'Cancel',
  ),
  LevelUpLanguage.ru: _Strings(
    LevelUpLanguage.ru,
    step: 'ШАГ 2 ИЗ 3',
    title1: 'Настрой ',
    title2: 'фокус.',
    subtitle: 'Выбери удобный для себя режим.',
    apps: 'Выбранные приложения',
    edit: 'Изменить',
    emptyApps: 'Сначала выбери приложения.',
    modeTitle: 'Режим фокуса',
    modeHint: 'Когда ограничивать приложения?',
    always: 'Постоянно',
    alwaysHint: 'Ограничение действует до отключения.',
    session: 'Сеанс фокуса',
    sessionHint: 'Ограничение на определённое время.',
    schedule: 'По расписанию',
    scheduleHint: 'Ограничение в выбранные дни и часы.',
    sessionLength: 'Длительность сеанса',
    accessTitle: 'Временный доступ',
    accessHint: 'На сколько открывать приложение?',
    fixedAccessHint:
        'За выполненное задание открывается 5 минут доступа. Другие варианты сохраняются в черновике.',
    days: 'Дни и время',
    weekdays: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
    start: 'Начало',
    end: 'Конец',
    sameDay: 'Начало и конец — в пределах одного дня.',
    invalidSchedule: 'Выбери хотя бы один день и время окончания после начала.',
    safety: 'Фокус можно приостановить или отключить. Упражнения добровольны.',
    notSupported:
        'Настройки можно сохранить как черновик. Часть из них пока не поддерживается ядром Focus.',
    next: 'Продолжить',
    skip: 'Пока пропустить',
    back: 'Назад',
    done: 'Готово',
    cancel: 'Отмена',
  ),
  LevelUpLanguage.kk: _Strings(
    LevelUpLanguage.kk,
    step: '2-ҚАДАМ / 3',
    title1: 'Фокусты ',
    title2: 'бапта.',
    subtitle: 'Өзіңе ыңғайлы режимді таңда.',
    apps: 'Таңдалған қолданбалар',
    edit: 'Өзгерту',
    emptyApps: 'Алдымен қолданбаларды таңда.',
    modeTitle: 'Фокус режимі',
    modeHint: 'Қолданбаларды қашан шектеу керек?',
    always: 'Үнемі қосулы',
    alwaysHint: 'Өшіргенге дейін шектеу сақталады.',
    session: 'Фокус сеансы',
    sessionHint: 'Қолданбаларды белгілі бір уақытқа шекте.',
    schedule: 'Кесте бойынша',
    scheduleHint: 'Таңдалған күндер мен сағаттарда шекте.',
    sessionLength: 'Сеанс ұзақтығы',
    accessTitle: 'Уақытша қолжетімділік',
    accessHint: 'Қолданба қанша уақыт ашық болсын?',
    fixedAccessHint:
        'Расталған тапсырма 5 минутқа рұқсат береді. Басқа нұсқалар жобаға сақталады.',
    days: 'Күндер мен уақыт',
    weekdays: ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'],
    start: 'Басталу уақыты',
    end: 'Аяқталу уақыты',
    sameDay: 'Басталу және аяқталу уақыты бір күн ішінде болуы керек.',
    invalidSchedule:
        'Кемінде бір күнді таңда. Аяқталу уақыты басталу уақытынан кейін болуы керек.',
    safety:
        'Фокусты кез келген уақытта тоқтатуға немесе өшіруге болады. Жаттығу міндетті емес.',
    notSupported:
        'Баптауларды жоба ретінде сақтауға болады. Кейбірін фокус жүйесі әлі қолдамайды.',
    next: 'Жалғастыру',
    skip: 'Әзірге өткізіп жіберу',
    back: 'Артқа',
    done: 'Дайын',
    cancel: 'Бас тарту',
  ),
};
