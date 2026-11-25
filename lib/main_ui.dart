import 'dart:convert';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/android_app_catalog.dart';
import 'data/android_usage_gateway.dart';
import 'data/dashboard_data.dart';
import 'data/levelup_permissions.dart';
import 'focus_experience/focus_exercises.dart';
import 'focus_experience/focus_screens.dart';
import 'screens/app_permissions_screen.dart';
import 'screens/levelup_app_selection_screen.dart';
import 'screens/levelup_focus_setup_screen.dart';
import 'screens/levelup_home_screen.dart';
import 'screens/levelup_permissions_screen.dart';
import 'screens/levelup_splash_screen.dart';
import 'screens/levelup_welcome_screen.dart';
import 'screens/manage_apps_screen.dart';
import 'test_kit/challenge_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LevelUpIntroDemo());
}

abstract final class LevelUpColors {
  static const background = Color(0xFF0A0F10);
  static const surface = Color(0xFF111718);
  static const accent = Color(0xFFC7FA5B);
  static const text = Color(0xFFF7F8F8);
  static const muted = Color(0xFFB0B8BA);
  static const border = Color(0xFF293334);
}

class LevelUpIntroDemo extends StatelessWidget {
  const LevelUpIntroDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LevelUp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: LevelUpColors.background,
        colorScheme: const ColorScheme.dark(
          primary: LevelUpColors.accent,
          onPrimary: LevelUpColors.background,
          surface: LevelUpColors.surface,
          onSurface: LevelUpColors.text,
          outline: LevelUpColors.border,
        ),
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: LevelUpColors.text,
          displayColor: LevelUpColors.text,
        ),
      ),
      home: const LevelUpSplashScreen(nextPage: _WelcomeFlow()),
    );
  }
}

@immutable
class _AppState {
  const _AppState({
    required this.language,
    required this.onboardingCompleted,
    required this.selectedApps,
    required this.draft,
  });

  final LevelUpLanguage language;
  final bool onboardingCompleted;
  final Set<String> selectedApps;
  final FocusSetupDraft? draft;
}

DashboardLanguage _toDashboardLanguage(LevelUpLanguage language) =>
    switch (language) {
      LevelUpLanguage.en => DashboardLanguage.en,
      LevelUpLanguage.ru => DashboardLanguage.ru,
      LevelUpLanguage.kk => DashboardLanguage.kk,
    };

LevelUpLanguage _toLevelUpLanguage(DashboardLanguage language) =>
    switch (language) {
      DashboardLanguage.en => LevelUpLanguage.en,
      DashboardLanguage.ru => LevelUpLanguage.ru,
      DashboardLanguage.kk => LevelUpLanguage.kk,
    };

class _WelcomeFlow extends StatefulWidget {
  const _WelcomeFlow();

  @override
  State<_WelcomeFlow> createState() => _WelcomeFlowState();
}

