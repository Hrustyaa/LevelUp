import 'package:flutter/widgets.dart';

import '../../core/integration/core_integration_coordinator.dart';
import '../../data/database/levelup_database.dart';
import '../../data/repositories/access_attempt_repository.dart';
import '../../data/repositories/workout_history_repository.dart';
import '../../features/challenge/application/challenge_service.dart';
import '../../features/challenge/application/workout_session_manager.dart';
import '../../features/focus/application/focus_service.dart';
import '../../features/progress/application/progress_service.dart';
import '../../features/progress/data/progress_repository.dart';
import '../../features/statistics/application/statistics_service.dart';
import '../../features/statistics/data/statistics_repository.dart';
import '../../features/settings/application/camera_permission_checker.dart';
import '../../features/settings/application/settings_service.dart';
import '../../features/settings/data/settings_repository.dart';
import '../../services/access_service.dart';
import '../../services/native_bridge.dart';
import '../adapters/core_app_catalog_adapter.dart';
import '../adapters/core_focus_gateway_adapter.dart';
import '../adapters/core_insights_adapter.dart';
import '../adapters/core_permission_gateway_adapter.dart';

/// Production-grade dependency injection container for LevelUp.
///
/// Encapsulates all backend engines (NativeBridge, FocusService, SettingsService,
/// LevelUpDatabase, AccessService, CoreIntegrationCoordinator) and provides production
/// adapters for the Flutter UI layer.
class AppScope {
  final LevelUpDatabase database;
  final INativeBridge nativeBridge;
  final IFocusService focusService;
  final ISettingsRepository settingsRepository;
  final ICameraPermissionChecker cameraChecker;
  final ISettingsService settingsService;
  final IWorkoutHistoryRepository workoutHistoryRepository;
  final IAccessAttemptRepository accessAttemptRepository;
  late final IProgressRepository progressRepository;
  late final IProgressService progressService;
  late final IStatisticsRepository statisticsRepository;
  late final IStatisticsService statisticsService;
  final IChallengeService challengeService;
  final IWorkoutSessionManager sessionManager;
  final IAccessService accessService;
  final ICoreIntegrationCoordinator coordinator;

  // UI Adapters
  final CoreAppCatalogAdapter appCatalog;
  late final CorePermissionGatewayAdapter permissionGateway;
  late final CoreFocusGatewayAdapter focusGateway;
  late final CoreInsightsAdapter insightsAdapter;

  bool _initialized = false;
  bool get isInitialized => _initialized;
  Object? _initializationError;
  Object? get initializationError => _initializationError;

  AppScope({
    required this.database,
    required this.nativeBridge,
    required this.focusService,
    required this.settingsRepository,
    required this.cameraChecker,
    required this.settingsService,
    required this.workoutHistoryRepository,
    required this.accessAttemptRepository,
    IProgressRepository? progressRepository,
    IProgressService? progressService,
    IStatisticsRepository? statisticsRepository,
    IStatisticsService? statisticsService,
    required this.challengeService,
    required this.sessionManager,
    required this.accessService,
    required this.coordinator,
    CoreAppCatalogAdapter? appCatalog,
    CorePermissionGatewayAdapter? permissionGateway,
    CoreFocusGatewayAdapter? focusGateway,
    CoreInsightsAdapter? insightsAdapter,
  }) : appCatalog = appCatalog ?? const CoreAppCatalogAdapter() {
    this.progressRepository =
        progressRepository ?? SqliteProgressRepository(databaseManager: database);
    this.progressService = progressService ??
        ProgressService(
          repository: this.progressRepository,
          historyRepository: workoutHistoryRepository,
        );
    this.statisticsRepository =
        statisticsRepository ?? SqliteStatisticsRepository(databaseManager: database);
    this.statisticsService = statisticsService ??
        StatisticsService(
          repository: this.statisticsRepository,
          progressService: this.progressService,
          focusService: focusService,
        );
    this.permissionGateway = permissionGateway ??
        CorePermissionGatewayAdapter(
          settingsService: settingsService,
          nativeBridge: nativeBridge,
          cameraChecker: cameraChecker,
        );
    this.focusGateway = focusGateway ??
        CoreFocusGatewayAdapter(
          focusService: focusService,
        );
    this.insightsAdapter = insightsAdapter ??
        CoreInsightsAdapter(
          historyRepo: workoutHistoryRepository,
          accessRepo: accessAttemptRepository,
          progressService: this.progressService,
          statisticsService: statisticsService,
        );
  }

