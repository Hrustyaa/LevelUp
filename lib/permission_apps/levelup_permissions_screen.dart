import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart';
import '../settings/settings_permissions.dart';
import 'permission_apps_models.dart';

/// Type-specific external action. Route each permission to the appropriate
/// *existing* Android settings or permission request workflow.
typedef LevelUpPermissionOpener =
    Future<void> Function(LevelUpPermission permission);

/// Secondary screen. Do not nest it inside LevelUpHomeScreen's ListView:
/// push it as a separate MaterialPageRoute.
class LevelUpPermissionsScreen extends StatefulWidget {
  const LevelUpPermissionsScreen({
    super.key,
    required this.language,
    this.loadStates,
    this.openPermission,
    this.openApps,
  });

  final DashboardLanguage language;
  final LevelUpPermissionLoader? loadStates;
  final LevelUpPermissionOpener? openPermission;
  final Future<void> Function()? openApps;

  @override
  State<LevelUpPermissionsScreen> createState() =>
      _LevelUpPermissionsScreenState();
}

class _LevelUpPermissionsScreenState extends State<LevelUpPermissionsScreen>
    with WidgetsBindingObserver {
  LevelUpPermissionSnapshot _snapshot = const LevelUpPermissionSnapshot();
  bool _loading = false;
  bool _error = false;
  int _epoch = 0;

  String t(String ru, String en, String kk) =>
      levelUpAccessTr(widget.language, ru, en, kk);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant LevelUpPermissionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadStates != widget.loadStates) unawaited(_refresh());
  }

  @override
  void dispose() {
    ++_epoch;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final epoch = ++_epoch;
    final loader = widget.loadStates;
    if (loader == null) {
      if (mounted) {
        setState(() {
          _snapshot = const LevelUpPermissionSnapshot();
          _loading = false;
          _error = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final value = await loader();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _snapshot = value;
        _error = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        // Never retain a stale "granted" after a read failure.
        _snapshot = const LevelUpPermissionSnapshot();
        _error = true;
      });
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _open(LevelUpPermission permission) async {
    final action = widget.openPermission;
    if (action == null) return;
    try {
      await action(permission);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Не удалось открыть настройки разрешения.',
              'Could not open permission settings.',
              'Рұқсат баптауларын ашу мүмкін болмады.',
            ),
          ),
        ),
      );
    }
    if (mounted) await _refresh();
  }

  Future<void> _openApps() async {
    final action = widget.openApps;
    if (action == null) return;
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            t(
              'Не удалось открыть выбор приложения.',
              'Could not open app selection.',
              'Қолданбаны таңдау ашылмады.',
            ),
          ),
        ),
      );
    }
  }

  String _stateText(LevelUpPermission permission) =>
      switch (_snapshot.stateOf(permission)) {
        LevelUpPermissionState.granted => t(
          'Разрешено',
          'Allowed',
          'Рұқсат берілген',
        ),
        LevelUpPermissionState.denied => t(
          'Не разрешено',
          'Not allowed',
          'Рұқсат жоқ',
        ),
        LevelUpPermissionState.unknown => t(
          'Не проверено',
          'Not checked',
          'Тексерілмеген',
        ),
      };

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 23, bottom: 7),
    child: Text(
      title,
      style: const TextStyle(
        color: LevelUpAccessPalette.secondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
      ),
    ),
  );

  Widget _permissionRow(
    LevelUpPermission permission,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final granted =
        _snapshot.stateOf(permission) == LevelUpPermissionState.granted;
    final actionable = widget.openPermission != null;
    return InkWell(
      key: ValueKey('access_permission_${permission.name}'),
      onTap: actionable ? () => _open(permission) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 21,
              color: granted
                  ? LevelUpAccessPalette.accent
                  : LevelUpAccessPalette.secondary,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: LevelUpAccessPalette.foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: LevelUpAccessPalette.secondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _stateText(permission),
                    key: ValueKey('access_status_${permission.name}'),
                    style: TextStyle(
                      color: granted
                          ? LevelUpAccessPalette.accent
                          : LevelUpAccessPalette.secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (actionable)
              const Icon(
                Icons.chevron_right,
                color: LevelUpAccessPalette.secondary,
                size: 19,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: levelUpAccessTheme(),
    child: Scaffold(
      backgroundColor: LevelUpAccessPalette.background,
      appBar: AppBar(
        title: Text(
          t('Разрешения', 'Permissions', 'Рұқсаттар'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              key: const ValueKey('access_permission_list'),
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
              children: [
                Text(
                  t(
                    'Настрой доступ для работы LevelUp.',
                    'Choose which Android access LevelUp can use.',
                    'LevelUp үшін Android рұқсаттарын бапта.',
                  ),
                  style: const TextStyle(
                    color: LevelUpAccessPalette.secondary,
                    fontSize: 14,
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    color: LevelUpAccessPalette.accent,
                  ),
                ],
                if (_error) ...[
                  const SizedBox(height: 12),
                  Text(
                    t(
                      'Не удалось проверить статусы. Повтори попытку.',
                      'Could not check permissions. Try again.',
                      'Рұқсат мәртебесі тексерілмеді. Қайтала.',
                    ),
                    style: const TextStyle(
                      color: LevelUpAccessPalette.secondary,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _refresh,
                      child: Text(t('Повторить', 'Retry', 'Қайталау')),
                    ),
                  ),
                ],
                _sectionTitle(t('ДЛЯ ФОКУСА', 'FOR FOCUS', 'ФОКУС ҮШІН')),
                _permissionRow(
                  LevelUpPermission.usageAccess,
                  Icons.bar_chart_outlined,
                  t('Экранное время', 'Screen time', 'Экран уақыты'),
                  t(
                    'Статистика использования приложений',
                    'App usage statistics',
                    'Қолданба статистикасы',
                  ),
                ),
                const Divider(height: 1, color: LevelUpAccessPalette.border),
                _permissionRow(
                  LevelUpPermission.accessibility,
                  Icons.accessibility_new_outlined,
                  t(
                    'Специальные возможности',
                    'Accessibility',
                    'Арнайы мүмкіндіктер',
                  ),
                  t(
                    'Определение открытия выбранного приложения',
                    'Detecting the selected app opening',
                    'Таңдалған қолданбаның ашылуын анықтау',
                  ),
                ),
                _sectionTitle(
                  t('ДЛЯ ТРЕНИРОВОК', 'FOR WORKOUTS', 'ЖАТТЫҒУ ҮШІН'),
                ),
                _permissionRow(
                  LevelUpPermission.camera,
                  Icons.camera_alt_outlined,
                  t('Камера', 'Camera', 'Камера'),
                  t(
                    'Подсчёт повторений через ML Kit',
                    'Counting reps using ML Kit',
                    'ML Kit арқылы санау',
                  ),
                ),
                _sectionTitle(t('ДОПОЛНИТЕЛЬНО', 'OPTIONAL', 'ҚОСЫМША')),
                _permissionRow(
                  LevelUpPermission.notifications,
                  Icons.notifications_none_outlined,
                  t('Уведомления', 'Notifications', 'Хабарландырулар'),
                  t(
                    'Для поддерживаемых уведомлений',
                    'For supported notifications',
                    'Қолдау көрсетілетін хабарландырулар',
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: LevelUpAccessPalette.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: LevelUpAccessPalette.border),
                  ),
                  child: Text(
                    t(
                      'Доступ добровольный. Специальные возможности позволяют LevelUp определять открытие приложений. Все разрешения можно отозвать в Android. Focus можно выключить без упражнений.',
                      'Access is optional. Accessibility lets LevelUp detect app launches. You can revoke permissions in Android and turn Focus off without exercising.',
                      'Рұқсат ерікті. Арнайы мүмкіндіктер қолданбаның ашылуын анықтайды. Рұқсатты Android-та қайтарып, Фокусты жаттығусыз өшіруге болады.',
                    ),
                    style: const TextStyle(
                      color: LevelUpAccessPalette.secondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                if (widget.openApps != null) ...[
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      key: const ValueKey('access_to_apps'),
                      onPressed: _openApps,
                      style: FilledButton.styleFrom(
                        backgroundColor: LevelUpAccessPalette.accent,
                        foregroundColor: LevelUpAccessPalette.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        t(
                          'Выбрать приложение',
                          'Choose an app',
                          'Қолданбаны таңдау',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