class _WelcomeFlowState extends State<_WelcomeFlow>
    with WidgetsBindingObserver {
  static const _languageKey = 'levelup.welcome.language';
  static const _onboardingCompletedKey = 'levelup.onboarding.completed';
  static const _selectedAppsKey = 'levelup.focus.selected_apps';
  static const _focusDraftKey = 'levelup.focus.draft_json';

  late final Future<_AppState> _initialState = _loadInitialState();
  bool _initialStateSynced = false;
  LevelUpLanguage _language = LevelUpLanguage.en;
  bool _onboardingCompleted = false;
  Set<String> _appSelectionDraft = const {};
  FocusSetupDraft? _focusSetupDraft;
  List<DashboardApp> _catalog = const [];
  List<SelectableApp>? _loadedCatalog;
  bool _appSelectionOpen = false;
  bool _challengeOpen = false;

  Future<_AppState> _loadInitialState() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final lang = switch (preferences.getString(_languageKey)) {
        'ru' => LevelUpLanguage.ru,
        'kk' => LevelUpLanguage.kk,
        _ => LevelUpLanguage.en,
      };
      final completed = preferences.getBool(_onboardingCompletedKey) ?? false;
      final selected =
          preferences.getStringList(_selectedAppsKey)?.toSet() ??
          const <String>{};
      FocusSetupDraft? draft;
      final draftJson = preferences.getString(_focusDraftKey);
      if (draftJson != null && draftJson.isNotEmpty) {
        try {
          final map = jsonDecode(draftJson) as Map<String, dynamic>;
          final ids =
              (map['packageIds'] as List<dynamic>?)?.cast<String>().toSet() ??
              const <String>{};
          final modeName = map['mode'] as String? ?? FocusMode.alwaysOn.name;
          final mode = FocusMode.values.firstWhere(
            (m) => m.name == modeName,
            orElse: () => FocusMode.alwaysOn,
          );
          final unlockMinutes = (map['unlockMinutes'] as num?)?.toInt() ?? 5;
          final sessionMinutes = (map['sessionMinutes'] as num?)?.toInt() ?? 60;
          final weekdays =
              (map['weekdays'] as List<dynamic>?)?.cast<int>().toSet() ??
              const {1, 2, 3, 4, 5};
          final startMinute = (map['startMinute'] as num?)?.toInt() ?? 540;
          final endMinute = (map['endMinute'] as num?)?.toInt() ?? 1020;
          final candidate = FocusSetupDraft(
            packageIds: ids,
            mode: mode,
            unlockMinutes: unlockMinutes,
            sessionMinutes: sessionMinutes,
            weekdays: weekdays,
            startMinute: startMinute,
            endMinute: endMinute,
          );
          if (candidate.hasValidRules &&
              ids.every((id) => id.trim().isNotEmpty)) {
            draft = candidate;
          }
        } catch (_) {}
      }
      return _AppState(
        language: lang,
        onboardingCompleted: completed,
        selectedApps: draft?.packageIds ?? selected,
        draft: draft,
      );
    } on Exception catch (error) {
      debugPrint('Could not load initial app state: $error');
      return const _AppState(
        language: LevelUpLanguage.en,
        onboardingCompleted: false,
        selectedApps: {},
        draft: null,
      );
    }
  }

  Future<void> _saveWelcomeLanguage(LevelUpLanguage language) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_languageKey, language.name);
      await _syncGateLanguage(language);
    } on Exception catch (error) {
      debugPrint('Could not save Welcome language: $error');
    }
  }

  Future<void> _ensureCatalogLoaded({bool forceRefresh = false}) async {
    if (_loadedCatalog != null && !forceRefresh) return;
    try {
      final apps = await const AndroidAppCatalog().load(
        forceRefresh: forceRefresh,
      );
      if (!mounted || identical(apps, _loadedCatalog)) return;
      setState(() {
        _loadedCatalog = apps;
        _catalog = apps
            .map((app) => DashboardApp(app.packageId, app.name, icon: app.icon))
            .toList(growable: false);
      });
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkChallenge();
      if (_onboardingCompleted) {
        _ensureCatalogLoaded(forceRefresh: true);
      }
    }
  }

  Future<void> _syncGateLanguage(LevelUpLanguage language) async {
    try {
      await ExistingFocusGateway.channel.invokeMethod<void>('setGateLanguage', {
        'language': language.name,
      });
    } on MissingPluginException {
      // The gate is available on Android.
    } on PlatformException catch (error) {
      debugPrint(
        'Could not synchronize the Focus Gate language: ${error.code}',
      );
    }
  }

  Future<void> _checkChallenge() async {
    if (!mounted || !_onboardingCompleted || _challengeOpen) return;
    _challengeOpen = true;
    const gateway = ExistingFocusGateway();
    FocusChallengeRequest? request;
    try {
      final claimed = await gateway.claimChallenge();
      request = claimed;
      if (claimed == null || !mounted) return;

      final exercises = FocusExercisePreferences(
        await SharedPreferences.getInstance(),
      );
      final exercise = exercises.next();
      if (exercise == null || exercise.id != FocusExerciseId.squat) return;
      await exercises.recordAssignment(exercise.id);
      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ChallengeScreen(
            exercise: exercise,
            language: _language.name,
            onCompleted: (repetitions) =>
                gateway.completeChallenge(claimed, repetitions),
            onCameraPermissionDenied: () => _cancelChallenge(claimed),
          ),
        ),
      );
    } on Exception catch (error) {
      debugPrint('Could not open the Focus challenge: $error');
    } finally {
      if (request != null) await _cancelChallenge(request);
      _challengeOpen = false;
    }
  }

  Future<void> _cancelChallenge(FocusChallengeRequest request) async {
    try {
      await const ExistingFocusGateway().cancelChallenge(request);
    } on Exception catch (error) {
      debugPrint('Could not close the Focus challenge: $error');
    }
  }

  Future<void> _openExerciseSettings() async {
    final exercises = FocusExercisePreferences(
      await SharedPreferences.getInstance(),
    );
    if (!mounted) return;
    final selected = await Navigator.of(context).push<Set<FocusExerciseId>>(
      MaterialPageRoute(
        builder: (routeContext) => FocusExerciseSettingsScreen(
          language: _language.name,
          initialSelection: exercises.selected,
          onSave: (selection) => Navigator.of(routeContext).pop(selection),
        ),
      ),
    );
    if (selected != null && !await exercises.save(selected)) {
      throw StateError('Could not save Focus exercises');
    }
  }

  Future<void> _openAppSelection(LevelUpLanguage language) async {
    if (_appSelectionOpen) return;
    _appSelectionOpen = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (routeContext) => LevelUpAppSelectionScreen(
            language: language,
            initialSelectedIds: _appSelectionDraft,
            loadApps: const AndroidAppCatalog().load,
            onSelectionChanged: (ids) => _appSelectionDraft = ids,
            onContinue: (ids) => _openFocusSetup(routeContext, language, ids),
            onSkip: () => _openFocusSetup(routeContext, language, const {}),
            onBack: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
    } finally {
      _appSelectionOpen = false;
    }
  }

  Future<void> _openFocusSetup(
    BuildContext routeContext,
    LevelUpLanguage language,
    Set<String> packageIds,
  ) async {
    if (ModalRoute.of(routeContext)?.isCurrent != true) return;

    if (packageIds.isEmpty) {
      _openPermissionsSetup(routeContext, language, null, skipped: true);
      return;
    }

    List<SelectableApp> installed;
    try {
      installed = await const AndroidAppCatalog().load();
    } catch (_) {
      installed = const [];
    }

    if (!mounted ||
        !routeContext.mounted ||
        ModalRoute.of(routeContext)?.isCurrent != true) {
      return;
    }

    if (_catalog.isEmpty && installed.isNotEmpty) {
      _catalog = installed
          .map((app) => DashboardApp(app.packageId, app.name, icon: app.icon))
          .toList(growable: false);
      _loadedCatalog = installed;
    }

    final selectedApps = installed
        .where((app) => packageIds.contains(app.packageId))
        .toList(growable: false);

    Navigator.of(routeContext).push<void>(
      MaterialPageRoute(
        builder: (focusContext) => LevelUpFocusSetupScreen(
          language: language,
          selectedApps: selectedApps,
          initialDraft: _focusSetupDraft,
          onDraftChanged: (draft) => _focusSetupDraft = draft,
          capabilities: const FocusCapabilities(),
          onBack: () => Navigator.of(focusContext).pop(),
          onEditApps: () => Navigator.of(focusContext).pop(),
          onContinue: (draft) {
            _focusSetupDraft = draft;
            _openPermissionsSetup(focusContext, language, draft);
          },
          onSkip: () {
            _openPermissionsSetup(focusContext, language, null, skipped: true);
          },
        ),
      ),
    );
  }

  void _openPermissionsSetup(
    BuildContext routeContext,
    LevelUpLanguage language,
    FocusSetupDraft? draft, {
    bool skipped = false,
  }) {
    if (!mounted ||
        !routeContext.mounted ||
        ModalRoute.of(routeContext)?.isCurrent != true) {
      return;
    }
    Navigator.of(routeContext).push<void>(
      MaterialPageRoute(
        builder: (permContext) => LevelUpPermissionsScreen(
          language: language,
          gateway: const AndroidPermissionGateway(),
          onBack: () => Navigator.of(permContext).pop(),
          onFinish: (_) => _openHome(permContext, language, draft),
        ),
      ),
    );
  }

  Future<void> _openHome(
    BuildContext routeContext,
    LevelUpLanguage language,
    FocusSetupDraft? draft,
  ) async {
    final setup = draft ?? FocusSetupDraft(packageIds: _appSelectionDraft);
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(
          _focusDraftKey,
          jsonEncode(setup.toJson()),
        ) ||
        !await preferences.setString(_languageKey, language.name) ||
        !await preferences.setBool(_onboardingCompletedKey, true)) {
      throw StateError('Could not persist onboarding');
    }

    if (!mounted || !routeContext.mounted) return;
    setState(() {
      _language = language;
      _onboardingCompleted = true;
      _focusSetupDraft = setup;
      _appSelectionDraft = setup.packageIds;
    });
    _syncGateLanguage(language);
    _ensureCatalogLoaded();
    Navigator.of(routeContext).popUntil((route) => route.isFirst);
  }

  String? _formatDraftSummary(
    FocusSetupDraft? draft,
    LevelUpLanguage language,
  ) {
    if (draft == null || draft.packageIds.isEmpty) return null;
    final count = draft.packageIds.length;
    final unlock = draft.unlockMinutes;
    return switch (language) {
      LevelUpLanguage.en => '$count apps · ${unlock}m unlock',
      LevelUpLanguage.ru => '$count прилож. · $unlockм разблок.',
      LevelUpLanguage.kk => '$count қолданба · $unlockмин бұғаттау',
    };
  }

  ExistingFocusGateway get _focusGateway => switch (_language) {
    LevelUpLanguage.en => const ExistingFocusGateway(
      notificationLanguage: DashboardLanguage.en,
    ),
    LevelUpLanguage.ru => const ExistingFocusGateway(
      notificationLanguage: DashboardLanguage.ru,
    ),
    LevelUpLanguage.kk => const ExistingFocusGateway(
      notificationLanguage: DashboardLanguage.kk,
    ),
  };

  Future<DashboardInsights> _loadDashboardInsights() =>
      const AndroidUsageGateway().read(
        _focusSetupDraft?.packageIds ?? _appSelectionDraft,
      );

  Widget _buildHomeScreen() {
    return LevelUpHomeScreen(
      gateway: _focusGateway,
      language: _toDashboardLanguage(_language),
      catalog: _catalog,
      draftIds: _focusSetupDraft?.packageIds ?? _appSelectionDraft,
      draftSummary: _formatDraftSummary(_focusSetupDraft, _language),
      focusDraft: _focusSetupDraft,
      capabilities: const FocusCapabilities(),
      onSaveFocusDraft: _saveFocusDraft,
      logoAsset: 'assets/images/levelup_mark.png',
      onEditFocus: () async {
        await _openManageApps();
      },
      onExerciseSettings: _openExerciseSettings,
      onPermissions: () async {
        await _openAppPermissions();
      },
      onEnableFocus: () async {
        await _handleEnableFocus();
      },
      onPauseFocus: () async {
        await _handlePauseFocus();
      },
      onLanguageChanged: (dashLang) {
        final lang = _toLevelUpLanguage(dashLang);
        _saveWelcomeLanguage(lang);
        setState(() => _language = lang);
      },
      onMovement: null,
      loadInsights: _loadDashboardInsights,
    );
  }

  Future<void> _openManageApps() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ManageAppsScreen(
          language: _toDashboardLanguage(_language),
          initialSelectedIds:
              _focusSetupDraft?.packageIds ?? _appSelectionDraft,
          loadApps: () => const AndroidAppCatalog().load(forceRefresh: true),
          onSave: (selectedIds) => _saveFocusDraft(
            (_focusSetupDraft ??
                    FocusSetupDraft(packageIds: _appSelectionDraft))
                .copyWith(packageIds: selectedIds),
            verifyTarget: true,
          ),
        ),
      ),
    );
  }

  Future<void> _saveFocusDraft(
    FocusSetupDraft draft, {
    bool verifyTarget = false,
  }) async {
    final selection = draft.packageIds;
    final previousSelection =
        _focusSetupDraft?.packageIds ?? _appSelectionDraft;
    if ((verifyTarget || !setEquals(previousSelection, selection)) &&
        await const AndroidPermissionGateway().isAvailable()) {
      final focus = await _focusGateway.read();
      if (focus.targets.any((id) => !selection.contains(id))) {
        await _focusGateway.disable();
        if (mounted && focus.active) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(switch (_language) {
                LevelUpLanguage.en =>
                  'Focus turned off because its current app was removed.',
                LevelUpLanguage.ru => 'Фокус выключен, потому что текущее приложение удалено из списка.',
                LevelUpLanguage.kk => 'Ағымдағы қолданба тізімнен алынды, сондықтан фокус өшірілді.',
              }),
            ),
          );
        }
      }
    }
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(
      _focusDraftKey,
      jsonEncode(draft.toJson()),
    )) {
      throw StateError('Could not persist Focus settings');
    }
    if (!mounted) return;
    setState(() {
      _focusSetupDraft = draft;
      _appSelectionDraft = selection;
    });
  }

  Future<void> _openAppPermissions() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AppPermissionsScreen(
          gateway: const AndroidPermissionGateway(),
          openPermissionSettings:
              const AndroidPermissionGateway().openPermissionSettings,
          language: _toDashboardLanguage(_language),
        ),
      ),
    );
  }

  Future<void> _handleEnableFocus() async {
    final Map<LevelUpPermission, PermissionState> states;
    try {
      states = await const AndroidPermissionGateway().read();
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (_language) {
            LevelUpLanguage.en => 'Focus setup needs the Android UI bridge.',
            LevelUpLanguage.ru =>
              'Для настройки фокуса нужен Android-мост интерфейса.',
            LevelUpLanguage.kk =>
              'Фокусты баптау үшін Android интерфейс көпірі қажет.',
          }),
        ),
      );
      return;
    }
    final accessGranted =
        states[LevelUpPermission.accessibility] == PermissionState.granted;
    if (!accessGranted) {
      if (!mounted) return;
      final openPerms = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: LevelUpColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: LevelUpColors.border),
          ),
          title: Text(switch (_language) {
            LevelUpLanguage.en => 'Accessibility Required',
            LevelUpLanguage.ru => 'Требуется разрешение',
            LevelUpLanguage.kk => 'Рұқсат қажет',
          }, style: const TextStyle(color: LevelUpColors.text, fontSize: 18)),
          content: Text(switch (_language) {
            LevelUpLanguage.en => 'To shield selected apps, LevelUp needs the Accessibility Service permission. Please enable it in Android Settings.',
            LevelUpLanguage.ru => 'Для защиты приложений LevelUp требуется разрешение Специальных возможностей. Пожалуйста, включи его в настройках.',
            LevelUpLanguage.kk => 'Қолданбаларды қорғау үшін LevelUp-ке Арнайы мүмкіндіктер рұқсаты қажет. Оны баптаулардан қосыңыз.',
          }, style: const TextStyle(color: LevelUpColors.muted, fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(switch (_language) {
                LevelUpLanguage.en => 'Cancel',
                LevelUpLanguage.ru => 'Отмена',
                LevelUpLanguage.kk => 'Болдырмау',
              }, style: const TextStyle(color: LevelUpColors.muted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LevelUpColors.accent,
                foregroundColor: LevelUpColors.background,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(switch (_language) {
                LevelUpLanguage.en => 'Open Permissions',
                LevelUpLanguage.ru => 'Открыть разрешения',
                LevelUpLanguage.kk => 'Рұқсаттарды ашу',
              }, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (openPerms == true && mounted) {
        await _openAppPermissions();
      }
      return;
    }

    final selectedIds = _focusSetupDraft?.packageIds ?? _appSelectionDraft;
    final apps = await const AndroidAppCatalog().load(forceRefresh: true);
    if (!mounted) return;
    final eligible = apps
        .where((app) => selectedIds.contains(app.packageId))
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (_language) {
            LevelUpLanguage.en => 'Select an installed app to use Focus.',
            LevelUpLanguage.ru => 'Выбери установленное приложение для фокуса.',
            LevelUpLanguage.kk => 'Фокус үшін орнатылған қолданбаны таңдаңыз.',
          }),
        ),
      );
      await _openManageApps();
      return;
    }

    final draft = _focusSetupDraft;
    final hasDraftOnlyRules =
        draft != null &&
        (draft.mode != FocusMode.alwaysOn || draft.unlockMinutes != 5);
    final target = eligible.length == 1 && !hasDraftOnlyRules
        ? eligible.single.packageId
        : await showDialog<String>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: Text(switch (_language) {
                LevelUpLanguage.en => 'Enable Focus for one app',
                LevelUpLanguage.ru => 'Включить фокус для одного приложения',
                LevelUpLanguage.kk => 'Бір қолданба үшін фокусты қосу',
              }),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                  child: Text(switch (_language) {
                    LevelUpLanguage.en => 'Focus stays on until you turn it off. Completing a challenge grants 5 minutes of access.',
                    LevelUpLanguage.ru => 'Фокус действует до ручного отключения. За выполненное задание открывается 5 минут доступа.',
                    LevelUpLanguage.kk => 'Фокус қолмен өшірілгенше қосулы болады. Тапсырма орындалса, 5 минутқа рұқсат беріледі.',
                  }),
                ),
                for (final app in eligible)
                  SimpleDialogOption(
                    key: ValueKey('focus_target_${app.packageId}'),
                    onPressed: () =>
                        Navigator.of(dialogContext).pop(app.packageId),
                    child: Text(app.name),
                  ),
              ],
            ),
          );
    if (!mounted || target == null) return;

    try {
      await _focusGateway.enable(target: target);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (_language) {
            LevelUpLanguage.en => 'Failed to enable focus: $e',
            LevelUpLanguage.ru => 'Не удалось включить фокус: $e',
            LevelUpLanguage.kk => 'Фокусты қосу мүмкін болмады: $e',
          }),
        ),
      );
    }
  }

  Future<void> _handlePauseFocus() => _focusGateway.disable();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AppState>(
      future: _initialState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) {
          return const ColoredBox(color: LevelUpWelcomeScreen.background);
        }
        if (!_initialStateSynced) {
          _language = state.language;
          _onboardingCompleted = state.onboardingCompleted;
          _appSelectionDraft = state.selectedApps;
          _focusSetupDraft = state.draft;
          _initialStateSynced = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncGateLanguage(_language);
            _checkChallenge();
          });
          if (_onboardingCompleted) {
            _ensureCatalogLoaded();
          }
        }
        if (_onboardingCompleted) {
          return _buildHomeScreen();
        }
        return LevelUpWelcomeScreen(
          initialLanguage: _language,
          onLanguageChanged: (lang) {
            _saveWelcomeLanguage(lang);
            setState(() => _language = lang);
          },
          onGetStarted: _openAppSelection,
        );
      },
    );
  }
}