  /// Creates a production-ready [AppScope] wiring all real engines together.
  factory AppScope.production({
    LevelUpDatabase? database,
    INativeBridge? nativeBridge,
    ICameraPermissionChecker? cameraChecker,
    DateTime Function()? clock,
  }) {
    final effectiveBridge = nativeBridge ?? const NativeBridge();
    final effectiveDb = database ?? LevelUpDatabase();
    final effectiveChecker = cameraChecker ??
        DefaultCameraPermissionChecker(nativeBridge: effectiveBridge);
    final effectiveClock = clock ?? DateTime.now;

    final focusService = FocusService(bridge: effectiveBridge);
    final settingsRepo = SqliteSettingsRepository(
      databaseManager: effectiveDb,
      clock: effectiveClock,
    );
    final settingsService = SettingsService(
      repository: settingsRepo,
      focusService: focusService,
      nativeBridge: effectiveBridge,
      cameraPermissionChecker: effectiveChecker,
      clock: effectiveClock,
    );

    final historyRepo = WorkoutHistoryRepository(
      databaseManager: effectiveDb,
    );
    final accessRepo = AccessAttemptRepository(
      databaseManager: effectiveDb,
    );
    final progressRepo = SqliteProgressRepository(
      databaseManager: effectiveDb,
    );
    final progressService = ProgressService(
      repository: progressRepo,
      historyRepository: historyRepo,
      clock: effectiveClock,
    );
    final statisticsRepo = SqliteStatisticsRepository(
      databaseManager: effectiveDb,
    );
    final statisticsService = StatisticsService(
      repository: statisticsRepo,
      progressService: progressService,
      focusService: focusService,
      clock: effectiveClock,
    );

    final challengeService = ChallengeService();
    final sessionManager = WorkoutSessionManager(
      challengeService: challengeService,
      clock: effectiveClock,
    );
    final accessService = AccessService(
      bridge: effectiveBridge,
      clock: effectiveClock,
    );

    final coordinator = CoreIntegrationCoordinator(
      nativeBridge: effectiveBridge,
      focusService: focusService,
      challengeService: challengeService,
      sessionManager: sessionManager,
      accessService: accessService,
      workoutHistoryRepository: historyRepo,
      accessAttemptRepository: accessRepo,
      progressService: progressService,
      clock: effectiveClock,
    );

    return AppScope(
      database: effectiveDb,
      nativeBridge: effectiveBridge,
      focusService: focusService,
      settingsRepository: settingsRepo,
      cameraChecker: effectiveChecker,
      settingsService: settingsService,
      workoutHistoryRepository: historyRepo,
      accessAttemptRepository: accessRepo,
      progressRepository: progressRepo,
      progressService: progressService,
      statisticsRepository: statisticsRepo,
      statisticsService: statisticsService,
      challengeService: challengeService,
      sessionManager: sessionManager,
      accessService: accessService,
      coordinator: coordinator,
    );
  }

  /// Authoritatively initializes core engines and loads persisted preferences.
  Future<void> initialize() async {
    if (_initialized) return;
    _initializationError = null;

    try {
      // 1. Initialize SQLite database and open connection
      await database.database;

      // 2. Initialize Settings and Focus engines
      final settingsState = await settingsService.initialize();
      if (settingsState.errorMessage != null) {
        throw StateError(settingsState.errorMessage!);
      }
      await focusService.refreshState();

      // 3. Initialize Integration Coordinator, Progress & Statistics Engines
      await progressService.initialize();
      await statisticsService.initialize();
      await coordinator.initialize();

      _initialized = true;
    } catch (error) {
      _initializationError = error;
      _initialized = false;
      rethrow;
    }
  }

  /// Refreshes native synchronization (e.g. after returning from Android Settings).
  Future<void> refresh() async {
    await settingsService.refresh();
    await focusService.refreshState();
    await progressService.refresh();
    await statisticsService.refresh();
  }

  /// Disposes resources held by the engines.
  void dispose() {
    coordinator.dispose();
    sessionManager.dispose();
    statisticsService.dispose();
    progressService.dispose();
    settingsService.dispose();
    focusService.dispose();
    database.close();
  }

  /// Convenience lookup on [BuildContext] using [AppScopeProvider].
  static AppScope of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppScopeProvider>();
    assert(provider != null, 'No AppScopeProvider found in context');
    return provider!.scope;
  }

  /// Nullable lookup on [BuildContext].
  static AppScope? maybeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppScopeProvider>();
    return provider?.scope;
  }
}

/// An [InheritedWidget] providing [AppScope] to the widget tree.
class AppScopeProvider extends InheritedWidget {
  final AppScope scope;

  const AppScopeProvider({
    super.key,
    required this.scope,
    required super.child,
  });

  @override
  bool updateShouldNotify(covariant AppScopeProvider oldWidget) =>
      scope != oldWidget.scope;
}
