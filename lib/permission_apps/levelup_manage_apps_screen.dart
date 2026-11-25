import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart';
import 'permission_apps_models.dart';

/// Single-target app picker for *already-installed, supported* Android apps.
/// The screen does not activate Focus or make a MethodChannel call itself.
/// Native app catalog and target persistence are injected from the host.
class LevelUpManageAppsScreen extends StatefulWidget {
  const LevelUpManageAppsScreen({
    super.key,
    required this.language,
    required this.loadApps,
    required this.loadSelectedTarget,
    required this.saveTarget,
  });

  final DashboardLanguage language;
  final LevelUpAppsLoader loadApps;
  final LevelUpCurrentTargetLoader loadSelectedTarget;
  final LevelUpTargetSaver saveTarget;

  @override
  State<LevelUpManageAppsScreen> createState() =>
      _LevelUpManageAppsScreenState();
}

class _LevelUpManageAppsScreenState extends State<LevelUpManageAppsScreen> {
  final TextEditingController _search = TextEditingController();
  List<LevelUpInstalledApp> _apps = const [];
  String? _initialTarget;
  String? _draftTarget;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  int _loadEpoch = 0;

  String t(String ru, String en, String kk) =>
      levelUpAccessTr(widget.language, ru, en, kk);

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_loadEpoch;
    _search.removeListener(_searchChanged);
    _search.dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final loadedApps = await widget.loadApps();
      final target = await widget.loadSelectedTarget();
      if (!mounted || epoch != _loadEpoch) {
        return;
      }
      final apps = eligibleInstalledApps(loadedApps);
      setState(() {
        _apps = apps;
        _initialTarget = target;
        // Preserve no inaccessible target as an actionable selection.
        _draftTarget = apps.any((app) => app.packageId == target)
            ? target
            : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _loadEpoch) return;
      setState(() {
        _apps = const [];
        _initialTarget = null;
        _draftTarget = null;
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  bool get _canSave =>
      !_loading &&
      !_loadFailed &&
      !_saving &&
      _draftTarget != null &&
      _draftTarget != _initialTarget;

  Future<void> _save() async {
    final id = _draftTarget;
    if (!_canSave || id == null) return;
    setState(() => _saving = true);
    try {
      // The host must call the existing native target persistence operation,
      // await its acknowledgement, and throw if Android rejects it.
      await widget.saveTarget(id);
      if (!mounted) return;
      setState(() {
        _initialTarget = id;
        _saving = false;
      });
      Navigator.of(context).pop<String>(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Не удалось сохранить выбор. Попробуй ещё раз.',
              'Could not save the selection. Try again.',
              'Таңдауды сақтау мүмкін болмады. Қайталап көр.',
            ),
          ),
        ),
      );
    }
  }

