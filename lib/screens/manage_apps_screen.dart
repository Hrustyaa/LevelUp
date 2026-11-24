import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/android_app_catalog.dart';
import '../data/dashboard_data.dart' show DashboardLanguage;

class ManageAppsScreen extends StatefulWidget {
  const ManageAppsScreen({
    super.key,
    required this.loadApps,
    required this.initialSelectedIds,
    required this.onSave,
    this.language = DashboardLanguage.en,
  });

  final Future<List<SelectableApp>> Function() loadApps;
  final Set<String> initialSelectedIds;
  final FutureOr<void> Function(Set<String>) onSave;
  final DashboardLanguage language;

  @override
  State<ManageAppsScreen> createState() => _ManageAppsScreenState();
}

class _ManageAppsScreenState extends State<ManageAppsScreen> {
  static const _bg = Color(0xFF0A0F10);
  static const _surface = Color(0xFF111718);
  static const _lime = Color(0xFFC7FA5B);
  static const _ink = Color(0xFFF7F8F8);
  static const _muted = Color(0xFFB0B8BA);
  static const _border = Color(0xFF293334);
  static const _searchSurface = Color(0xFF161E20);

  final _search = TextEditingController();
  final Set<String> _selected = {};
  List<SelectableApp> _apps = [];
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  String _tr(String en, String ru, String kk) => switch (widget.language) {
    DashboardLanguage.en => en,
    DashboardLanguage.ru => ru,
    DashboardLanguage.kk => kk,
  };

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelectedIds);
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final list = await widget.loadApps();
      if (!mounted) return;
      final unique = <String, SelectableApp>{};
      for (final a in list) {
        if (a.packageId.trim().isNotEmpty && a.name.trim().isNotEmpty) {
          unique[a.packageId] = a;
        }
      }
      setState(() {
        _apps = unique.values.toList();
        _selected.retainAll(unique.keys);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _save() async {
    if (_loading || _failed || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(Set.unmodifiable(_selected));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Could not save the app list. Try again.',
              'Не удалось сохранить список. Попробуй ещё раз.',
              'Тізімді сақтау мүмкін болмады. Қайталап көріңіз.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(String packageId) {
    if (_saving) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.add(packageId)) {
        _selected.remove(packageId);
      }
    });
  }

  Widget _buildAppIcon(SelectableApp app, {double size = 40}) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.5;
    final pixelSize = (size * dpr).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: app.icon == null || app.icon!.isEmpty
          ? Container(
              width: size,
              height: size,
              color: _border,
              child: const Icon(Icons.apps_rounded, color: _muted, size: 22),
            )
          : Image.memory(
              app.icon!,
              width: size,
              height: size,
              cacheWidth: pixelSize,
              cacheHeight: pixelSize,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: size,
                height: size,
                color: _border,
                child: const Icon(Icons.apps_rounded, color: _muted, size: 22),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _apps
        .where((a) => a.name.toLowerCase().contains(query))
        .toList();

    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          title: Text(
            _tr(
              'Manage protected apps',
              'Выбор приложений',
              'Қолданбаларды басқару',
            ),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: _ink),
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _search,
                  style: const TextStyle(color: _ink, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _tr(
                      'Search apps...',
                      'Поиск приложений...',
                      'Қолданбаларды іздеу...',
                    ),
                    hintStyle: const TextStyle(color: _muted, fontSize: 14),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _muted,
                      size: 20,
                    ),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              color: _muted,
                              size: 18,
                            ),
                            onPressed: () => _search.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: _searchSurface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: _lime),
                    ),
                  ),
                ),
              ),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator(color: _lime)),
                )
              else if (_failed)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _tr(
                            'Could not load installed apps.',
                            'Не удалось загрузить список приложений.',
                            'Қолданбалар тізімін жүктеу мүмкін болмады.',
                          ),
                          style: const TextStyle(color: _muted, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _load,
                          child: Text(_tr('Retry', 'Повторить', 'Қайталау')),
                        ),
                      ],
                    ),
                  ),
                )
              else if (visible.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      _tr(
                        'No matching apps found.',
                        'Приложения не найдены.',
                        'Қолданбалар табылмады.',
                      ),
                      style: const TextStyle(color: _muted, fontSize: 14),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: _border, height: 1),
                    itemBuilder: (context, index) {
                      final app = visible[index];
                      final isChecked = _selected.contains(app.packageId);
                      return InkWell(
                        onTap: () => _toggle(app.packageId),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              _buildAppIcon(app),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: _ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      app.packageId,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: _muted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: isChecked,
                                activeColor: _lime,
                                checkColor: _bg,
                                side: const BorderSide(
                                  color: _border,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                onChanged: (_) => _toggle(app.packageId),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (!keyboardVisible)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    color: _surface,
                    border: Border(top: BorderSide(color: _border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selected.length} ${_tr('apps selected', 'прилож. выбрано', 'қолданба таңдалды')}',
                            style: const TextStyle(fontSize: 13, color: _muted),
                          ),
                        ),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _lime,
                              foregroundColor: _bg,
                              minimumSize: const Size(120, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: _loading || _failed || _saving
                                ? null
                                : _save,
                            child: Text(
                              _saving
                                  ? _tr('Saving…', 'Сохранение…', 'Сақталуда…')
                                  : _tr('Save changes', 'Сохранить', 'Сақтау'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
