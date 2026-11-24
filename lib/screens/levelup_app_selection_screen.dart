import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android_app_catalog.dart';
import 'levelup_welcome_screen.dart' show LevelUpLanguage;

typedef AppLoader = Future<List<SelectableApp>> Function();

class LevelUpAppSelectionScreen extends StatefulWidget {
  const LevelUpAppSelectionScreen({
    super.key,
    required this.loadApps,
    required this.onContinue,
    required this.onSkip,
    required this.onBack,
    this.language = LevelUpLanguage.en,
    this.initialSelectedIds = const {},
    this.onSelectionChanged,
  });
  final AppLoader loadApps;
  final ValueChanged<Set<String>> onContinue;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final LevelUpLanguage language;
  final Set<String> initialSelectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<LevelUpAppSelectionScreen> createState() => _SelectionState();
}

class _SelectionState extends State<LevelUpAppSelectionScreen> {
  static const bg = Color(0xFF0A0F10);
  static const surface = Color(0xFF111718);
  static const searchSurface = Color(0xFF1A2021);
  static const selectedSurface = Color(0xFF182119);
  static const accent = Color(0xFFC7FA5B);
  static const ink = Color(0xFFF7F8F8);
  static const muted = Color(0xFFB0B8BA);
  static const border = Color(0xFF293334);
  final _scrollController = ScrollController();
  final _search = TextEditingController();
  final Set<String> _selected = {};
  List<SelectableApp> _apps = [];
  bool _loading = true;
  bool _failed = false;
  int _request = 0;
  _Copy get c => _strings[widget.language]!;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelectedIds);
    _search.addListener(_searchChanged);
    _load();
  }

  void _searchChanged() => setState(() {});

  @override
  void dispose() {
    _search.removeListener(_searchChanged);
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final apps = await widget.loadApps();
      if (!mounted || request != _request) return;
      final unique = <String, SelectableApp>{};
      for (final app in apps) {
        if (app.packageId.trim().isNotEmpty && app.name.trim().isNotEmpty) {
          unique[app.packageId] = app;
        }
      }
      final installed = unique.values.toList(growable: false);
      setState(() {
        _apps = installed;
        _selected.retainAll(unique.keys);
        _loading = false;
      });
      _notify();
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _notify() =>
      widget.onSelectionChanged?.call(Set.unmodifiable(_selected));
  void _toggle(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
    _notify();
  }

  void _leave(VoidCallback action) {
    FocusScope.of(context).unfocus();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _apps
        .where((app) => app.name.toLowerCase().contains(query))
        .toList();
    final suggested = visible.where((a) => a.suggested).toList();
    final other = visible.where((a) => !a.suggested).toList();
    final enabled = !_loading && !_failed && _selected.isNotEmpty;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final selectedCount = _loading || _failed ? 0 : _selected.length;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largeText =
                  MediaQuery.textScalerOf(context).scale(14) >= 28;
              final footerInList =
                  !keyboardVisible &&
                  (constraints.maxHeight < 420 || largeText);
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _header(),
                        Expanded(
                          child: RawScrollbar(
                            controller: _scrollController,
                            thumbColor: border,
                            radius: const Radius.circular(4),
                            thickness: 3,
                            padding: const EdgeInsets.only(right: 2),
                            child: ListView(
                              controller: _scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.only(
                                top: 20,
                                bottom: 12,
                              ),
                              children: [
                                Text.rich(
                                  TextSpan(
                                    text: c.title1,
                                    children: [
                                      TextSpan(
                                        text: ' ${c.title2}',
                                        style: const TextStyle(color: accent),
                                      ),
                                    ],
                                  ),
                                  style: const TextStyle(
                                    color: ink,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.8,
                                    height: 1.18,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  c.subtitle,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _searchField(),
                                const SizedBox(height: 18),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      query.isNotEmpty
                                          ? c.results
                                          : suggested.isNotEmpty
                                          ? c.suggested
                                          : c.allApps,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minWidth: 84,
                                      ),
                                      child: Container(
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selectedSurface,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Semantics(
                                          liveRegion: true,
                                          child: Text(
                                            c.count(selectedCount),
                                            style: const TextStyle(
                                              color: accent,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                              fontFeatures: [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_loading)
                                  _message(c.loading, loading: true)
                                else if (_failed)
                                  _message(c.error, retry: true)
                                else if (_apps.isEmpty)
                                  _message(c.noApps, retry: true)
                                else if (visible.isEmpty)
                                  _message(c.noResults, onClear: _search.clear)
                                else if (query.isNotEmpty)
                                  ...visible.map(_tile)
                                else ...[
                                  ...suggested.map(_tile),
                                  if (other.isNotEmpty &&
                                      suggested.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      c.allApps,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  ...other.map(_tile),
                                ],
                                if (footerInList) _footer(enabled),
                              ],
                            ),
                          ),
                        ),
                        if (!keyboardVisible && !footerInList) _footer(enabled),
                      ],
                    ),
                  ),
                ),
              );
            },
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
            onPressed: () => _leave(widget.onBack),
            icon: const Icon(Icons.arrow_back_rounded, color: ink, size: 23),
          ),
          Expanded(
            child: Text(
              c.step,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
      Row(
        children: [
          for (var step = 0; step < 3; step++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: step == 2 ? 0 : 4),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: step == 0 ? accent : border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _searchField() => TextField(
    controller: _search,
    style: const TextStyle(color: ink, fontSize: 15),
    cursorColor: accent,
    textInputAction: TextInputAction.search,
    onSubmitted: (_) => FocusScope.of(context).unfocus(),
    decoration: InputDecoration(
      hintText: c.search,
      hintStyle: const TextStyle(color: muted),
      prefixIcon: const Icon(Icons.search_rounded, color: muted, size: 22),
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
              tooltip: c.clear,
              onPressed: _search.clear,
              icon: const Icon(Icons.close_rounded, color: muted),
            ),
      filled: true,
      fillColor: searchSurface,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: accent, width: 1),
      ),
    ),
  );

  Widget _message(
    String message, {
    bool loading = false,
    bool retry = false,
    VoidCallback? onClear,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        if (loading) ...[
          const SizedBox(
            width: 25,
            height: 25,
            child: CircularProgressIndicator(color: accent, strokeWidth: 2),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 14),
        ),
        if (retry)
          TextButton(
            onPressed: _load,
            child: Text(c.retry, style: const TextStyle(color: accent)),
          ),
        if (onClear != null)
          TextButton(
            onPressed: onClear,
            child: Text(c.clear, style: const TextStyle(color: accent)),
          ),
      ],
    ),
  );

  Widget _tile(SelectableApp app) {
    final checked = _selected.contains(app.packageId);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        checked: checked,
        onTap: () => _toggle(app.packageId),
        label: '${app.name}, ${c.category(app.category)}',
        child: ExcludeSemantics(
          child: AnimatedContainer(
            key: ValueKey(app.packageId),
            duration: duration,
            decoration: BoxDecoration(
              color: checked ? selectedSurface : surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: checked ? accent : border),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                splashColor: accent.withValues(alpha: 0.12),
                highlightColor: accent.withValues(alpha: 0.06),
                onTap: () => _toggle(app.packageId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _appIcon(app),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.name,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.category(app.category),
                              style: const TextStyle(
                                color: muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AnimatedContainer(
                        duration: duration,
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: checked ? accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: checked ? accent : const Color(0xFF5D696A),
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: checked
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey(true),
                                  color: bg,
                                  size: 19,
                                )
                              : const SizedBox(
                                  key: ValueKey(false),
                                  width: 19,
                                  height: 19,
                                ),
                        ),
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

  Widget _appIcon(SelectableApp app) {
    final fallback = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: searchSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.apps_rounded, color: muted, size: 23),
    );
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.5;
    final pixelSize = (40 * dpr).round();
    return app.icon == null || app.icon!.isEmpty
        ? fallback
        : ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.memory(
              app.icon!,
              width: 40,
              height: 40,
              cacheWidth: pixelSize,
              cacheHeight: pixelSize,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => fallback,
            ),
          );
  }

  Widget _footer(bool enabled) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottomPadding > 0 ? 0 : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined, size: 17, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  c.hint,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('continue'),
              onPressed: enabled
                  ? () => _leave(
                      () => widget.onContinue(Set.unmodifiable(_selected)),
                    )
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: bg,
                disabledBackgroundColor: border,
                disabledForegroundColor: muted,
                minimumSize: const Size(0, 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      c.next(_selected.length),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 19),
                ],
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('skip'),
            onPressed: () => _leave(widget.onSkip),
            style: TextButton.styleFrom(
              foregroundColor: muted,
              minimumSize: const Size(48, 44),
            ),
            child: Text(
              c.skip,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Copy {
  const _Copy({
    required this.step,
    required this.title1,
    required this.title2,
    required this.subtitle,
    required this.search,
    required this.clear,
    required this.suggested,
    required this.allApps,
    required this.results,
    required this.hint,
    required this.skip,
    required this.back,
    required this.loading,
    required this.error,
    required this.noApps,
    required this.noResults,
    required this.retry,
    required this.categories,
    required this.language,
  });
  final String step,
      title1,
      title2,
      subtitle,
      search,
      clear,
      suggested,
      allApps,
      results,
      hint,
      skip,
      back,
      loading,
      error,
      noApps,
      noResults,
      retry;
  final List<String> categories;
  final LevelUpLanguage language;
  String category(AppCategory c) => categories[c.index];
  String _ruApps(int n) => n % 100 >= 11 && n % 100 <= 14
      ? 'приложений'
      : n % 10 == 1
      ? 'приложение'
      : (n % 10 >= 2 && n % 10 <= 4 ? 'приложения' : 'приложений');
  String count(int n) => switch (language) {
    LevelUpLanguage.en => '$n selected',
    LevelUpLanguage.ru => 'Выбрано: $n',
    LevelUpLanguage.kk => '$n таңдалды',
  };
  String next(int n) => switch (language) {
    LevelUpLanguage.en =>
      n == 0 ? 'Continue' : 'Continue · $n ${n == 1 ? 'app' : 'apps'}',
    LevelUpLanguage.ru => n == 0 ? 'Продолжить' : 'Далее · $n ${_ruApps(n)}',
    LevelUpLanguage.kk => n == 0 ? 'Жалғастыру' : 'Жалғастыру · $n қолданба',
  };
}

const _strings = {
  LevelUpLanguage.en: _Copy(
    language: LevelUpLanguage.en,
    step: 'STEP 1 OF 3',
    title1: 'Your time.',
    title2: 'Your choice.',
    subtitle: 'Choose the apps you want to spend less time on.',
    search: 'Search apps',
    clear: 'Clear search',
    suggested: 'Suggested apps',
    allApps: 'Available apps',
    results: 'Search results',
    hint: 'You can change your selection anytime.',
    skip: 'Skip for now',
    back: 'Back',
    loading: 'Loading apps…',
    error: 'Could not load apps.',
    noApps: 'No supported apps found.',
    noResults: 'No matching apps.',
    retry: 'Try again',
    categories: ['Social media', 'Entertainment', 'Messaging', 'Other'],
  ),
  LevelUpLanguage.ru: _Copy(
    language: LevelUpLanguage.ru,
    step: 'ШАГ 1 ИЗ 3',
    title1: 'Твоё время.',
    title2: 'Твой выбор.',
    subtitle: 'Выбери приложения, в которых хочешь проводить меньше времени.',
    search: 'Поиск приложений',
    clear: 'Очистить поиск',
    suggested: 'Рекомендуемые',
    allApps: 'Доступные приложения',
    results: 'Результаты поиска',
    hint: 'Ты можешь изменить выбор в любой момент.',
    skip: 'Пока пропустить',
    back: 'Назад',
    loading: 'Загрузка приложений…',
    error: 'Не удалось загрузить приложения.',
    noApps: 'Нет поддерживаемых приложений.',
    noResults: 'Ничего не найдено.',
    retry: 'Повторить',
    categories: ['Социальные сети', 'Развлечения', 'Общение', 'Другое'],
  ),
  LevelUpLanguage.kk: _Copy(
    language: LevelUpLanguage.kk,
    step: '1-ҚАДАМ / 3',
    title1: 'Уақытың.',
    title2: 'Таңдауың.',
    subtitle: 'Уақытты азырақ өткізгің келетін қолданбаларды таңда.',
    search: 'Қолданбаларды іздеу',
    clear: 'Іздеуді тазарту',
    suggested: 'Ұсынылған қолданбалар',
    allApps: 'Қолжетімді қолданбалар',
    results: 'Іздеу нәтижелері',
    hint: 'Таңдауыңды кез келген уақытта өзгерте аласың.',
    skip: 'Әзірге өткізіп жіберу',
    back: 'Артқа',
    loading: 'Қолданбалар жүктелуде…',
    error: 'Қолданбаларды жүктеу мүмкін болмады.',
    noApps: 'Қолдау көрсетілетін қолданбалар табылмады.',
    noResults: 'Ештеңе табылмады.',
    retry: 'Қайталау',
    categories: ['Әлеуметтік желілер', 'Ойын-сауық', 'Хабар алмасу', 'Басқа'],
  ),
};
