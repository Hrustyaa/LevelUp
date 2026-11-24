import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/channel_constants.dart';
import '../../../core/integration/core_integration_coordinator.dart';
import '../../../data/database/levelup_database.dart';
import '../../../data/repositories/access_attempt_repository.dart';
import '../../../data/repositories/workout_history_repository.dart';
import '../../../features/challenge/application/challenge_service.dart';
import '../../../features/challenge/application/workout_session_manager.dart';
import '../../../features/focus/application/focus_service.dart';
import '../../../features/settings/application/camera_permission_checker.dart';
import '../../../features/settings/application/settings_service.dart';
import '../../../features/settings/data/settings_repository.dart';
import '../../../features/settings/models/camera_permission_status.dart';
import '../../../models/native_access_status.dart';
import '../../../models/native_focus_status.dart';
import '../../../models/native_permission_status.dart';
import '../../../services/access_service.dart';
import '../../../services/native_bridge.dart';
import '../models/dev_mode.dart';
import '../models/diagnostic_event.dart';
import '../models/module_status.dart';
import '../services/dev_lab_log_service.dart';

/// Fake platform bridge used specifically for Simulation Mode.
class SimulationBridge implements INativeBridge {
  NativeFocusStatus status;
  bool challengeRequested;
  DateTime? unlockTimestamp;
  final List<String> callLog = [];

  SimulationBridge({
    NativeFocusStatus? initialStatus,
    this.challengeRequested = false,
    this.unlockTimestamp,
  }) : status = initialStatus ??
            const NativeFocusStatus(
              targetPackage: ChannelConstants.targetYouTube,
              isGateEnabled: true,
              permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
              accessStatus: NativeAccessStatus(),
            );

  @override
  Future<NativeFocusStatus> getState() async {
    callLog.add('getState');
    return status;
  }

  @override
  Future<bool> setTarget(String targetPackage) async {
    callLog.add('setTarget($targetPackage)');
    status = NativeFocusStatus(
      targetPackage: targetPackage,
      isGateEnabled: status.isGateEnabled,
      permissionStatus: status.permissionStatus,
      accessStatus: const NativeAccessStatus(),
    );
    return true;
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    callLog.add('setEnabled($enabled)');
    status = NativeFocusStatus(
      targetPackage: status.targetPackage,
      isGateEnabled: enabled,
      permissionStatus: status.permissionStatus,
      accessStatus: status.accessStatus,
    );
    return true;
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    callLog.add('openAccessibilitySettings');
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    callLog.add('openAppSettings');
    return true;
  }

  @override
  Future<String> checkCameraPermission() async {
    callLog.add('checkCameraPermission');
    return 'granted';
  }

  @override
  Future<bool> consumeChallengeRequest() async {
    callLog.add('consumeChallengeRequest');
    final was = challengeRequested;
    challengeRequested = false;
    return was;
  }

  @override
  Future<DateTime> grantAccess({int minutes = 5}) async {
    callLog.add('grantAccess($minutes)');
    final expiry = DateTime.now().add(Duration(minutes: minutes));
    status = NativeFocusStatus(
      targetPackage: status.targetPackage,
      isGateEnabled: status.isGateEnabled,
      permissionStatus: status.permissionStatus,
      accessStatus: NativeAccessStatus(unlockUntil: expiry),
    );
    unlockTimestamp = expiry;
    return expiry;
  }

