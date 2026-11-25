import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;
import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart';
import 'levelup_focus_setup_screen.dart';

const _bg = Color(0xFF0A0F10),
    _surface = Color(0xFF111718),
    _lime = Color(0xFFC7FA5B),
    _ink = Color(0xFFF7F8F8),
    _muted = Color(0xFFB0B8BA),
    _border = Color(0xFF293334);

/// The parent owns persistence, permission handling and activation.
/// A missing callback means a feature is unavailable, not a simulated success.
class LevelUpHomeScreen extends StatefulWidget {
  const LevelUpHomeScreen({
    super.key,
    required this.gateway,
    this.language = DashboardLanguage.en,
    this.catalog = const [],
    this.draftIds = const {},
    this.draftSummary,
    this.focusDraft,
    this.onSaveFocusDraft,
    this.capabilities = const FocusCapabilities(),
    this.loadInsights,
    this.onEditFocus,
    this.onExerciseSettings,
    this.onEnableFocus,
    this.onPauseFocus,
    this.onMovement,
    this.onPermissions,
    this.onNotifications,
    this.onLanguageChanged,
    this.onBreakCompleted,
    this.refreshToken = 0,
    this.soundFeedbackEnabled,
    this.diagnosticLoggingEnabled,
    this.onSoundFeedbackChanged,
    this.onDiagnosticLoggingChanged,
    this.demo = false,
    this.logoAsset = 'assets/images/levelup_mark.png',
  });
  final DashboardFocusGateway gateway;
  final DashboardLanguage language;
  final List<DashboardApp> catalog;
  final Set<String> draftIds;
  final String? draftSummary, logoAsset;
  final FocusSetupDraft? focusDraft;
  final FutureOr<void> Function(FocusSetupDraft)? onSaveFocusDraft;
  final FocusCapabilities capabilities;
  final Future<DashboardInsights> Function()? loadInsights;
  final Future<void> Function()? onEditFocus,
      onExerciseSettings,
      onEnableFocus,
      onPauseFocus,
      onMovement,
      onPermissions,
      onNotifications;
  final ValueChanged<DashboardLanguage>? onLanguageChanged;
  final ValueChanged<DateTime>? onBreakCompleted;
  final int refreshToken;
  final bool? soundFeedbackEnabled, diagnosticLoggingEnabled;
  final Future<void> Function(bool)? onSoundFeedbackChanged,
      onDiagnosticLoggingChanged;
  final bool demo;
  @override
  State<LevelUpHomeScreen> createState() => _HomeState();
}

class _HomeState extends State<LevelUpHomeScreen> with WidgetsBindingObserver {
  DashboardTab _tab = DashboardTab.home;
  late DashboardLanguage _language = widget.language;
  late FocusSetupDraft? _currentDraft = widget.focusDraft;
  FocusSnapshot? _focus;
  final _insightState = ValueNotifier(const DashboardInsights());
  DashboardInsights get _insights => _insightState.value;
  bool _loading = true,
      _focusError = false,
      _insightsError = false,
      _busy = false;
  int _generation = 0;
  Timer? _ticker;
  DateTime _now = DateTime.now();
  final _countdown = ValueNotifier(DateTime.now());
  int _seconds = 0;
  bool _foreground = true;
  final _scrolls = {for (final t in DashboardTab.values) t: ScrollController()};

