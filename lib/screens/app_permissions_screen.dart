import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart' show DashboardLanguage;
import '../data/levelup_permissions.dart';

class AppPermissionsScreen extends StatefulWidget {
  const AppPermissionsScreen({
    super.key,
    required this.gateway,
    this.openPermissionSettings,
    this.language = DashboardLanguage.en,
  });

  final LevelUpPermissionGateway gateway;
  final Future<void> Function(LevelUpPermission)? openPermissionSettings;
  final DashboardLanguage language;

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen>
    with WidgetsBindingObserver {
  static const _bg = Color(0xFF0A0F10);
  static const _surface = Color(0xFF111718);
  static const _lime = Color(0xFFC7FA5B);
  static const _ink = Color(0xFFF7F8F8);
  static const _muted = Color(0xFFB0B8BA);
  static const _border = Color(0xFF293334);

  Map<LevelUpPermission, PermissionState> _states = {};
  LevelUpPermission? _busy;
  bool _loading = true, _failed = false, _dialogOpen = false;
  int _readId = 0;

  String _tr(String en, String ru, String kk) => switch (widget.language) {
    DashboardLanguage.en => en,
    DashboardLanguage.ru => ru,
    DashboardLanguage.kk => kk,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final request = ++_readId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final next = await widget.gateway.read();
      if (!mounted || request != _readId) return;
      setState(() {
        _states = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _readId) return;
      setState(() {
        _states = {};
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _openAppSettings([LevelUpPermission? permission]) async {
    try {
      final openPermission = widget.openPermissionSettings;
      if (permission != null && openPermission != null) {
        await openPermission(permission);
      } else {
        await widget.gateway.openAppSettings();
      }
    } catch (_) {
      _showSettingsError();
    }
  }

  void _showSettingsError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _tr(
            'Could not open Android settings.',
            'Не удалось открыть настройки Android.',
            'Android баптауларын ашу мүмкін болмады.',
          ),
        ),
      ),
    );
  }

  Future<void> _request(LevelUpPermission p) async {
    if (_busy != null ||
        _loading ||
        _dialogOpen ||
        _states[p] != PermissionState.denied) {
      return;
    }

    if (p == LevelUpPermission.accessibility || p == LevelUpPermission.usage) {
      final title = _titleFor(p);
      final message = _dialogFor(p);
      _dialogOpen = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _border),
          ),
          title: Text(title, style: const TextStyle(color: _ink, fontSize: 18)),
          content: SingleChildScrollView(
            child: Text(
              message,
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _tr('Cancel', 'Отмена', 'Болдырмау'),
                style: const TextStyle(color: _muted),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _lime,
                foregroundColor: _bg,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _tr('Open Settings', 'Открыть настройки', 'Баптауларды ашу'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = p);
    try {
      await widget.gateway.request(p);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'Could not open the permission settings.',
                'Не удалось открыть настройки разрешения.',
                'Рұқсат баптауларын ашу мүмкін болмады.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        await _refresh();
      }
    }
  }

  String _titleFor(LevelUpPermission p) => switch (p) {
    LevelUpPermission.accessibility => _tr(
      'Accessibility Service',
      'Специальные возможности',
      'Арнайы мүмкіндіктер',
    ),
    LevelUpPermission.usage => _tr(
      'Usage Access (Screen Time)',
      'Доступ к статистике использования',
      'Пайдалану статистикасы',
    ),
    LevelUpPermission.camera => _tr(
      'Camera Access',
      'Доступ к камере',
      'Камераға рұқсат',
    ),
    LevelUpPermission.notifications => _tr(
      'Notifications',
      'Уведомления',
      'Хабарландырулар',
    ),
  };

  String _descFor(LevelUpPermission p) => switch (p) {
    LevelUpPermission.accessibility => _tr(
      'Allows LevelUp to detect when shielded apps open and show the focus gate. Does not inspect screen content.',
      'Позволяет распознавать запуск защищённых приложений и показывать защитный экран. Не читает личные данные.',
      'Қорғалған қолданбалар ашылғанда анықтауға және экранды көрсетуге мүмкіндік береді. Жеке деректерді оқымайды.',
    ),
    LevelUpPermission.usage => _tr(
      'Provides accurate screen time statistics for selected apps. Processed strictly locally on your device.',
      'Предоставляет точную статистику экранного времени выбранных приложений. Обрабатывается исключительно локально.',
      'Таңдалған қолданбалардың нақты экран уақытын береді. Деректер тек құрылғыңызда өңделеді.',
    ),
    LevelUpPermission.camera => _tr(
      'Used during voluntary physical movement challenges to verify squats on device with ML Kit. Video is never saved or streamed.',
      'Используется во время физических упражнений для подсчёта приседаний на устройстве через ML Kit. Видео никуда не передаётся.',
      'Жаттығу кезінде құрылғыда ML Kit арқылы отырып-тұруды есептеу үшін қолданылады. Видео сақталмайды және жіберілмейді.',
    ),
    LevelUpPermission.notifications => _tr(
      'Optional alerts when you turn Focus on or off.',
      'Необязательные уведомления, когда ты включаешь или выключаешь фокус.',
      'Фокусты қосқанда немесе өшіргенде келетін ерікті хабарландырулар.',
    ),
  };

  String _dialogFor(LevelUpPermission p) => switch (p) {
    LevelUpPermission.accessibility => _tr(
      'LevelUp will open Android Accessibility Settings. Locate "LevelUp" in installed services and enable it.',
      'LevelUp откроет настройки специальных возможностей. Найди «LevelUp» в списке установленных сервисов и включи его.',
      'LevelUp арнайы мүмкіндіктер баптауларын ашады. Орнатылған қызметтер ішінен «LevelUp» тауып, қосыңыз.',
    ),
    LevelUpPermission.usage => _tr(
      'LevelUp will open Usage Access Settings. Grant permission to LevelUp so it can read local screen time for chosen apps.',
      'LevelUp откроет настройки доступа к данным об использовании. Разреши доступ для LevelUp для локального подсчёта времени.',
      'LevelUp пайдалану деректеріне қолжетімділік баптауларын ашады. Жергілікті уақытты есептеу үшін LevelUp-ке рұқсат беріңіз.',
    ),
    _ => '',
  };

  IconData _iconFor(LevelUpPermission p) => switch (p) {
    LevelUpPermission.accessibility => Icons.accessibility_new_rounded,
    LevelUpPermission.usage => Icons.pie_chart_outline_rounded,
    LevelUpPermission.camera => Icons.camera_alt_outlined,
    LevelUpPermission.notifications => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          _tr(
            'App permissions',
            'Разрешения приложения',
            'Қолданба рұқсаттары',
          ),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _muted),
            tooltip: _tr(
              'App settings',
              'Настройки системы',
              'Жүйе баптаулары',
            ),
            onPressed: _openAppSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            Text(
              _tr(
                'Configure system access required for voluntary shielding and statistics.',
                'Управляй системными разрешениями для защиты внимания и локальной статистики.',
                'Назарды қорғау және жергілікті статистика үшін қажетті рұқсаттарды басқарыңыз.',
              ),
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const LinearProgressIndicator()
            else if (_failed) ...[
              Text(
                _tr(
                  'Could not read permissions.',
                  'Не удалось проверить разрешения.',
                  'Рұқсаттарды тексеру мүмкін болмады.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _refresh,
                child: Text(_tr('Retry', 'Повторить', 'Қайталау')),
              ),
            ] else
              for (final p in LevelUpPermission.values) ...[
                _buildPermissionTile(p),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: _muted,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tr(
                        'Permissions are strictly voluntary. You can revoke them at any time in Android system settings.',
                        'Все разрешения добровольны. Их можно отозвать в любой момент в настройках Android.',
                        'Барлық рұқсаттар ерікті. Оларды кез келген уақытта Android баптауларында өшіруге болады.',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile(LevelUpPermission p) {
    final state = _states[p] ?? PermissionState.unknown;
    final isGranted = state == PermissionState.granted;
    final isUnavailable = state == PermissionState.unavailable;
    final isBusy = _busy == p;
    final isUnknown = state == PermissionState.unknown;
    final isOptional =
        p == LevelUpPermission.usage || p == LevelUpPermission.notifications;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isGranted ? const Color(0x40C7FA5B) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(p), color: isGranted ? _lime : _muted, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _titleFor(p),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            switch (state) {
              PermissionState.granted => _tr(
                'Granted',
                'Предоставлено',
                'Берілді',
              ),
              PermissionState.unavailable => _tr(
                'Unavailable',
                'Недоступно',
                'Қолжетімсіз',
              ),
              PermissionState.unknown => _tr(
                'Status unknown',
                'Статус неизвестен',
                'Күйі белгісіз',
              ),
              PermissionState.denied =>
                isOptional
                    ? _tr('Off', 'Выключено', 'Өшірулі')
                    : _tr(
                        'Permission needed',
                        'Нужно разрешение',
                        'Рұқсат қажет',
                      ),
            },
            style: TextStyle(
              color: isGranted ? _lime : _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _descFor(p),
            style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (!isUnavailable && !isUnknown)
            SizedBox(
              width: double.infinity,
              child: isGranted
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _ink,
                        side: const BorderSide(color: _border),
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _openAppSettings(p),
                      child: Text(
                        _tr(
                          'Manage in OS',
                          'Управление в системе',
                          'Жүйеде басқару',
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: isUnavailable ? _border : _lime,
                        foregroundColor: isUnavailable ? _muted : _bg,
                        disabledBackgroundColor: _border,
                        minimumSize: const Size(0, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _busy != null ? null : () => _request(p),
                      child: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _bg,
                              ),
                            )
                          : Text(
                              isUnavailable
                                  ? _tr(
                                      'Feature not connected',
                                      'Функция ещё не подключена',
                                      'Функция әлі қосылмаған',
                                    )
                                  : _tr(
                                      'Grant access',
                                      'Предоставить доступ',
                                      'Рұқсат беру',
                                    ),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isUnavailable ? _muted : _bg,
                              ),
                            ),
                    ),
            ),
        ],
      ),
    );
  }
}