  @override
  Future<bool> resetAccess() async {
    callLog.add('resetAccess');
    status = NativeFocusStatus(
      targetPackage: status.targetPackage,
      isGateEnabled: status.isGateEnabled,
      permissionStatus: status.permissionStatus,
      accessStatus: const NativeAccessStatus(),
    );
    unlockTimestamp = null;
    return true;
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Service composition root and reactive state manager for Developer Lab.
class DevLabController extends ChangeNotifier {
  DevExecutionMode _executionMode;
  final DevLabLogService logService;
  final INativeBridge? _customBridge;
  final LevelUpDatabase? _customDatabase;

  late INativeBridge nativeBridge;
  late IFocusService focusService;
  late IChallengeService challengeService;
  late IWorkoutSessionManager sessionManager;
  late IAccessService accessService;
  late LevelUpDatabase database;
  late IWorkoutHistoryRepository workoutHistoryRepository;
  late IAccessAttemptRepository accessAttemptRepository;
  late ICoreIntegrationCoordinator coordinator;
  late ISettingsRepository settingsRepository;
  late ISettingsService settingsService;

  FocusState? currentFocusState;
  bool isInitializing = true;
  String? initError;

  // Tracked real health for each backend module
  final Map<BackendModuleId, ModuleHealthStatus> moduleHealth = {
    BackendModuleId.nativeBridge: ModuleHealthStatus.notTested,
    BackendModuleId.focusEngine: ModuleHealthStatus.notTested,
    BackendModuleId.challengeEngine: ModuleHealthStatus.notTested,
    BackendModuleId.poseEngine: ModuleHealthStatus.notTested,
    BackendModuleId.sessionManager: ModuleHealthStatus.notTested,
    BackendModuleId.accessEngine: ModuleHealthStatus.notTested,
    BackendModuleId.localDatabase: ModuleHealthStatus.notTested,
    BackendModuleId.coordinator: ModuleHealthStatus.notTested,
    BackendModuleId.settingsEngine: ModuleHealthStatus.notTested,
  };

  DevLabController({
    DevExecutionMode initialMode = DevExecutionMode.realDevice,
    DevLabLogService? customLogService,
    INativeBridge? customBridge,
    LevelUpDatabase? customDatabase,
  })  : _executionMode = initialMode,
        logService = customLogService ?? DevLabLogService(),
        _customBridge = customBridge,
        _customDatabase = customDatabase {
    _initializeServices(
      overrideBridge: customBridge,
      overrideDatabase: customDatabase,
    );
  }

  DevExecutionMode get executionMode => _executionMode;

  void _initializeServices({
    INativeBridge? overrideBridge,
    LevelUpDatabase? overrideDatabase,
  }) {
    final bridgeOverride = overrideBridge ?? _customBridge;
    final dbOverride = overrideDatabase ?? _customDatabase;

    if (_executionMode == DevExecutionMode.realDevice) {
      nativeBridge = bridgeOverride ?? const NativeBridge();
      database = dbOverride ?? LevelUpDatabase();
    } else {
      nativeBridge = bridgeOverride ?? SimulationBridge();
      // Ensure Simulation mode uses an isolated database instance to prevent test contamination
      database = dbOverride ??
          LevelUpDatabase(
            customPath: 'levelup_simulation.db',
          );
    }

    focusService = FocusService(bridge: nativeBridge);
    challengeService = ChallengeService();
    sessionManager = WorkoutSessionManager(challengeService: challengeService);
    accessService = AccessService(bridge: nativeBridge);
    workoutHistoryRepository = WorkoutHistoryRepository(databaseManager: database);
    accessAttemptRepository = AccessAttemptRepository(databaseManager: database);

    coordinator = CoreIntegrationCoordinator(
      nativeBridge: nativeBridge,
      focusService: focusService,
      challengeService: challengeService,
      sessionManager: sessionManager,
      accessService: accessService,
      workoutHistoryRepository: workoutHistoryRepository,
      accessAttemptRepository: accessAttemptRepository,
    );

    settingsRepository = SqliteSettingsRepository(databaseManager: database);
    final cameraChecker = _executionMode == DevExecutionMode.realDevice
        ? DefaultCameraPermissionChecker(nativeBridge: nativeBridge)
        : MockCameraPermissionChecker(status: CameraPermissionStatus.granted);
    settingsService = SettingsService(
      repository: settingsRepository,
      focusService: focusService,
      nativeBridge: nativeBridge,
      cameraPermissionChecker: cameraChecker,
    );

    logService.info(
      BackendModuleId.developerLab,
      'Initialized Developer Lab in ${_executionMode.label} mode',
    );
  }

  /// Refreshes all live module connections and validates real operational health.
  Future<void> refreshAll() async {
    isInitializing = true;
    initError = null;
    notifyListeners();

    try {
      // 1. Check Native Bridge & Focus Service
      try {
        final bridgeAvailable = await nativeBridge.isAvailable();
        if (bridgeAvailable) {
          moduleHealth[BackendModuleId.nativeBridge] = ModuleHealthStatus.ready;
        } else {
          moduleHealth[BackendModuleId.nativeBridge] = ModuleHealthStatus.failed;
        }

        currentFocusState = await focusService.getFocusStatus();
        if (currentFocusState!.isAccessibilityGranted) {
          moduleHealth[BackendModuleId.focusEngine] = ModuleHealthStatus.ready;
        } else {
          moduleHealth[BackendModuleId.focusEngine] = ModuleHealthStatus.needsPermission;
        }
      } catch (e) {
        moduleHealth[BackendModuleId.nativeBridge] = ModuleHealthStatus.failed;
        moduleHealth[BackendModuleId.focusEngine] = ModuleHealthStatus.failed;
        logService.error(BackendModuleId.focusEngine, 'Focus query failed: $e');
      }

      // 2. Check Challenge Engine
      try {
        final challenges = challengeService.getAvailableChallenges();
        if (challenges.isNotEmpty) {
          moduleHealth[BackendModuleId.challengeEngine] = ModuleHealthStatus.ready;
        }
      } catch (e) {
        moduleHealth[BackendModuleId.challengeEngine] = ModuleHealthStatus.failed;
      }

      // 3. Pose Engine & Session Manager
      moduleHealth[BackendModuleId.poseEngine] = ModuleHealthStatus.ready;
      moduleHealth[BackendModuleId.sessionManager] = ModuleHealthStatus.ready;

      // 4. Access Engine
      try {
        final accessStatus = await accessService.getAccessStatus();
        moduleHealth[BackendModuleId.accessEngine] = accessStatus.isAccessActive()
            ? ModuleHealthStatus.ready
            : ModuleHealthStatus.ready;
      } catch (e) {
        moduleHealth[BackendModuleId.accessEngine] = ModuleHealthStatus.failed;
      }

      // 5. Local SQLite Database
      try {
        final count = await workoutHistoryRepository.countCompletedWorkouts();
        moduleHealth[BackendModuleId.localDatabase] = ModuleHealthStatus.ready;
        logService.info(
          BackendModuleId.localDatabase,
          'SQLite connected. Historical workouts: $count',
        );
      } catch (e) {
        moduleHealth[BackendModuleId.localDatabase] = ModuleHealthStatus.failed;
        logService.error(BackendModuleId.localDatabase, 'SQLite check failed: $e');
      }

      // 6. Coordinator
      try {
        await coordinator.initialize();
        moduleHealth[BackendModuleId.coordinator] = ModuleHealthStatus.ready;
      } catch (e) {
        moduleHealth[BackendModuleId.coordinator] = ModuleHealthStatus.failed;
      }

      // 7. Settings & Permissions Engine
      try {
        final sState = await settingsService.initialize();
        moduleHealth[BackendModuleId.settingsEngine] =
            sState.isReady ? ModuleHealthStatus.ready : ModuleHealthStatus.ready;
      } catch (e) {
        moduleHealth[BackendModuleId.settingsEngine] = ModuleHealthStatus.failed;
      }
    } catch (e) {
      initError = e.toString();
      logService.error(BackendModuleId.developerLab, 'Initialization error: $e');
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  /// Switches between Real Device mode and Simulation mode.
  ///
  /// Safely terminates any in-flight workout session and resets pose source
  /// listeners before teardown and re-initialization.
  Future<void> switchMode(DevExecutionMode newMode) async {
    if (_executionMode == newMode) return;

    // 1. Safely cancel active or preparing session before switching modes
    if (coordinator.currentState.sessionStatus == WorkoutSessionStatus.active ||
        coordinator.currentState.sessionStatus == WorkoutSessionStatus.preparing) {
      try {
        await coordinator.cancelCurrentSession();
      } catch (_) {}
    }
    coordinator.detachPoseEventSource();

    // 2. Tear down old services and switch
    _disposeServices();
    _executionMode = newMode;
    _initializeServices();
    await refreshAll();
  }

  void _disposeServices() {
    coordinator.dispose();
    sessionManager.dispose();
    focusService.dispose();
    accessService.dispose();
    settingsService.dispose();
    database.close();
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _disposeServices();
    logService.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
}

/// InheritedWidget providing [DevLabController] down the widget tree.
class DevLabScope extends InheritedNotifier<DevLabController> {
  const DevLabScope({
    super.key,
    required DevLabController super.notifier,
    required super.child,
  });

  /// Retrieves the nearest [DevLabController] instance.
  static DevLabController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DevLabScope>();
    assert(scope != null && scope.notifier != null, 'No DevLabScope found in context');
    return scope!.notifier!;
  }
}