  String tr(String en, String ru, String kk) => switch (_language) {
    DashboardLanguage.en => en,
    DashboardLanguage.ru => ru,
    DashboardLanguage.kk => kk,
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant LevelUpHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _language = widget.language;
    if (oldWidget.focusDraft != widget.focusDraft) {
      _currentDraft = widget.focusDraft;
    }
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.loadInsights != widget.loadInsights ||
        oldWidget.refreshToken != widget.refreshToken ||
        !setEquals(oldWidget.draftIds, widget.draftIds)) {
      _refresh();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_foreground) return;
      final now = DateTime.now();
      final previous = _now;
      _now = now;
      final deadlines = _active
          ? _focus!.accessUntil.values
          : const <DateTime>[];
      final expired = deadlines.any(
        (d) => d.isAfter(previous) && !d.isAfter(now),
      );
      if (expired || deadlines.any((d) => d.isAfter(now))) {
        _countdown.value = now;
      }
      if (_tab == DashboardTab.home &&
          _greetingPeriod(previous) != _greetingPeriod(now)) {
        setState(() {});
      }
      if ((expired || ++_seconds % 10 == 0) && !_busy && !_loading) {
        _refresh(quiet: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refresh();
      _startTicker();
    } else {
      _ticker?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _insightState.dispose();
    _countdown.dispose();
    for (final s in _scrolls.values) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh({bool quiet = false}) async {
    final generation = ++_generation;
    if (!mounted) return;
    if (!quiet) setState(() => _loading = true);
    FocusSnapshot? next;
    var insights = quiet ? _insights : const DashboardInsights();
    var focusError = false;
    var insightsError = quiet && _insightsError;
    // Independent reads: a failed stats provider does not mask the engine status.
    await Future.wait<void>([
      () async {
        try {
          next = await widget.gateway.read().timeout(
            const Duration(seconds: 5),
          );
        } catch (_) {
          focusError = true;
        }
      }(),
      () async {
        try {
          if (!quiet && widget.loadInsights != null) {
            insights = await widget.loadInsights!().timeout(
              const Duration(seconds: 5),
            );
          }
        } catch (_) {
          insightsError = true;
        }
      }(),
    ]);
    if (!mounted || generation != _generation) return;
    if (quiet &&
        !_loading &&
        _focusError == focusError &&
        _sameFocus(_focus, next)) {
      return;
    }
    setState(() {
      _focus = next;
      _insightState.value = insights;
      _focusError = focusError;
      _insightsError = insightsError;
      _loading = false;
      _now = DateTime.now();
      _countdown.value = _now;
    });
  }

  bool _sameFocus(FocusSnapshot? a, FocusSnapshot? b) =>
      identical(a, b) ||
      (a != null &&
          b != null &&
          a.enabled == b.enabled &&
          a.serviceEnabled == b.serviceEnabled &&
          listEquals(a.targets, b.targets) &&
          mapEquals(a.accessUntil, b.accessUntil));

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Could not complete the action. Try again.',
                'Не удалось выполнить действие. Повтори.',
                'Әрекет орындалмады. Қайталап көр.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        await _refresh();
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  DashboardApp _app(String id) => widget.catalog.firstWhere(
    (a) => a.id == id,
    orElse: () => DashboardApp(id, id),
  );
  List<DashboardApp> get _actualApps =>
      (_focus?.targets ?? []).map(_app).toList();
  List<DashboardApp> get _draftApps {
    final ids = _currentDraft?.packageIds ?? widget.draftIds;
    return ids.map(_app).toList();
  }

  bool get _active => _focus?.active == true;
  String _time(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _minutes(int? n) => n == null ? '—' : '$n ${tr('min', 'мин', 'мин')}';
  String _label(DashboardTab t) => switch (t) {
    DashboardTab.home => tr('Home', 'Главная', 'Басты бет'),
    DashboardTab.focus => tr('Focus', 'Фокус', 'Фокус'),
    DashboardTab.challenge => tr('Challenge', 'Задания', 'Тапсырма'),
    DashboardTab.progress => tr('Progress', 'Прогресс', 'Ілгерілеу'),
    DashboardTab.settings => tr('Settings', 'Настройки', 'Баптаулар'),
  };
  void _go(DashboardTab tab) {
    if (_tab != tab) {
      HapticFeedback.selectionClick();
      setState(() => _tab = tab);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: _bg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _lime,
          onPrimary: _bg,
          surface: _surface,
          onSurface: _ink,
          outline: _border,
        ),
        dividerColor: _border,
        splashColor: const Color(0x10C7FA5B),
        highlightColor: const Color(0x08C7FA5B),
      ),
      child: PopScope(
        canPop: _tab == DashboardTab.home,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _tab != DashboardTab.home) _go(DashboardTab.home);
        },
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _header(),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 2, color: _lime),
                Expanded(
                  child: RefreshIndicator(
                    color: _lime,
                    backgroundColor: _surface,
                    onRefresh: _refresh,
                    child: ListView(
                      key: PageStorageKey(_tab),
                      controller: _scrolls[_tab],
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        if (widget.demo)
                          _note(
                            tr(
                              'DEMO · example data',
                              'ДЕМО · пример данных',
                              'ДЕМО · үлгі деректер',
                            ),
                          ),
                        ...switch (_tab) {
                          DashboardTab.home => _home(),
                          DashboardTab.focus => _focusPage(),
                          DashboardTab.challenge => _challenge(),
                          DashboardTab.progress => _progress(),
                          DashboardTab.settings => _settings(),
                        },
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _bottomNav(),
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
    child: Row(
      children: [
        if (_tab == DashboardTab.home) ...[
          if (widget.logoAsset != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Image.asset(
                widget.logoAsset!,
                width: 30,
                height: 26,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          const Expanded(
            child: Text(
              'LevelUp',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -.5,
              ),
            ),
          ),
        ] else
          Expanded(child: _title(_label(_tab), 22)),
        if (widget.onNotifications != null)
          IconButton(
            onPressed: _busy ? null : () => _action(widget.onNotifications!),
            tooltip: tr('Notifications', 'Уведомления', 'Хабарландырулар'),
            icon: const Icon(Icons.notifications_none_rounded, color: _muted),
          ),
      ],
    ),
  );
  Widget _bottomNav() {
    const icons = [
      Icons.home_outlined,
      Icons.track_changes_rounded,
      Icons.emoji_events_outlined,
      Icons.bar_chart_rounded,
      Icons.settings_outlined,
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            children: [
              for (var i = 0; i < DashboardTab.values.length; i++)
                Expanded(
                  child: Semantics(
                    selected: _tab.index == i,
                    button: true,
                    child: InkWell(
                      key: ValueKey('tab_$i'),
                      onTap: () => _go(DashboardTab.values[i]),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 1,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedScale(
                              scale: _tab.index == i ? 1.08 : 1.0,
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                icons[i],
                                size: 23,
                                color: _tab.index == i ? _lime : _muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _label(DashboardTab.values[i]),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                height: 1.2,
                                color: _tab.index == i ? _lime : _muted,
                                fontWeight: _tab.index == i
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String x, [double size = 18]) => Text(
    x,
    style: TextStyle(
      color: _ink,
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: -.35,
      height: 1.2,
    ),
  );
  Widget _sub(String x, [double size = 13]) => Text(
    x,
    style: TextStyle(color: _muted, fontSize: size, height: 1.35),
  );
  Widget _gap([double h = 18]) => SizedBox(height: h);
  Widget _card(Widget child, {VoidCallback? onTap, Key? key}) => Material(
    key: key,
    color: _surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: _border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    ),
  );
  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: _muted, size: 17),
        const SizedBox(width: 8),
        Expanded(child: _sub(text, 12)),
      ],
    ),
  );
  Widget _section(String label, {String? action, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: _title(label)),
            if (action != null)
              Flexible(
                child: TextButton(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text(
                    action,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      );
  Widget _primary(
    String label,
    VoidCallback? tap, {
    IconData? icon,
    Key? key,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      key: key,
      onPressed: tap,
      style: FilledButton.styleFrom(
        backgroundColor: _lime,
        foregroundColor: _bg,
        disabledBackgroundColor: _border,
        disabledForegroundColor: _muted,
        minimumSize: const Size(0, 50),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _outline(String label, VoidCallback? tap, {Key? key}) =>
      OutlinedButton(
        key: key,
        onPressed: tap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: _border),
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      );
  Widget _appIcon(DashboardApp a, {double size = 32}) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.5;
    final pixelSize = (size * dpr).round();
    return Semantics(
      label: a.name,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: a.icon == null || a.icon!.isEmpty
            ? Container(
                width: size,
                height: size,
                color: _border,
                child: const Icon(Icons.apps_rounded, size: 19, color: _muted),
              )
            : Image.memory(
                a.icon!,
                width: size,
                height: size,
                cacheWidth: pixelSize,
                cacheHeight: pixelSize,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => SizedBox(
                  width: size,
                  height: size,
                  child: const Icon(Icons.apps_rounded, color: _muted),
                ),
              ),
      ),
    );
  }

  Widget _appIcons(List<DashboardApp> apps) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final a in apps) Tooltip(message: a.name, child: _appIcon(a)),
    ],
  );
  String get _status => _focus == null
      ? tr('Status unavailable', 'Статус неизвестен', 'Күйі белгісіз')
      : _active
      ? tr('Focus active', 'Фокус активен', 'Фокус қосулы')
      : tr('Focus off', 'Фокус выключен', 'Фокус өшірулі');
  Widget _statusLine() => Row(
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: _active ? _lime : _muted,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          _status,
          style: TextStyle(
            color: _active ? _lime : _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
  Widget _focusCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _statusLine()),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
        _gap(8),
        _title(
          _active
              ? tr('You’re in focus.', 'Ты в фокусе.', 'Фокус режимі қосулы.')
              : tr(
                  'Your time. Your choice.',
                  'Твоё время. Твой выбор.',
                  'Уақытың. Таңдауың.',
                ),
          21,
        ),
        _gap(5),
        _sub(
          _active
              ? '${_actualApps.length} ${tr('selected apps', 'выбранных приложений', 'таңдалған қолданба')}'
              : tr(
                  'Manage your focus when you need it.',
                  'Настрой фокус, когда он нужен.',
                  'Фокусты қажет кезде бапта.',
                ),
        ),
        if ((_active ? _actualApps : _draftApps).isNotEmpty) ...[
          _gap(12),
          _appIcons(_active ? _actualApps : _draftApps),
        ],
        if (_active) ...[
          for (final app in _actualApps)
            _remainingFor(
              app.id,
              (remaining) => remaining > Duration.zero
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _accessRow(app, remaining),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
        _gap(12),
        if (_active || _focus == null)
          SizedBox(
            width: double.infinity,
            child: _outline(
              widget.onPauseFocus != null && _active
                  ? tr('Pause', 'Пауза', 'Кідірту')
                  : tr('Turn off Focus', 'Отключить фокус', 'Фокусты өшіру'),
              _busy
                  ? null
                  : () => _action(
                      _active && widget.onPauseFocus != null
                          ? widget.onPauseFocus!
                          : widget.gateway.disable,
                    ),
              key: const ValueKey('home_off'),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: _outline(
                  tr('Manage', 'Настроить', 'Баптау'),
                  () => _go(DashboardTab.focus),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('home_enable'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _lime,
                    foregroundColor: _bg,
                    disabledBackgroundColor: _border,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _busy || widget.onEnableFocus == null
                      ? null
                      : () => _action(widget.onEnableFocus!),
                  child: Text(
                    tr('Enable', 'Включить', 'Қосу'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    ),
    key: const ValueKey('home_focus'),
    onTap: () => _go(DashboardTab.focus),
  );
  Widget _remainingFor(String id, Widget Function(Duration) builder) =>
      ValueListenableBuilder<DateTime>(
        valueListenable: _countdown,
        builder: (context, now, child) =>
            builder(_focus?.remaining(id, now) ?? Duration.zero),
      );

  Widget _accessRow(DashboardApp a, Duration remaining) => Row(
    children: [
      Expanded(
        child: _sub(
          '${a.name} · ${tr('temporary access', 'временный доступ', 'уақытша қолжетімділік')}',
        ),
      ),
      Text(
        _time(remaining),
        style: const TextStyle(
          color: _lime,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
  int _greetingPeriod(DateTime time) => time.hour < 12
      ? 0
      : time.hour < 18
      ? 1
      : 2;

  String get _greeting => _now.hour < 12
      ? tr('Good morning.', 'Доброе утро.', 'Қайырлы таң.')
      : _now.hour < 18
      ? tr('Good afternoon.', 'Добрый день.', 'Қайырлы күн.')
      : tr('Good evening.', 'Добрый вечер.', 'Қайырлы кеш.');
  List<Widget> _home() => [
    _title(_greeting, 26),
    _gap(15),
    _focusCard(),
    if (_focusError)
      _note(
        tr(
          'Could not read Focus. Pull down to retry.',
          'Не удалось проверить фокус. Потяни вниз для обновления.',
          'Фокусты тексеру мүмкін болмады. Жаңарту үшін төмен тарт.',
        ),
      ),
    _gap(),
    _section(
      tr('Today', 'Сегодня', 'Бүгін'),
      action: tr('View activity ›', 'Активность ›', 'Белсенділік ›'),
      onTap: _openActivity,
    ),
    LayoutBuilder(
      builder: (context, c) {
        final cards = [
          _metric(
            Icons.smartphone_rounded,
            _minutes(_insights.todayUsageMinutes),
            tr('Selected apps usage', 'Время в приложениях', 'Қолданба уақыты'),
          ),
          _metric(
            Icons.lock_open_rounded,
            _insights.todayUnlocks?.toString() ?? '—',
            tr('Temporary unlocks', 'Разблокировки', 'Уақытша ашулар'),
          ),
        ];
        return c.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(14) > 20
            ? Column(children: [cards[0], _gap(8), cards[1]])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                ],
              );
      },
    ),
    _gap(12),
    _levelCard(onTap: _openLevel),
    _gap(12),
    _primary(
      tr('Open challenges', 'Открыть задания', 'Тапсырмаларды ашу'),
      () => _go(DashboardTab.challenge),
      icon: Icons.arrow_forward_rounded,
      key: const ValueKey('home_challenge'),
    ),
    _gap(24),
    _section(
      tr('This week', 'Эта неделя', 'Осы апта'),
      action: tr('Progress ›', 'Прогресс ›', 'Ілгерілеу ›'),
      onTap: () => _go(DashboardTab.progress),
    ),
    _usageCard(),
    _gap(),
    _section(
      tr('Recent activity', 'Недавняя активность', 'Соңғы белсенділік'),
      action: tr('See all ›', 'Вся история ›', 'Барлығы ›'),
      onTap: _openActivity,
    ),
    _eventsCard(limit: 3),
    if (_insightsError)
      _note(
        tr(
          'Activity data could not be loaded.',
          'Не удалось загрузить активность.',
          'Белсенділік деректері жүктелмеді.',
        ),
      ),
  ];
  Widget _metric(IconData icon, String value, String label) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _muted, size: 21),
        _gap(8),
        _title(value, 23),
        _gap(4),
        _sub(label, 12),
      ],
    ),
  );
  Widget _levelCard({VoidCallback? onTap}) {
    final xp = _insights.totalXp;
    final level = xp == null ? null : DashboardLevel.fromXp(xp);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _lime, size: 23),
              const SizedBox(width: 8),
              Expanded(
                child: _title(
                  level == null
                      ? tr('Level & XP', 'Уровень и XP', 'Деңгей және XP')
                      : '${tr('Level', 'Уровень', 'Деңгей')} ${level.level}',
                  17,
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
          _gap(8),
          if (level == null)
            _sub(
              tr(
                'Progress is not available yet.',
                'Прогресс пока недоступен.',
                'Ілгерілеу әзірге қолжетімсіз.',
              ),
            )
          else ...[
            _sub('${level.xp} / ${level.next} XP'),
            _gap(7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: level.fraction,
                minHeight: 5,
                backgroundColor: _border,
                color: _lime,
              ),
            ),
          ],
        ],
      ),
      onTap: onTap,
      key: onTap == null ? null : const ValueKey('home_level'),
    );
  }

  List<Widget> _focusPage() {
    final draft =
        _currentDraft ??
        FocusSetupDraft(
          packageIds: widget.draftIds,
          mode: FocusMode.alwaysOn,
          unlockMinutes: 5,
          sessionMinutes: 60,
        );

    final modeLabel = switch (draft.mode) {
      FocusMode.alwaysOn => tr('Always on', 'Всегда активен', 'Әрқашан қосулы'),
      FocusMode.timedSession => tr('Session', 'Сессия', 'Сессия'),
      FocusMode.customSchedule => tr(
        'Schedule',
        'По расписанию',
        'Кесте бойынша',
      ),
    };

    final durationLabel = '${draft.sessionMinutes} ${tr('min', 'мин', 'мин')}';
    final accessLabel = '${draft.unlockMinutes} ${tr('min', 'мин', 'мин')}';

    final daysAbbr = switch (_language) {
      DashboardLanguage.en => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      DashboardLanguage.ru => const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      DashboardLanguage.kk => const ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'],
    };
    final activeDays = [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ].where(draft.weekdays.contains).map((d) => daysAbbr[d - 1]).join(', ');
    String formatClock(int min) =>
        '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';
    final scheduleLabel = draft.weekdays.isEmpty
        ? tr('No days selected', 'Дни не выбраны', 'Күндер таңдалмаған')
        : '$activeDays · ${formatClock(draft.startMinute)} – ${formatClock(draft.endMinute)}';

    return [
      _statusLine(),
      _gap(8),
      _title(
        _active
            ? tr('Focus is on', 'Фокус включён', 'Фокус қосулы')
            : tr('Manage Focus', 'Управление фокусом', 'Фокусты басқару'),
        26,
      ),
      _gap(),
      if (_focusError)
        _note(
          tr(
            'Engine status could not be verified.',
            'Не удалось проверить состояние ядра.',
            'Жүйе күйін тексеру мүмкін болмады.',
          ),
        ),
      _section(tr('Current engine state', 'Текущее состояние', 'Ағымдағы күй')),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sub(
              _focus == null
                  ? tr('Not checked', 'Не проверено', 'Тексерілмеді')
                  : _focus!.serviceEnabled
                  ? tr(
                      'Accessibility enabled',
                      'Разрешение выдано',
                      'Рұқсат берілді',
                    )
                  : tr(
                      'Accessibility not enabled',
                      'Нет разрешения специальных возможностей',
                      'Арнайы мүмкіндіктерге рұқсат жоқ',
                    ),
            ),
            if (_active) ...[
              _gap(12),
              for (final a in _actualApps) ...[
                _remainingFor(
                  a.id,
                  (remaining) => _appLine(
                    a,
                    remaining > Duration.zero
                        ? _time(remaining)
                        : tr('Restricted', 'Ограничено', 'Шектелген'),
                  ),
                ),
                _gap(8),
              ],
            ],
            _gap(8),
            if (_active || _focus == null) ...[
              if (_active && widget.onPauseFocus != null) ...[
                _outline(
                  tr('Pause Focus', 'Пауза фокуса', 'Фокусты кідірту'),
                  _busy ? null : () => _showPauseSheet(),
                ),
                _gap(8),
              ],
              _primary(
                tr('Turn off Focus', 'Отключить фокус', 'Фокусты өшіру'),
                _busy ? null : () => _action(widget.gateway.disable),
                key: const ValueKey('focus_off'),
              ),
            ] else
              _primary(
                tr('Enable Focus', 'Включить фокус', 'Фокусты қосу'),
                _busy || widget.onEnableFocus == null
                    ? null
                    : () => _action(widget.onEnableFocus!),
                key: const ValueKey('focus_enable'),
              ),
          ],
        ),
      ),
      _gap(),
      _section(
        tr('Protected apps', 'Защищённые приложения', 'Қорғалған қолданбалар'),
        action: tr('Edit apps', 'Изменить', 'Өзгерту'),
        onTap: widget.onEditFocus == null || _busy
            ? null
            : () => _action(widget.onEditFocus!),
      ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_draftApps.isEmpty)
              _sub(
                tr(
                  'No apps selected.',
                  'Приложения не выбраны.',
                  'Қолданбалар таңдалмаған.',
                ),
              )
            else
              for (var i = 0; i < _draftApps.length; i++) ...[
                InkWell(
                  onTap: () => _showAppDetailsSheet(_draftApps[i], draft),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        _appIcon(_draftApps[i]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _draftApps[i].name,
                            style: const TextStyle(fontSize: 14, color: _ink),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: _muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < _draftApps.length - 1) _gap(6),
              ],
            _gap(12),
            _outline(
              tr(
                'Edit apps selection',
                'Выбрать приложения',
                'Қолданбаларды таңдау',
              ),
              widget.onEditFocus == null || _busy
                  ? null
                  : () => _action(widget.onEditFocus!),
              key: const ValueKey('edit_apps_button'),
            ),
          ],
        ),
      ),
      _gap(),
      _section(tr('Focus rules', 'Правила фокуса', 'Фокус ережелері')),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.onExerciseSettings != null) ...[
              _ruleTile(
                title: tr('Exercises', 'Упражнения', 'Жаттығулар'),
                subtitle: tr(
                  'Movement before access',
                  'Движение перед доступом',
                  'Рұқсат алдындағы қозғалыс',
                ),
                icon: Icons.directions_walk_rounded,
                key: const ValueKey('focus_exercise_settings'),
                onTap: () => _action(widget.onExerciseSettings!),
              ),
              const Divider(color: _border, height: 16),
            ],
            _ruleTile(
              title: tr('Focus mode', 'Режим фокуса', 'Фокус режимі'),
              subtitle:
                  draft.mode == FocusMode.alwaysOn ||
                      (draft.mode == FocusMode.timedSession &&
                          widget.capabilities.timedSession) ||
                      (draft.mode == FocusMode.customSchedule &&
                          widget.capabilities.customSchedule)
                  ? modeLabel
                  : '$modeLabel · ${tr('Draft', 'Черновик', 'Жоба')}',
              icon: Icons.tune_rounded,
              key: const ValueKey('rule_mode_tile'),
              onTap: () => _showModeSheet(draft),
            ),
            const Divider(color: _border, height: 16),
            if (draft.mode == FocusMode.timedSession) ...[
              _ruleTile(
                title: tr(
                  'Session duration',
                  'Длительность сессии',
                  'Сессия ұзақтығы',
                ),
                subtitle: durationLabel,
                icon: Icons.hourglass_bottom_rounded,
                key: const ValueKey('rule_duration_tile'),
                onTap: () => _showSessionDurationSheet(draft),
              ),
              const Divider(color: _border, height: 16),
            ],
            if (draft.mode == FocusMode.customSchedule) ...[
              _ruleTile(
                title: tr('Custom schedule', 'Расписание', 'Кесте'),
                subtitle: scheduleLabel,
                icon: Icons.calendar_today_rounded,
                key: const ValueKey('rule_schedule_tile'),
                onTap: () => _showScheduleSheet(draft),
              ),
              const Divider(color: _border, height: 16),
            ],
            _ruleTile(
              title: tr(
                'Temporary access',
                'Временный доступ',
                'Уақытша қолжетімділік',
              ),
              subtitle:
                  widget.capabilities.configurableAccess ||
                      draft.unlockMinutes ==
                          FocusCapabilities.defaultAccessMinutes
                  ? accessLabel
                  : tr(
                      '5 min active · $accessLabel draft',
                      'Действует 5 мин · $accessLabel в черновике',
                      'Қазір 5 мин · жоба $accessLabel',
                    ),
              icon: Icons.timer_outlined,
              key: const ValueKey('rule_access_tile'),
              onTap: () => _showAccessDurationSheet(draft),
            ),
            const Divider(color: _border, height: 16),
            _ruleTile(
              title: tr(
                'Access options',
                'Параметры разблокировки',
                'Бұғаттан шығару баптаулары',
              ),
              subtitle: tr(
                'Exercise or voluntary exit',
                'Упражнение или добровольный выход',
                'Жаттығу немесе ерікті шығу',
              ),
              icon: Icons.fitness_center_rounded,
              key: const ValueKey('rule_options_tile'),
              onTap: () => _showAccessOptionsSheet(),
            ),
          ],
        ),
      ),
      _gap(),
      if (widget.onEnableFocus == null)
        _note(
          tr(
            'Activation needs a supported rule and a verified safe exit.',
            'Включение требует поддерживаемого правила и проверенного быстрого выхода.',
            'Қосу үшін қолдау көрсетілетін ереже және қауіпсіз шығу қажет.',
          ),
        ),
      _note(
        tr(
          'Single-target support in current engine: YouTube, Instagram, or TikTok. Voluntary exit is always available.',
          'В текущей версии ядра поддерживается одно приложение: YouTube, Instagram или TikTok. Отключение всегда доступно.',
          'Ағымдағы нұсқада бір қолданба қолдау табады: YouTube, Instagram немесе TikTok. Өшіру әрқашан қолжетімді.',
        ),
      ),
    ];
  }

  Widget _ruleTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Key? key,
  }) => InkWell(
    key: key,
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: _lime, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
        ],
      ),
    ),
  );
  Widget _appLine(DashboardApp a, String value) => Row(
    children: [
      _appIcon(a),
      const SizedBox(width: 10),
      Expanded(
        child: Text(a.name, style: const TextStyle(fontSize: 14, color: _ink)),
      ),
      if (value.isNotEmpty) Flexible(child: _sub(value)),
    ],
  );

  Future<void> _saveDraft(FocusSetupDraft newDraft) => _action(() async {
    await widget.onSaveFocusDraft?.call(newDraft);
    if (mounted) setState(() => _currentDraft = newDraft);
  });

  Future<void> _showModeSheet(FocusSetupDraft currentDraft) async {
    FocusMode selected = currentDraft.mode;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _gap(16),
                _title(tr('Focus mode', 'Режим фокуса', 'Фокус режимі'), 20),
                _gap(6),
                _sub(
                  tr(
                    'Select how LevelUp shields your focus time.',
                    'Выбери, как LevelUp защищает твоё внимание.',
                    'LevelUp назарыңды қалай қорғайтынын таңда.',
                  ),
                ),
                _gap(16),
                for (final mode in FocusMode.values) ...[
                  Material(
                    color: selected == mode
                        ? const Color(0x15C7FA5B)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: selected == mode ? _lime : _border,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setSheetState(() => selected = mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected == mode
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected == mode ? _lime : _muted,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    switch (mode) {
                                      FocusMode.alwaysOn => tr(
                                        'Always on',
                                        'Всегда активен',
                                        'Әрқашан қосулы',
                                      ),
                                      FocusMode.timedSession => tr(
                                        'Session',
                                        'Сессия',
                                        'Сессия',
                                      ),
                                      FocusMode.customSchedule => tr(
                                        'Schedule',
                                        'По расписанию',
                                        'Кесте бойынша',
                                      ),
                                    },
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: selected == mode ? _lime : _ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    switch (mode) {
                                      FocusMode.alwaysOn => tr(
                                        'Continuous shielding whenever accessibility is active.',
                                        'Постоянная защита при активном сервисе.',
                                        'Қызмет қосулы кезде үздіксіз қорғау.',
                                      ),
                                      FocusMode.timedSession => tr(
                                        'Focus for a fixed duration, then rest.',
                                        'Фокус на фиксированное время с последующим отдыхом.',
                                        'Белгіленген уақыт бойы фокус, сосын тынығу.',
                                      ),
                                      FocusMode.customSchedule => tr(
                                        'Active during specific days and hours.',
                                        'Активен в заданные дни и часы.',
                                        'Белгіленген күндер мен сағаттарда қосулы.',
                                      ),
                                    },
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _gap(8),
                ],
                _gap(16),
                Row(
                  children: [
                    Expanded(
                      child: _outline(
                        tr('Cancel', 'Отмена', 'Болдырмау'),
                        () => Navigator.of(sheetContext).pop(),
                        key: const ValueKey('sheet_cancel_mode'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _primary(tr('Apply', 'Применить', 'Қолдану'), () {
                        _saveDraft(currentDraft.copyWith(mode: selected));
                        Navigator.of(sheetContext).pop();
                      }, key: const ValueKey('sheet_apply_mode')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showSessionDurationSheet(FocusSetupDraft currentDraft) async {
    int selected = currentDraft.sessionMinutes;
    const options = [15, 30, 60, 120];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _gap(16),
                _title(
                  tr(
                    'Session duration',
                    'Длительность сессии',
                    'Сессия ұзақтығы',
                  ),
                  20,
                ),
                _gap(6),
                _sub(
                  tr(
                    'Choose how long each focus interval lasts.',
                    'Выбери продолжительность одного интервала фокуса.',
                    'Әр фокус аралығының ұзақтығын таңда.',
                  ),
                ),
                _gap(16),
                for (final mins in options) ...[
                  Material(
                    color: selected == mins
                        ? const Color(0x15C7FA5B)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: selected == mins ? _lime : _border,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setSheetState(() => selected = mins),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected == mins
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected == mins ? _lime : _muted,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$mins ${tr('minutes', 'минут', 'минут')}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: selected == mins ? _lime : _ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _gap(8),
                ],
                _gap(16),
                Row(
                  children: [
                    Expanded(
                      child: _outline(
                        tr('Cancel', 'Отмена', 'Болдырмау'),
                        () => Navigator.of(sheetContext).pop(),
                        key: const ValueKey('sheet_cancel_duration'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _primary(tr('Apply', 'Применить', 'Қолдану'), () {
                        _saveDraft(
                          currentDraft.copyWith(sessionMinutes: selected),
                        );
                        Navigator.of(sheetContext).pop();
                      }, key: const ValueKey('sheet_apply_duration')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showScheduleSheet(FocusSetupDraft currentDraft) async {
    Set<int> selectedDays = Set.of(currentDraft.weekdays);
    int startMinute = currentDraft.startMinute;
    int endMinute = currentDraft.endMinute;

    final daysLabels = switch (_language) {
      DashboardLanguage.en => const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ],
      DashboardLanguage.ru => const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      DashboardLanguage.kk => const ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'],
    };

    String formatClock(int min) =>
        '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _gap(16),
                _title(tr('Custom schedule', 'Расписание', 'Кесте'), 20),
                _gap(6),
                _sub(
                  tr(
                    'Choose active days of the week and working hours.',
                    'Выбери дни недели и рабочие часы защиты.',
                    'Қорғаудың апта күндері мен жұмыс уақытын таңда.',
                  ),
                ),
                _gap(16),
                _sub(tr('Days of week', 'Дни недели', 'Апта күндері'), 14),
                _gap(8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (int day = 1; day <= 7; day++) ...[
                      FilterChip(
                        selected: selectedDays.contains(day),
                        label: Text(daysLabels[day - 1]),
                        selectedColor: const Color(0x25C7FA5B),
                        checkmarkColor: _lime,
                        backgroundColor: _surface,
                        side: BorderSide(
                          color: selectedDays.contains(day) ? _lime : _border,
                        ),
                        labelStyle: TextStyle(
                          color: selectedDays.contains(day) ? _lime : _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (selected) {
                          setSheetState(() {
                            if (selected) {
                              selectedDays.add(day);
                            } else if (selectedDays.length > 1) {
                              selectedDays.remove(day);
                            }
                          });
                        },
                      ),
                    ],
                  ],
                ),
                _gap(16),
                _sub(
                  tr('Active hours', 'Активные часы', 'Жұмыс сағаттары'),
                  14,
                ),
                _gap(8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final current = TimeOfDay(
                            hour: startMinute ~/ 60,
                            minute: startMinute % 60,
                          );
                          final picked = await showTimePicker(
                            context: sheetContext,
                            initialTime: current,
                          );
                          if (picked != null) {
                            final total = picked.hour * 60 + picked.minute;
                            if (total < endMinute) {
                              setSheetState(() => startMinute = total);
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: _border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('Start', 'Начало', 'Басталуы'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatClock(startMinute),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final current = TimeOfDay(
                            hour: endMinute ~/ 60,
                            minute: endMinute % 60,
                          );
                          final picked = await showTimePicker(
                            context: sheetContext,
                            initialTime: current,
                          );
                          if (picked != null) {
                            final total = picked.hour * 60 + picked.minute;
                            if (total > startMinute) {
                              setSheetState(() => endMinute = total);
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: _border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('End', 'Конец', 'Аяқталуы'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatClock(endMinute),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _gap(20),
                Row(
                  children: [
                    Expanded(
                      child: _outline(
                        tr('Cancel', 'Отмена', 'Болдырмау'),
                        () => Navigator.of(sheetContext).pop(),
                        key: const ValueKey('sheet_cancel_schedule'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _primary(tr('Apply', 'Применить', 'Қолдану'), () {
                        _saveDraft(
                          currentDraft.copyWith(
                            weekdays: selectedDays,
                            startMinute: startMinute,
                            endMinute: endMinute,
                          ),
                        );
                        Navigator.of(sheetContext).pop();
                      }, key: const ValueKey('sheet_apply_schedule')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAccessDurationSheet(FocusSetupDraft currentDraft) async {
    int selected = currentDraft.unlockMinutes;
    const options = [3, 5, 10, 15];
    final configurable = widget.capabilities.configurableAccess;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _gap(16),
                _title(
                  tr(
                    'Temporary access',
                    'Временный доступ',
                    'Уақытша қолжетімділік',
                  ),
                  20,
                ),
                _gap(6),
                _sub(
                  configurable
                      ? tr(
                          'How long the protected app stays open after a verified challenge.',
                          'Сколько времени приложение доступно после выполненного задания.',
                          'Расталған тапсырмадан кейін қолданба қанша уақыт ашық болады.',
                        )
                      : tr(
                          'A verified challenge grants 5 minutes. Other durations are saved as a draft.',
                          'За выполненное задание открывается 5 минут доступа. Другие варианты сохраняются в черновике.',
                          'Расталған тапсырма 5 минутқа рұқсат береді. Басқа нұсқалар жобаға сақталады.',
                        ),
                ),
                _gap(16),
                for (final mins in options) ...[
                  Material(
                    color: selected == mins
                        ? const Color(0x15C7FA5B)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: selected == mins ? _lime : _border,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setSheetState(() => selected = mins),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected == mins
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: selected == mins ? _lime : _muted,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$mins ${tr('minutes', 'минут', 'минут')}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: selected == mins ? _lime : _ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _gap(8),
                ],
                _gap(16),
                Row(
                  children: [
                    Expanded(
                      child: _outline(
                        tr('Cancel', 'Отмена', 'Болдырмау'),
                        () => Navigator.of(sheetContext).pop(),
                        key: const ValueKey('sheet_cancel_access'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _primary(
                        configurable
                            ? tr('Apply', 'Применить', 'Қолдану')
                            : tr(
                                'Save draft',
                                'Сохранить черновик',
                                'Жобаны сақтау',
                              ),
                        () {
                          _saveDraft(
                            currentDraft.copyWith(unlockMinutes: selected),
                          );
                          Navigator.of(sheetContext).pop();
                        },
                        key: const ValueKey('sheet_apply_access'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAppDetailsSheet(
    DashboardApp app,
    FocusSetupDraft currentDraft,
  ) async {
    final isDraft = currentDraft.packageIds.contains(app.id);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _gap(16),
              Row(
                children: [
                  _appIcon(app, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.id,
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _gap(20),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sub(tr('Status', 'Статус', 'Күйі')),
                    const SizedBox(height: 4),
                    _remainingFor(app.id, (remaining) {
                      final activeTarget =
                          _active && _focus!.targets.contains(app.id);
                      return Text(
                        remaining > Duration.zero
                            ? tr(
                                'Temporary access',
                                'Временный доступ',
                                'Уақытша қолжетімділік',
                              )
                            : activeTarget
                            ? tr('Restricted', 'Ограничено', 'Шектелген')
                            : isDraft
                            ? tr(
                                'Saved in selection',
                                'В списке выбранных',
                                'Таңдалғандар тізімінде',
                              )
                            : tr('Not selected', 'Не выбрано', 'Таңдалмаған'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: activeTarget ? _lime : _ink,
                        ),
                      );
                    }),
                  ],
                ),
              ),
              _gap(16),
              if (isDraft && currentDraft.packageIds.length > 1) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF5252),
                      side: const BorderSide(color: Color(0x40FF5252)),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final updated = Set<String>.of(currentDraft.packageIds)
                        ..remove(app.id);
                      _saveDraft(currentDraft.copyWith(packageIds: updated));
                      Navigator.of(sheetContext).pop();
                    },
                    child: Text(
                      tr(
                        'Remove from protected apps',
                        'Удалить из списка защиты',
                        'Қорғау тізімінен өшіру',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                _gap(8),
              ],
              SizedBox(
                width: double.infinity,
                child: _outline(
                  tr('Close', 'Закрыть', 'Жабу'),
                  () => Navigator.of(sheetContext).pop(),
                  key: const ValueKey('sheet_close_app_details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAccessOptionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _gap(16),
              _title(
                tr(
                  'Access options',
                  'Параметры разблокировки',
                  'Бұғаттан шығару баптаулары',
                ),
                20,
              ),
              _gap(6),
              _sub(
                tr(
                  'How LevelUp unlocks apps when you need them.',
                  'Как LevelUp открывает доступ к приложениям при необходимости.',
                  'Қажет болғанда LevelUp қолданбаларға қалай рұқсат береді.',
                ),
              ),
              _gap(16),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_run_rounded,
                          color: _lime,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          tr(
                            'Physical movement',
                            'Физическое движение',
                            'Физикалық қозғалыс',
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _sub(
                      tr(
                        'Complete a quick mindful movement set to earn temporary access.',
                        'Выполни короткую серию упражнений для временного доступа.',
                        'Уақытша қолжетімділік алу үшін қысқа жаттығулар жиынтығын жаса.',
                      ),
                    ),
                  ],
                ),
              ),
              _gap(8),
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.touch_app_rounded,
                          color: _muted,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          tr(
                            'Manual unlock / turn off',
                            'Ручное отключение',
                            'Қолмен өшіру',
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _sub(
                      tr(
                        'You can always disable Focus or exit freely. LevelUp never traps you.',
                        'Ты всегда можешь отключить фокус без принуждения. LevelUp не блокирует телефон.',
                        'Сен әрқашан фокусты мәжбүрлеусіз өшіре аласың. LevelUp телефонды құлыптамайды.',
                      ),
                    ),
                  ],
                ),
              ),
              _gap(16),
              SizedBox(
                width: double.infinity,
                child: _primary(
                  tr('Got it', 'Понятно', 'Түсінікті'),
                  () => Navigator.of(sheetContext).pop(),
                  key: const ValueKey('sheet_got_it_options'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPauseSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              _gap(16),
              _title(
                tr(
                  'Turn off until manually enabled',
                  'Отключить до ручного включения',
                  'Қолмен қосқанша өшіру',
                ),
                20,
              ),
              _gap(6),
              _sub(
                tr(
                  'Temporarily suspend focus shielding. Automatic timed resume is not supported by the current engine, so Focus will remain off until you manually enable it again.',
                  'Временно приостановить защиту фокуса. Автоматическое возобновление не поддерживается текущим ядром, поэтому фокус останется выключенным до повторного ручного включения.',
                  'Фокус қорғауын уақытша тоқтату. Автоматты түрде қайта қосылуды ағымдағы ядро қолдамайды, сондықтан фокус қайта қолмен қосқанша өшірулі болады.',
                ),
              ),
              _gap(20),
              Row(
                children: [
                  Expanded(
                    child: _outline(
                      tr('Cancel', 'Отмена', 'Болдырмау'),
                      () => Navigator.of(sheetContext).pop(),
                      key: const ValueKey('sheet_cancel_pause'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _primary(tr('Turn off', 'Отключить', 'Өшіру'), () {
                      Navigator.of(sheetContext).pop();
                      if (widget.onPauseFocus != null) {
                        _action(widget.onPauseFocus!);
                      } else {
                        _action(widget.gateway.disable);
                      }
                    }, key: const ValueKey('sheet_apply_pause')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _challenge() => [
    _title(tr('Choose a challenge', 'Выбери задание', 'Тапсырманы таңда'), 26),
    _gap(6),
    _sub(
      tr(
        'Take a short break when you want to.',
        'Сделай небольшую паузу, когда захочешь.',
        'Қалаған кезде қысқа үзіліс жаса.',
      ),
    ),
    _gap(),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.directions_walk_rounded, color: _muted, size: 26),
          _gap(8),
          _title(tr('Movement', 'Движение', 'Қозғалыс')),
          _gap(5),
          _sub(
            widget.onMovement == null
                ? tr(
                    'Open your selected app with Focus on to start the movement challenge.',
                    'Чтобы начать упражнение, открой выбранное приложение при включённом фокусе.',
                    'Жаттығуды бастау үшін фокус қосулы кезде таңдалған қолданбаны ашыңыз.',
                  )
                : tr(
                    'Optional movement activity. Stop whenever you want.',
                    'Добровольное движение. Можно остановиться в любой момент.',
                    'Ерікті қозғалыс. Кез келген уақытта тоқтатуға болады.',
                  ),
          ),
          if (widget.onMovement != null) ...[
            _gap(12),
            _primary(
              tr(
                'Open movement challenge',
                'Открыть задание',
                'Тапсырманы ашу',
              ),
              _busy ? null : () => _action(widget.onMovement!),
            ),
          ],
        ],
      ),
    ),
    _gap(10),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.self_improvement_rounded, color: _muted, size: 26),
          _gap(8),
          _title(tr('Mindful break', 'Спокойная пауза', 'Тыныш үзіліс')),
          _gap(5),
          _sub(
            tr(
              'One minute away from the screen. No camera needed.',
              'Минута без экрана. Камера не нужна.',
              'Экрансыз бір минут. Камера қажет емес.',
            ),
          ),
          _gap(12),
          _outline(
            tr('Start break', 'Начать паузу', 'Үзілісті бастау'),
            _openBreak,
            key: const ValueKey('challenge_break'),
          ),
        ],
      ),
    ),
    _gap(8),
    _note(
      tr(
        'Challenges are optional. They never change your Focus rules or require exercise to recover access.',
        'Задания добровольны. Они не меняют правила фокуса и не требуют упражнений для возврата доступа.',
        'Тапсырмалар міндетті емес. Олар фокус ережелерін өзгертпейді және қолжетімділікті қайтару үшін жаттығуды талап етпейді.',
      ),
    ),
  ];
  Future<void> _openBreak() async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _BreakScreen(language: _language)),
    );
    if (!mounted || completed != true) return;
    widget.onBreakCompleted?.call(DateTime.now());
    await _refresh();
  }

  List<Widget> _progress() => [
    _title(tr('Your progress', 'Твой прогресс', 'Ілгерілеуің'), 26),
    _gap(),
    if (_insights.todayWorkouts != null || _insights.todayUnlocks != null) ...[
      Row(
        children: [
          Expanded(
            child: _metric(
              Icons.fitness_center_rounded,
              _insights.todayWorkouts?.toString() ?? '—',
              tr('Workouts today', 'Тренировок сегодня', 'Бүгінгі жаттығулар'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metric(
              Icons.lock_open_rounded,
              _insights.todayUnlocks?.toString() ?? '—',
              tr('Unlocks today', 'Разблокировок сегодня', 'Бүгінгі ашулар'),
            ),
          ),
        ],
      ),
      _gap(),
    ],
    _levelCard(onTap: _openLevel),
    _gap(),
    _section(tr('Screen time', 'Экранное время', 'Экран уақыты')),
    _usageCard(),
    _gap(),
    _section(
      tr('Activity', 'Активность', 'Белсенділік'),
      action: tr('See all ›', 'Вся история ›', 'Барлығы ›'),
      onTap: _openActivity,
    ),
    _eventsCard(limit: 5),
  ];
  List<Widget> _settings() => [
    _title(tr('Preferences', 'Предпочтения', 'Қалаулар'), 26),
    _gap(),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(tr('Language', 'Язык', 'Тіл'), 16),
          _gap(10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in DashboardLanguage.values)
                ChoiceChip(
                  label: Text(switch (l) {
                    DashboardLanguage.en => 'English',
                    DashboardLanguage.ru => 'Русский',
                    DashboardLanguage.kk => 'Қазақша',
                  }),
                  selected: l == _language,
                  showCheckmark: false,
                  selectedColor: _lime,
                  labelStyle: TextStyle(color: l == _language ? _bg : _ink),
                  onSelected: (_) {
                    setState(() => _language = l);
                    widget.onLanguageChanged?.call(l);
                  },
                ),
            ],
          ),
        ],
      ),
    ),
    _gap(10),
    _card(
      Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_outlined, color: _muted),
            title: Text(tr('Permissions', 'Разрешения', 'Рұқсаттар')),
            trailing: const Icon(Icons.chevron_right, color: _muted),
            enabled: widget.onPermissions != null,
            onTap: widget.onPermissions == null
                ? null
                : () => _action(widget.onPermissions!),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.track_changes, color: _muted),
            title: Text(
              tr('Focus settings', 'Настройки фокуса', 'Фокус баптаулары'),
            ),
            trailing: const Icon(Icons.chevron_right, color: _muted),
            onTap: () => _go(DashboardTab.focus),
          ),
        ],
      ),
    ),
    _gap(10),
    if (widget.onSoundFeedbackChanged != null ||
        widget.onDiagnosticLoggingChanged != null) ...[
      _card(
        Column(
          children: [
            if (widget.onSoundFeedbackChanged != null &&
                widget.soundFeedbackEnabled != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.soundFeedbackEnabled!,
                activeThumbColor: _lime,
                title: Text(
                  tr(
                    'Sound & haptic feedback',
                    'Звук и виброотклик',
                    'Дыбыс және діріл',
                  ),
                ),
                onChanged: _busy
                    ? null
                    : (v) => _action(() => widget.onSoundFeedbackChanged!(v)),
              ),
            if (widget.onSoundFeedbackChanged != null &&
                widget.soundFeedbackEnabled != null &&
                widget.onDiagnosticLoggingChanged != null &&
                widget.diagnosticLoggingEnabled != null)
              const Divider(height: 1),
            if (widget.onDiagnosticLoggingChanged != null &&
                widget.diagnosticLoggingEnabled != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: widget.diagnosticLoggingEnabled!,
                activeThumbColor: _lime,
                title: Text(
                  tr(
                    'Diagnostic logging',
                    'Журнал диагностики',
                    'Диагностика журналы',
                  ),
                ),
                onChanged: _busy
                    ? null
                    : (v) =>
                          _action(() => widget.onDiagnosticLoggingChanged!(v)),
              ),
          ],
        ),
      ),
      _gap(10),
    ],
    _note(
      tr(
        'Additional settings will appear when their features are connected.',
        'Дополнительные настройки появятся после подключения функций.',
        'Қосымша баптаулар функциялар қосылғанда пайда болады.',
      ),
    ),
  ];
  Widget _usageCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sub(
          tr(
            'Selected apps usage',
            'Время в выбранных приложениях',
            'Таңдалған қолданбалар уақыты',
          ),
        ),
        _gap(8),
        if (_insights.week.isEmpty)
          _sub(
            tr(
              'No screen time data yet.',
              'Данных об экранном времени пока нет.',
              'Экран уақыты туралы деректер әзірге жоқ.',
            ),
          )
        else
          _UsageBars(days: _insights.week, language: _language),
      ],
    ),
  );
  List<ActivityEntry> get _sortedEvents =>
      [..._insights.events]..sort((a, b) => b.at.compareTo(a.at));
  Widget _eventsCard({required int limit}) => _card(
    _sortedEvents.isEmpty
        ? _sub(
            _insights.historyReady
                ? tr(
                    'No activity yet.',
                    'Пока нет событий.',
                    'Әзірге оқиға жоқ.',
                  )
                : tr(
                    'Activity history is not connected yet.',
                    'История активности пока не подключена.',
                    'Белсенділік тарихы әзірге қосылмаған.',
                  ),
          )
        : Column(
            children: [
              for (final (i, event) in _sortedEvents.take(limit).indexed) ...[
                if (i > 0) const Divider(height: 19),
                _event(event),
              ],
            ],
          ),
  );
  String _eventTitle(ActivityEntry e) => switch (e.kind) {
    ActivityKind.focusOn => tr(
      'Focus enabled',
      'Фокус включён',
      'Фокус қосылды',
    ),
    ActivityKind.focusOff => tr(
      'Focus turned off',
      'Фокус выключен',
      'Фокус өшірілді',
    ),
    ActivityKind.temporaryAccess =>
      e.appName == null
          ? tr('Temporary access', 'Временный доступ', 'Уақытша қолжетімділік')
          : '${e.appName} · ${tr('unlocked', 'доступ открыт', 'ашылды')}',
    ActivityKind.breakCompleted => tr(
      'Break completed',
      'Пауза завершена',
      'Үзіліс аяқталды',
    ),
    ActivityKind.movementCompleted =>
      e.appName == null
          ? tr('Movement completed', 'Задание завершено', 'Тапсырма аяқталды')
          : '${e.appName} · ${tr('challenge completed', 'задание выполнено', 'тапсырма орындалды')}',
  };
  Widget _event(ActivityEntry e) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        switch (e.kind) {
          ActivityKind.focusOn ||
          ActivityKind.focusOff => Icons.track_changes_rounded,
          ActivityKind.temporaryAccess => Icons.lock_open_rounded,
          _ => Icons.check_circle_outline_rounded,
        },
        color: _muted,
        size: 21,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _eventTitle(e),
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            _gap(3),
            _sub(
              [
                MaterialLocalizations.of(context)
                    .formatShortDate(e.at.toLocal()),
                MaterialLocalizations.of(context)
                    .formatTimeOfDay(TimeOfDay.fromDateTime(e.at.toLocal())),
                if (e.detail != null) e.detail!,
                if (e.minutes != null) _minutes(e.minutes),
              ].join(' · '),
              12,
            ),
          ],
        ),
      ),
      if (e.xp != null && e.xp! > 0)
        Text(
          '+${e.xp} XP',
          style: const TextStyle(
            color: _lime,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
    ],
  );
  void _openActivity() {
    var period = 0;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ValueListenableBuilder<DashboardInsights>(
          valueListenable: _insightState,
          builder: (context, insights, _) => StatefulBuilder(
            builder: (context, setLocal) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final week = DateTime(
                now.year,
                now.month,
                now.day - now.weekday + 1,
              );
              final events =
                  ([...insights.events]..sort((a, b) => b.at.compareTo(a.at)))
                      .where(
                        (e) =>
                            period == 2 ||
                            !e.at.toLocal().isBefore(
                              period == 0 ? today : week,
                            ),
                      )
                      .toList();
              return _detail(tr('Activity', 'Активность', 'Белсенділік'), [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (i, label) in [
                      tr('Today', 'Сегодня', 'Бүгін'),
                      tr('This week', 'Эта неделя', 'Осы апта'),
                      tr('All', 'Все', 'Барлығы'),
                    ].indexed)
                      ChoiceChip(
                        label: Text(label),
                        selected: period == i,
                        showCheckmark: false,
                        selectedColor: _lime,
                        labelStyle: TextStyle(color: period == i ? _bg : _ink),
                        onSelected: (_) => setLocal(() => period = i),
                      ),
                  ],
                ),
                _gap(),
                if (period == 0) ...[
                  _metric(
                    Icons.smartphone_rounded,
                    _minutes(insights.todayUsageMinutes),
                    tr(
                      'Today · Selected apps',
                      'Сегодня · Выбранные приложения',
                      'Бүгін · Таңдалған қолданбалар',
                    ),
                  ),
                  _gap(),
                  if (insights.usageByApp.isNotEmpty) ...[
                    _section(
                      tr('By app', 'По приложениям', 'Қолданбалар бойынша'),
                    ),
                    _card(
                      Column(
                        children: [
                          for (final entry in insights.usageByApp.entries) ...[
                            _appLine(_app(entry.key), _minutes(entry.value)),
                            _gap(8),
                          ],
                        ],
                      ),
                    ),
                    _gap(),
                  ],
                ],
                _section(tr('History', 'История', 'Тарих')),
                if (events.isEmpty)
                  _card(
                    _sub(
                      insights.historyReady
                          ? tr(
                              'No events for this period.',
                              'Нет событий за этот период.',
                              'Бұл кезеңде оқиға жоқ.',
                            )
                          : tr(
                              'History is not connected yet.',
                              'История пока не подключена.',
                              'Тарих әзірге қосылмаған.',
                            ),
                    ),
                  )
                else
                  _card(
                    Column(
                      children: [
                        for (final (i, e) in events.indexed) ...[
                          if (i > 0) const Divider(height: 22),
                          _event(e),
                        ],
                      ],
                    ),
                  ),
                _gap(),
                _section(tr('Last 7 days', 'Последние 7 дней', 'Соңғы 7 күн')),
                _card(
                  insights.week.isEmpty
                      ? _sub(
                          tr(
                            'No screen time data yet.',
                            'Данных пока нет.',
                            'Деректер әзірге жоқ.',
                          ),
                        )
                      : _UsageBars(days: insights.week, language: _language),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  void _openLevel() {
    final xp = _insights.totalXp;
    final level = xp == null ? null : DashboardLevel.fromXp(xp);
    final entries = _sortedEvents
        .where((e) => e.xp != null && e.xp! > 0)
        .toList();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _detail(tr('Your level', 'Твой уровень', 'Деңгейің'), [
          _levelCard(),
          if (level != null) ...[
            _gap(12),
            _sub(
              '${level.remaining} XP ${tr('to Level', 'до уровня', 'келесі деңгейге')} ${level.level + 1}',
            ),
          ],
          _gap(),
          _section(tr('XP history', 'История XP', 'XP тарихы')),
          _card(
            entries.isEmpty
                ? _sub(
                    tr(
                      'No recorded XP events yet.',
                      'Записей о XP пока нет.',
                      'XP жазбалары әзірге жоқ.',
                    ),
                  )
                : Column(
                    children: [
                      for (final (i, e) in entries.indexed) ...[
                        if (i > 0) const Divider(height: 22),
                        _event(e),
                      ],
                    ],
                  ),
          ),
          _gap(),
          _note(
            tr(
              'XP is shown only when recorded by the progress system. No points are lost for stopping a challenge or taking a break.',
              'XP отображается только по записям системы прогресса. За отмену задания или отдых очки не снимаются.',
              'XP ілгерілеу жүйесінде тіркелгенде ғана көрсетіледі. Тапсырманы тоқтату немесе демалу үшін ұпай алынбайды.',
            ),
          ),
        ]),
      ),
    );
  }

  Widget _detail(String title, List<Widget> widgets) => Theme(
    data: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: _lime,
        onPrimary: _bg,
        surface: _surface,
        onSurface: _ink,
        outline: _border,
      ),
    ),
    child: Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.demo)
              _note(
                tr(
                  'DEMO · example data',
                  'ДЕМО · пример данных',
                  'ДЕМО · үлгі деректер',
                ),
              ),
            ...widgets,
          ],
        ),
      ),
    ),
  );
}

class _UsageBars extends StatelessWidget {
  const _UsageBars({required this.days, required this.language});
  final List<UsageDay> days;
  final DashboardLanguage language;
  @override
  Widget build(BuildContext context) {
    // Use only supplied observations, no zero-filling unknown days.
    final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));
    final shown = sorted.length > 7
        ? sorted.sublist(sorted.length - 7)
        : sorted;
    final max = shown.fold<int>(1, (m, d) => d.minutes > m ? d.minutes : m);
    final labels = switch (language) {
      DashboardLanguage.en => ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      DashboardLanguage.ru => ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'],
      DashboardLanguage.kk => ['Дс', 'Сс', 'Ср', 'Бс', 'Жм', 'Сб', 'Жс'],
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final d in shown)
          Expanded(
            child: Semantics(
              label:
                  '${MaterialLocalizations.of(context).formatShortDate(d.date)}: ${d.minutes} min',
              child: Column(
                children: [
                  Text(
                    '${d.minutes}',
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height:
                        82 * (d.minutes / max).clamp(0.0, 1.0).toDouble() + 2,
                    width: 20,
                    decoration: BoxDecoration(
                      color: d == shown.last ? _lime : const Color(0xFF40552E),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[d.date.weekday - 1],
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BreakScreen extends StatefulWidget {
  const _BreakScreen({required this.language});
  final DashboardLanguage language;
  @override
  State<_BreakScreen> createState() => _BreakState();
}

class _BreakState extends State<_BreakScreen> {
  late final DateTime _end = DateTime.now().add(const Duration(minutes: 1));
  Timer? _timer;
  int _remaining = 60;
  String tr(String en, String ru, String kk) => switch (widget.language) {
    DashboardLanguage.en => en,
    DashboardLanguage.ru => ru,
    DashboardLanguage.kk => kk,
  };
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final s = (_end.difference(DateTime.now()).inMilliseconds / 1000)
          .ceil()
          .clamp(0, 60)
          .toInt();
      if (s != _remaining) setState(() => _remaining = s);
      if (s == 0) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: _bg,
      foregroundColor: _ink,
      title: Text(tr('Mindful break', 'Спокойная пауза', 'Тыныш үзіліс')),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _remaining == 0
                    ? tr(
                        'Break complete.',
                        'Пауза завершена.',
                        'Үзіліс аяқталды.',
                      )
                    : tr(
                        'Put the phone aside if you like.',
                        'Можно отложить телефон.',
                        'Қаласаң, телефонды қоя тұр.',
                      ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 16),
              ),
              const SizedBox(height: 24),
              if (_remaining == 0)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _lime,
                    foregroundColor: _bg,
                  ),
                  child: Text(tr('Done', 'Готово', 'Дайын')),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  tr('Exit', 'Выйти', 'Шығу'),
                  style: const TextStyle(color: _muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
