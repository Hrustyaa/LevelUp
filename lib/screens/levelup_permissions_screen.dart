import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/levelup_permissions.dart';
import 'levelup_welcome_screen.dart' show LevelUpLanguage;

class LevelUpPermissionsScreen extends StatefulWidget {
  const LevelUpPermissionsScreen({
    super.key,
    required this.gateway,
    required this.onFinish,
    required this.onBack,
    this.language = LevelUpLanguage.en,
  });
  final LevelUpPermissionGateway gateway;
  final FutureOr<void> Function(PermissionsOutcome) onFinish;
  final VoidCallback onBack;
  final LevelUpLanguage language;
  @override
  State<LevelUpPermissionsScreen> createState() => _PermissionsState();
}

class _PermissionsState extends State<LevelUpPermissionsScreen>
    with WidgetsBindingObserver {
  static const bg = Color(0xFF0A0F10),
      surface = Color(0xFF111718),
      accent = Color(0xFFC7FA5B),
      ink = Color(0xFFF7F8F8),
      muted = Color(0xFFB0B8BA),
      border = Color(0xFF293334);
  final _scroll = ScrollController();
  Map<LevelUpPermission, PermissionState> _states = {};
  bool _loading = true, _failed = false, _leaving = false, _dialogOpen = false;
  LevelUpPermission? _busy;
  int _readId = 0;
  _Copy get c => _copies[widget.language]!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final id = ++_readId;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final next = await widget.gateway.read();
      if (!mounted || id != _readId) return;
      setState(() {
        _states = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _readId) return;
      setState(() {
        _states = {};
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _request(LevelUpPermission p) async {
    if (_busy != null ||
        _dialogOpen ||
        _loading ||
        _leaving ||
        _states[p] != PermissionState.denied) {
      return;
    }
    HapticFeedback.selectionClick();
    if (p == LevelUpPermission.accessibility || p == LevelUpPermission.usage) {
      _dialogOpen = true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(c.name(p)),
          content: SingleChildScrollView(
            child: Text(
              p == LevelUpPermission.accessibility
                  ? c.accessibilityDisclosure
                  : c.usageDisclosure,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(c.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(c.openSettings),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (!mounted || ok != true) return;
    }
    setState(() => _busy = p);
    try {
      await widget.gateway.request(p);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(c.requestError)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        await _refresh();
      }
    }
  }

  Future<void> _settings() async {
    try {
      await widget.gateway.openAppSettings();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(c.requestError)));
      }
    }
  }

  Future<void> _finish(bool skipped) async {
    if (_leaving || _busy != null || _dialogOpen) return;
    setState(() => _leaving = true);
    // Recheck before passing the outcome. An unavailable state is never a grant.
    if (!skipped) await _refresh();
    if (!mounted) return;
    try {
      await widget.onFinish(
        PermissionsOutcome(skipped: skipped, states: _states),
      );
    } catch (_) {
      if (!mounted) return;
      final text = switch (widget.language) {
        LevelUpLanguage.en => 'Could not save setup. Try again.',
        LevelUpLanguage.ru =>
          'Не удалось сохранить настройку. Попробуй ещё раз.',
        LevelUpLanguage.kk =>
          'Баптауды сақтау мүмкін болмады. Қайталап көріңіз.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
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
              builder: (context, size) {
                final footerInList =
                    size.maxHeight < 440 ||
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
                              thumbColor: border,
                              thickness: 3,
                              radius: const Radius.circular(4),
                              child: ListView(
                                controller: _scroll,
                                padding: const EdgeInsets.only(
                                  top: 22,
                                  bottom: 12,
                                ),
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      text: c.title1,
                                      children: [
                                        TextSpan(
                                          text: c.title2,
                                          style: const TextStyle(color: accent),
                                        ),
                                      ],
                                    ),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: ink,
                                      letterSpacing: -.7,
                                      height: 1.18,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _muted(c.subtitle, 15),
                                  const SizedBox(height: 20),
                                  if (_loading)
                                    const LinearProgressIndicator(
                                      minHeight: 2,
                                      color: accent,
                                    ),
                                  if (_failed)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Column(
                                        children: [
                                          _muted(c.readError, 13),
                                          TextButton(
                                            onPressed: _refresh,
                                            child: Text(c.retry),
                                          ),
                                        ],
                                      ),
                                    ),
                                  for (final p in LevelUpPermission.values)
                                    _tile(p),
                                  const SizedBox(height: 8),
                                  if (!_loading &&
                                      _states[LevelUpPermission
                                              .accessibility] !=
                                          PermissionState.granted)
                                    _notice(
                                      Icons.info_outline_rounded,
                                      c.focusOff,
                                    ),
                                  if (_states.values.contains(
                                    PermissionState.denied,
                                  ))
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: _busy == null
                                            ? _settings
                                            : null,
                                        child: Text(c.manage),
                                      ),
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
            tooltip: c.back,
            onPressed: _leaving || _busy != null ? null : widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 23, color: ink),
          ),
          Expanded(
            child: Text(
              c.step,
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
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
  Widget _muted(String value, double size) => Text(
    value,
    style: TextStyle(color: muted, fontSize: size, height: 1.35),
  );
  Widget _tile(LevelUpPermission p) {
    final status = _states[p] ?? PermissionState.unknown;
    final granted = status == PermissionState.granted;
    final unavailable = status == PermissionState.unavailable;
    final icon = switch (p) {
      LevelUpPermission.accessibility => Icons.accessibility_new_rounded,
      LevelUpPermission.camera => Icons.camera_alt_outlined,
      LevelUpPermission.usage => Icons.bar_chart_rounded,
      LevelUpPermission.notifications => Icons.notifications_none_rounded,
    };
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final action = AnimatedSwitcher(
      duration: disableMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: _busy == p
          ? const SizedBox(
              key: ValueKey('loading'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            )
          : granted
          ? Semantics(
              key: const ValueKey('granted'),
              liveRegion: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: accent,
                    size: 18,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      c.granted,
                      style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : unavailable
          ? KeyedSubtree(
              key: const ValueKey('unavailable'),
              child: _muted(c.unavailable, 12),
            )
          : status == PermissionState.unknown
          ? KeyedSubtree(
              key: const ValueKey('unknown'),
              child: _muted(c.unknown, 12),
            )
          : OutlinedButton(
              key: ValueKey('permission_${p.name}'),
              onPressed: _loading || _busy != null || _leaving
                  ? null
                  : () => _request(p),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: const BorderSide(color: accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(64, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                p == LevelUpPermission.accessibility ? c.enable : c.allow,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c.name(p),
          style: const TextStyle(
            color: ink,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        _muted(c.hint(p), 13),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: granted ? const Color(0xFF526D32) : border),
        ),
        child: LayoutBuilder(
          builder: (context, limits) {
            final stack =
                limits.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 17;
            final mark = Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: unavailable ? border : const Color(0xFF202C1C),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: unavailable ? muted : accent, size: 24),
            );
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          mark,
                          const SizedBox(width: 12),
                          Expanded(child: info),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  )
                : Row(
                    children: [
                      mark,
                      const SizedBox(width: 12),
                      Expanded(child: info),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 106),
                        child: action,
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String label) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: muted, size: 18),
      const SizedBox(width: 8),
      Expanded(child: _muted(label, 12)),
    ],
  );
  Widget _footer() => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _notice(Icons.verified_user_outlined, c.safety),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('permissions_finish'),
            onPressed: _leaving || _busy != null ? null : () => _finish(false),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: bg,
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    c.finish,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
        TextButton(
          key: const ValueKey('permissions_skip'),
          onPressed: _leaving || _busy != null ? null : () => _finish(true),
          style: TextButton.styleFrom(
            foregroundColor: muted,
            minimumSize: const Size(48, 44),
          ),
          child: Text(c.skip),
        ),
      ],
    ),
  );
}

class _Copy {
  const _Copy({
    required this.step,
    required this.title1,
    required this.title2,
    required this.subtitle,
    required this.names,
    required this.hints,
    required this.enable,
    required this.allow,
    required this.granted,
    required this.unavailable,
    required this.unknown,
    required this.safety,
    required this.finish,
    required this.skip,
    required this.back,
    required this.cancel,
    required this.openSettings,
    required this.manage,
    required this.retry,
    required this.focusOff,
    required this.readError,
    required this.requestError,
    required this.accessibilityDisclosure,
    required this.usageDisclosure,
  });
  final String step,
      title1,
      title2,
      subtitle,
      enable,
      allow,
      granted,
      unavailable,
      unknown,
      safety,
      finish,
      skip,
      back,
      cancel,
      openSettings,
      manage,
      retry,
      focusOff,
      readError,
      requestError,
      accessibilityDisclosure,
      usageDisclosure;
  final List<String> names, hints;
  String name(LevelUpPermission p) => names[p.index];
  String hint(LevelUpPermission p) => hints[p.index];
}

const _copies = {
  LevelUpLanguage.en: _Copy(
    step: 'STEP 3 OF 3',
    title1: 'Almost ',
    title2: 'ready.',
    subtitle: 'Choose the permissions you want to enable.',
    names: ['Accessibility', 'Camera', 'Usage access', 'Notifications'],
    hints: [
      'Required only for Focus Mode.',
      'Optional: movement challenges.',
      'Optional: screen time insights.',
      'Optional: Focus on and off alerts.',
    ],
    enable: 'Enable',
    allow: 'Allow',
    granted: 'Granted',
    unavailable: 'Not available yet',
    unknown: 'Not checked',
    safety: 'You can change permissions or turn off Focus anytime.',
    finish: 'Finish setup',
    skip: 'Skip for now',
    back: 'Back',
    cancel: 'Cancel',
    openSettings: 'Open settings',
    manage: 'Manage app permissions',
    retry: 'Try again',
    focusOff:
        'Without Accessibility access, Focus stays off. You can still finish setup.',
    readError: 'Could not check permissions.',
    requestError:
        'Could not open the permission request. Try again or use Settings.',
    accessibilityDisclosure:
        'LevelUp uses Accessibility app/window change events to detect when you open selected apps and show a voluntary focus screen. This feature does not read screen text or take screenshots. Android grants a sensitive permission; only enable it if you agree. You can disable Focus and revoke access at any time.',
    usageDisclosure:
        'Usage access lets LevelUp read app usage times for screen time insights. It is optional. Only grant it if you want these insights.',
  ),
  LevelUpLanguage.ru: _Copy(
    step: 'ШАГ 3 ИЗ 3',
    title1: 'Почти ',
    title2: 'готово.',
    subtitle: 'Выбери разрешения, которые хочешь предоставить.',
    names: [
      'Специальные возможности',
      'Камера',
      'Данные об использовании',
      'Уведомления',
    ],
    hints: [
      'Нужны только для режима фокуса.',
      'Необязательно: задания с движением.',
      'Необязательно: экранное время.',
      'Необязательно: уведомления о включении и выключении фокуса.',
    ],
    enable: 'Включить',
    allow: 'Разрешить',
    granted: 'Разрешено',
    unavailable: 'Пока недоступно',
    unknown: 'Не проверено',
    safety: 'Разрешения можно изменить, а фокус — отключить в любой момент.',
    finish: 'Завершить настройку',
    skip: 'Пока пропустить',
    back: 'Назад',
    cancel: 'Отмена',
    openSettings: 'Открыть настройки',
    manage: 'Настройки разрешений',
    retry: 'Повторить',
    focusOff:
        'Без специальных возможностей фокус останется выключенным. Настройку можно завершить.',
    readError: 'Не удалось проверить разрешения.',
    requestError:
        'Не удалось открыть запрос разрешения. Повтори или открой настройки.',
    accessibilityDisclosure:
        'LevelUp использует события смены приложения или окна, чтобы обнаружить открытие выбранных приложений и показать добровольное ограничение. Эта функция не читает текст экрана и не делает снимки. Android предоставляет чувствительное разрешение: включай его только с согласия. Фокус и доступ можно отключить в любой момент.',
    usageDisclosure:
        'Доступ к данным об использовании позволяет LevelUp получать время использования приложений для статистики. Это необязательно. Разреши доступ, только если нужна эта статистика.',
  ),
  LevelUpLanguage.kk: _Copy(
    step: '3-ҚАДАМ / 3',
    title1: 'Дайын ',
    title2: 'деуге болады.',
    subtitle: 'Бергің келетін рұқсаттарды таңда.',
    names: [
      'Арнайы мүмкіндіктер',
      'Камера',
      'Қолдану деректері',
      'Хабарландырулар',
    ],
    hints: [
      'Тек фокус режиміне қажет.',
      'Міндетті емес: қозғалыс тапсырмалары.',
      'Міндетті емес: экран уақыты.',
      'Міндетті емес: фокусты қосу және өшіру хабарландырулары.',
    ],
    enable: 'Қосу',
    allow: 'Рұқсат беру',
    granted: 'Рұқсат берілді',
    unavailable: 'Әзірге қолжетімсіз',
    unknown: 'Тексерілмеді',
    safety: 'Рұқсаттарды өзгертіп, фокусты кез келген уақытта өшіре аласың.',
    finish: 'Баптауды аяқтау',
    skip: 'Әзірге өткізіп жіберу',
    back: 'Артқа',
    cancel: 'Бас тарту',
    openSettings: 'Баптауларды ашу',
    manage: 'Рұқсаттар баптауы',
    retry: 'Қайталау',
    focusOff:
        'Арнайы мүмкіндіктерге рұқсат берілмесе, фокус өшірулі қалады. Баптауды аяқтауға болады.',
    readError: 'Рұқсаттарды тексеру мүмкін болмады.',
    requestError:
        'Рұқсат сұрауын ашу мүмкін болмады. Қайта көр немесе баптауларды аш.',
    accessibilityDisclosure:
        'LevelUp таңдалған қолданбаның ашылғанын анықтау және ерікті шектеу экранын көрсету үшін терезе ауысу оқиғаларын қолданады. Бұл функция экран мәтінін оқымайды және скриншот жасамайды. Android жүйесіндегі бұл рұқсатты тек келіссең қос. Фокус пен рұқсатты кез келген уақытта өшіруге болады.',
    usageDisclosure:
        'Бұл рұқсат экран уақытының статистикасын жасау үшін қолданбалардың қолданылу уақытын оқуға мүмкіндік береді. Міндетті емес.',
  ),
};