  Widget _appRow(LevelUpInstalledApp app) {
    final isSelected = _draftTarget == app.packageId;
    final bytes = app.iconPng;
    return InkWell(
      key: ValueKey('access_app_${app.packageId}'),
      onTap: _saving
          ? null
          : () {
              FocusScope.of(context).unfocus();
              setState(() => _draftTarget = app.packageId);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF202728),
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null || bytes.isEmpty
                  ? const Icon(
                      Icons.apps_outlined,
                      color: LevelUpAccessPalette.secondary,
                      size: 21,
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.apps_outlined,
                        color: LevelUpAccessPalette.secondary,
                      ),
                    ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                app.displayName,
                style: const TextStyle(
                  color: LevelUpAccessPalette.foreground,
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? LevelUpAccessPalette.accent
                  : LevelUpAccessPalette.secondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matching = _apps
        .where(
          (app) =>
              app.displayName.toLowerCase().contains(query) ||
              app.packageId.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final selectedName = _apps
        .where((app) => app.packageId == _draftTarget)
        .map((app) => app.displayName)
        .firstOrNull;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Theme(
      data: levelUpAccessTheme(),
      child: Scaffold(
        backgroundColor: LevelUpAccessPalette.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            t('Выбор приложения', 'Choose an app', 'Қолданбаны таңдау'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      t(
                        'Выбери приложение, которое хочешь ограничить.',
                        'Choose the app you want to limit.',
                        'Шектегің келетін қолданбаны таңда.',
                      ),
                      style: const TextStyle(
                        color: LevelUpAccessPalette.secondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t(
                        'Сейчас можно выбрать одно приложение. Focus можно отключить в любой момент.',
                        'One app can be selected for now. Focus can be turned off at any time.',
                        'Әзірге бір қолданба таңдалады. Фокусты кез келген уақытта өшіруге болады.',
                      ),
                      style: const TextStyle(
                        color: LevelUpAccessPalette.secondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const ValueKey('access_app_search'),
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: LevelUpAccessPalette.foreground,
                      ),
                      decoration: InputDecoration(
                        hintText: t(
                          'Найти приложение',
                          'Find an app',
                          'Қолданбаны іздеу',
                        ),
                        hintStyle: const TextStyle(
                          color: LevelUpAccessPalette.secondary,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: LevelUpAccessPalette.secondary,
                        ),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: t(
                                  'Очистить поиск',
                                  'Clear search',
                                  'Іздеуді тазарту',
                                ),
                                onPressed: _search.clear,
                                icon: const Icon(
                                  Icons.close,
                                  color: LevelUpAccessPalette.secondary,
                                ),
                              ),
                        filled: true,
                        fillColor: LevelUpAccessPalette.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: LevelUpAccessPalette.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: LevelUpAccessPalette.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      t(
                        'УСТАНОВЛЕННЫЕ ПРИЛОЖЕНИЯ',
                        'INSTALLED APPS',
                        'ОРНАТЫЛҒАН ҚОЛДАНБАЛАР',
                      ),
                      style: const TextStyle(
                        color: LevelUpAccessPalette.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: LevelUpAccessPalette.accent,
                              ),
                            )
                          : _loadFailed
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t(
                                      'Не удалось загрузить приложения.',
                                      'Could not load apps.',
                                      'Қолданбалар жүктелмеді.',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: LevelUpAccessPalette.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    key: const ValueKey('access_app_retry'),
                                    onPressed: _load,
                                    child: Text(
                                      t('Повторить', 'Retry', 'Қайталау'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _apps.isEmpty
                          ? Center(
                              child: Text(
                                t(
                                  'Нет поддерживаемых установленных приложений.',
                                  'No supported installed apps were found.',
                                  'Қолдайтын орнатылған қолданба табылмады.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: LevelUpAccessPalette.secondary,
                                ),
                              ),
                            )
                          : matching.isEmpty
                          ? Center(
                              child: Text(
                                t(
                                  'Ничего не найдено.',
                                  'No results.',
                                  'Ештеңе табылмады.',
                                ),
                                style: const TextStyle(
                                  color: LevelUpAccessPalette.secondary,
                                ),
                              ),
                            )
                          : ListView.separated(
                              key: const ValueKey('access_app_list'),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: matching.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                color: LevelUpAccessPalette.border,
                              ),
                              itemBuilder: (_, index) =>
                                  _appRow(matching[index]),
                            ),
                    ),
                    if (!keyboardVisible) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            t('Выбрано', 'Selected', 'Таңдалды'),
                            style: const TextStyle(
                              color: LevelUpAccessPalette.secondary,
                            ),
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              selectedName ?? t('Ничего', 'None', 'Ештеңе'),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: LevelUpAccessPalette.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_initialTarget != null &&
                          !_apps.any(
                            (app) => app.packageId == _initialTarget,
                          )) ...[
                        const SizedBox(height: 6),
                        Text(
                          t(
                            'Ранее выбранное приложение сейчас недоступно.',
                            'Previously selected app is no longer available.',
                            'Алдыңғы таңдалған қолданба қолжетімсіз.',
                          ),
                          style: const TextStyle(
                            color: LevelUpAccessPalette.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          key: const ValueKey('access_save_app'),
                          onPressed: _canSave ? _save : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: LevelUpAccessPalette.accent,
                            foregroundColor: LevelUpAccessPalette.background,
                            disabledBackgroundColor:
                                LevelUpAccessPalette.border,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: LevelUpAccessPalette.background,
                                  ),
                                )
                              : Text(
                                  t(
                                    'Сохранить выбор',
                                    'Save selection',
                                    'Таңдауды сақтау',
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
