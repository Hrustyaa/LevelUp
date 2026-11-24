import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/channel_constants.dart';
import '../../../../core/integration/core_integration_coordinator.dart';
import '../../../../core/integration/pose_event_adapter.dart';
import '../../../../data/database/levelup_database.dart';
import '../../../../data/repositories/access_attempt_repository.dart';
import '../../../../data/repositories/workout_history_repository.dart';
import '../../../../features/challenge/application/challenge_service.dart';
import '../../../../features/challenge/application/workout_session_manager.dart';
import '../../../../features/challenge/data/challenge_catalog.dart';
import '../../../../features/focus/application/focus_service.dart';
import '../../../../features/pose_detection/application/squat_counter.dart';
import '../../../../features/pose_detection/application/squat_geometry.dart';
import '../../../../features/settings/application/camera_permission_checker.dart';
import '../../../../features/settings/application/settings_service.dart';
import '../../../../features/settings/data/settings_repository.dart';
import '../../../../features/settings/models/app_settings.dart';
import '../../../../features/settings/models/camera_permission_status.dart';
import '../../../../models/access_attempt_state.dart';
import '../../../../services/access_service.dart';
import '../../di/dev_lab_scope.dart';
import '../../models/diagnostic_event.dart';
import '../models/test_scenario.dart';

/// Small, safe test harness that builds and runs module diagnostic scenarios.
///
/// Enforces strict isolation:
/// - Isolated in-app scenarios use in-memory/disposable SQLite databases.
/// - Injected [SimulationBridge] prevents real IPC or native grant invocation.
/// - Real-device probes are strictly read-only checks.
/// - Manual checklist items can never be auto-passed by software.
class TestScenarioRunner with ChangeNotifier {
  final DevLabController _controller;
  late final List<TestScenario> scenarios;

  bool _isRunningBatch = false;
  bool get isRunningBatch => _isRunningBatch;

  TestScenarioRunner(this._controller) {
    scenarios = _buildCatalog();
  }

  /// Groups scenarios by their target backend module.
  Map<BackendModuleId, List<TestScenario>> get scenariosByModule {
    final map = <BackendModuleId, List<TestScenario>>{};
    for (final s in scenarios) {
      map.putIfAbsent(s.moduleId, () => []).add(s);
    }
    return map;
  }

  /// Executes a single test scenario safely.
  Future<void> runScenario(TestScenario scenario) async {
    if (scenario.action == null) return; // Checklist or ref
    if (scenario.status == TestRunStatus.running) return;

    scenario.status = TestRunStatus.running;
    scenario.errorMessage = null;
    scenario.outputMessage = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();
    try {
      final result = await scenario.action!();
      stopwatch.stop();

      scenario.status = result.status;
      scenario.outputMessage = result.message;
      scenario.errorMessage = result.error;
      scenario.logs = result.logs;
      scenario.durationMs = stopwatch.elapsedMilliseconds;
      scenario.executedAt = DateTime.now();

      _controller.logService.log(DiagnosticEvent(
        module: scenario.moduleId,
        level: result.status == TestRunStatus.pass
            ? DevLogLevel.success
            : (result.status == TestRunStatus.blocked
                ? DevLogLevel.warning
                : DevLogLevel.error),
        message: 'Test [${scenario.id}]: ${result.status.label}',
        details: result.error ?? result.message,
        category: 'test_center',
      ));
    } catch (e, stack) {
      stopwatch.stop();
      scenario.status = TestRunStatus.fail;
      scenario.errorMessage = e.toString();
      scenario.logs = stack.toString();
      scenario.durationMs = stopwatch.elapsedMilliseconds;
      scenario.executedAt = DateTime.now();

      _controller.logService.error(
        scenario.moduleId,
        'Test [${scenario.id}] Exception: $e',
        stack.toString(),
      );
    } finally {
      notifyListeners();
    }
  }

  /// Runs all runnable scenarios for a given module.
  Future<void> runModuleScenarios(BackendModuleId moduleId) async {
    final moduleList = scenariosByModule[moduleId] ?? [];
    for (final s in moduleList) {
      if (s.action != null) {
        await runScenario(s);
      }
    }
  }

  /// Runs all runnable isolated in-app and safe probe scenarios.
  Future<void> runAllExecutableScenarios() async {
    if (_isRunningBatch) return;
    _isRunningBatch = true;
    notifyListeners();

    try {
      for (final s in scenarios) {
        if (s.action != null) {
          await runScenario(s);
        }
      }
    } finally {
      _isRunningBatch = false;
      notifyListeners();
    }
  }

  /// Manually toggles the pass status of a physical checklist item.
  void toggleChecklistPass(TestScenario scenario) {
    if (scenario.executionType != TestExecutionType.manualChecklist) return;
    if (scenario.status == TestRunStatus.pass) {
      scenario.status = TestRunStatus.notRun;
      scenario.outputMessage = null;
    } else {
      scenario.status = TestRunStatus.pass;
      scenario.outputMessage = 'Verified manually on physical device by tester.';
      scenario.executedAt = DateTime.now();
    }
    notifyListeners();
  }

  // =========================================================================
  // TEST SCENARIO CATALOG
  // =========================================================================

  List<TestScenario> _buildCatalog() {
    return [
      // -----------------------------------------------------------------------
      // MODULE 01 — NATIVE BRIDGE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M01_PROBE_AVAILABLE',
        moduleId: BackendModuleId.nativeBridge,
        title: 'Platform Availability Probe',
        description: 'Queries native bridge isAvailable() check.',
        executionType: TestExecutionType.realDeviceProbe,
        action: () async {
          final isAvail = await _controller.nativeBridge.isAvailable();
          if (isAvail) {
            return TestScenarioResult.pass('Native bridge is available.');
          } else {
            return TestScenarioResult.fail('Native bridge returned false for isAvailable().');
          }
        },
      ),
      TestScenario(
        id: 'M01_PROBE_GET_STATE',
        moduleId: BackendModuleId.nativeBridge,
        title: 'Native getState Diagnostic Probe',
        description: 'Calls native getState() to read active target and gate status.',
        executionType: TestExecutionType.realDeviceProbe,
        action: () async {
          final state = await _controller.nativeBridge.getState();
          return TestScenarioResult.pass(
            'Target: ${state.targetPackage}, GateEnabled: ${state.isGateEnabled}, '
            'AccessGranted: ${state.permissionStatus.isAccessibilityGranted}',
          );
        },
      ),
      TestScenario(
        id: 'M01_ISOLATED_TARGETS',
        moduleId: BackendModuleId.nativeBridge,
        title: 'Allowed Target Packages Validation',
        description: 'Verifies allowed targets contain YouTube, Instagram, TikTok and rejects unknown apps.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final allowed = ChannelConstants.allowedTargets;
          if (!allowed.contains('com.google.android.youtube') ||
              !allowed.contains('com.instagram.android') ||
              !allowed.contains('com.zhiliaoapp.musically')) {
            return TestScenarioResult.fail('Missing supported target package in allowedTargets.');
          }
          if (allowed.contains('com.android.settings')) {
            return TestScenarioResult.fail('System settings must never be in allowed targets.');
          }
          return TestScenarioResult.pass('All 3 supported targets correctly isolated.');
        },
      ),
      TestScenario(
        id: 'M01_ISOLATED_ERRORS',
        moduleId: BackendModuleId.nativeBridge,
        title: 'Native Exception Wrapping Invariant',
        description: 'Verifies that platform channel errors are sanitized into NativeBridgeException.',
        executionType: TestExecutionType.automatedTestRef,
        status: TestRunStatus.pass,
        outputMessage: 'Verified in native_bridge_test.dart: wraps PlatformException in NativeBridgeException.',
      ),

      // -----------------------------------------------------------------------
      // MODULE 02 — FOCUS ENGINE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M02_PROBE_FOCUS_STATUS',
        moduleId: BackendModuleId.focusEngine,
        title: 'Current Focus State Query',
        description: 'Reads authoritative Focus status from FocusService.',
        executionType: TestExecutionType.realDeviceProbe,
        action: () async {
          final focus = await _controller.focusService.getFocusStatus();
          return TestScenarioResult.pass(
            'Target: ${focus.selectedTarget}, Enabled: ${focus.isUserEnabled}, '
            'Accessibility: ${focus.isAccessibilityGranted}, ActiveAccess: ${focus.isAccessActive}',
          );
        },
      ),
      TestScenario(
        id: 'M02_ISOLATED_INVALID_TARGET',
        moduleId: BackendModuleId.focusEngine,
        title: 'Invalid Target Package Rejection',
        description: 'FocusService must throw UnsupportedTargetException on invalid target package.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final bridge = SimulationBridge();
          final service = FocusService(bridge: bridge);
          try {
            await service.selectTargetApp('com.malicious.fake');
            return TestScenarioResult.fail('Did not throw on invalid target package.');
          } catch (e) {
            return TestScenarioResult.pass('Correctly rejected invalid target with exception: $e');
          } finally {
            service.dispose();
          }
        },
      ),
      TestScenario(
        id: 'M02_ISOLATED_ENABLE_LOGIC',
        moduleId: BackendModuleId.focusEngine,
        title: 'Focus Toggle Logic Verification',
        description: 'Verifies enableFocus and disableFocus update bridge without leaking unhandled exceptions.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final bridge = SimulationBridge();
          final service = FocusService(bridge: bridge);
          await service.enableFocus();
          final state = await service.getFocusStatus();
          if (!state.isUserEnabled) {
            return TestScenarioResult.fail('Focus was not enabled.');
          }
          await service.disableFocus();
          final state2 = await service.getFocusStatus();
          if (state2.isUserEnabled) {
            return TestScenarioResult.fail('Focus was not disabled.');
          }
          service.dispose();
          return TestScenarioResult.pass('Focus toggle logic operates idempotently.');
        },
      ),

      // -----------------------------------------------------------------------
      // MODULE 03 — CHALLENGE ENGINE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M03_ISOLATED_CATALOG',
        moduleId: BackendModuleId.challengeEngine,
        title: 'Challenge Catalog Invariants',
        description: 'Verifies default unlock challenge defines exactly 5 squats for 300 seconds (5m).',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final unlock = ChallengeCatalog.squatUnlockChallenge;
          if (unlock.targetRepetitions != 5 ||
              unlock.accessDurationSeconds != 300 ||
              unlock.exerciseType != ExerciseType.squats) {
            return TestScenarioResult.fail(
              'Unlock definition violation: reps=${unlock.targetRepetitions}, duration=${unlock.accessDurationSeconds}',
            );
          }

          final free = ChallengeCatalog.squatFreeWorkout;
          if (free.targetRepetitions != 5 ||
              free.accessDurationSeconds != 0 ||
              free.exerciseType != ExerciseType.squats) {
            return TestScenarioResult.fail('Free workout definition violation: duration must be 0s.');
          }

          return TestScenarioResult.pass('Unlock (5 reps = 300s) and Free Workout definitions verified.');
        },
      ),
      TestScenario(
        id: 'M03_ISOLATED_VALIDATION',
        moduleId: BackendModuleId.challengeEngine,
        title: 'Challenge Request Validation',
        description: 'ChallengeService rejects unknown challenge ID and invalid challenge context.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final service = ChallengeService();
          try {
            service.createUnlockChallengeRequest('com.invalid.app');
            return TestScenarioResult.fail('Did not reject invalid target package.');
          } catch (e) {
            return TestScenarioResult.pass('Correctly rejected invalid challenge request: $e');
          }
        },
      ),

      // -----------------------------------------------------------------------
      // MODULE 04 — POSE ENGINE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M04_ISOLATED_GEOMETRY',
        moduleId: BackendModuleId.poseEngine,
        title: 'SquatGeometry Mathematical Calculations',
        description: 'Validates 3-point knee joint angle computation and collinear straight-leg case.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          // 1. Straight leg (180 deg)
          final straight = SquatGeometry.calculateKneeAngle(
            const Offset(100, 0),
            const Offset(100, 100),
            const Offset(100, 200),
          );
          if (straight == null || (straight - 180.0).abs() > 0.5) {
            return TestScenarioResult.fail('Straight leg angle expected 180°, got $straight°');
          }

          // 2. 90-degree right-angle squat
          final rightAngle = SquatGeometry.calculateKneeAngle(
            const Offset(0, 100),
            const Offset(100, 100),
            const Offset(100, 200),
          );
          if (rightAngle == null || (rightAngle - 90.0).abs() > 0.5) {
            return TestScenarioResult.fail('Right-angle knee expected 90°, got $rightAngle°');
          }

          return TestScenarioResult.pass('SquatGeometry calculates exact geometric joint angles.');
        },
      ),
      TestScenario(
        id: 'M04_ISOLATED_SQUAT_COUNTER',
        moduleId: BackendModuleId.poseEngine,
        title: 'Squat State Machine & Debounce Verification',
        description: 'Validates 2 consecutive down (<125°) and 2 up (>155°) frames required per repetition.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final counter = SquatCounter();

          // 1. Partial squat (130 deg - not deep enough)
          counter.processAngle(130.0);
          counter.processAngle(130.0);
          counter.processAngle(165.0);
          counter.processAngle(165.0);
          if (counter.repetitionCount != 0) {
            return TestScenarioResult.fail('Partial squat incorrectly counted as repetition.');
          }

          // 2. Valid squat (110 deg down x 2, 165 deg up x 2)
          counter.processAngle(110.0);
          counter.processAngle(110.0);
          counter.processAngle(165.0);
          final res = counter.processAngle(165.0);
          if (res.repetitionCount != 1 || !res.isRepetitionCompleted) {
            return TestScenarioResult.fail('Valid 2-down 2-up cycle did not count 1 repetition.');
          }

          return TestScenarioResult.pass('SquatCounter debounce and depth thresholds verified.');
        },
      ),

      // -----------------------------------------------------------------------
      // MODULE 05 — WORKOUT SESSION MANAGER
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M05_ISOLATED_LIFECYCLE',
        moduleId: BackendModuleId.sessionManager,
        title: 'Session Manager State Machine',
        description: 'Verifies creation -> preparing -> start -> progress -> completion lifecycle.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final challengeService = ChallengeService();
          final manager = WorkoutSessionManager(challengeService: challengeService);

          final req = challengeService.createUnlockChallengeRequest('com.google.android.youtube');
          final s = manager.createSession(req);
          if (s.status != WorkoutSessionStatus.created) {
            return TestScenarioResult.fail('Expected created status');
          }

          final prep = manager.prepareSession(s.sessionId);
          if (prep.status != WorkoutSessionStatus.preparing) {
            return TestScenarioResult.fail('Expected preparing status');
          }

          final active = manager.startSession(s.sessionId);
          if (active.status != WorkoutSessionStatus.active) {
            return TestScenarioResult.fail('Expected active status');
          }

          final prog = manager.updateVerifiedProgress(s.sessionId, cumulativeReps: 5);
          if (prog.status != WorkoutSessionStatus.completed) {
            return TestScenarioResult.fail('Expected completed status at 5 reps');
          }

          final result = manager.completeSession(s.sessionId);
          if (result.completedRepetitions != 5 || !result.eligibleForAccess) {
            return TestScenarioResult.fail('Invalid WorkoutResult produced.');
          }

          manager.dispose();
          return TestScenarioResult.pass('Full session lifecycle verified end-to-end.');
        },
      ),
      TestScenario(
        id: 'M05_ISOLATED_MULTIPLE_SESSIONS',
        moduleId: BackendModuleId.sessionManager,
        title: 'Multiple Active Sessions Protection',
        description: 'SessionManager must reject creating a new session while another is active.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final challengeService = ChallengeService();
          final manager = WorkoutSessionManager(challengeService: challengeService);

          final req1 = challengeService.createUnlockChallengeRequest('com.google.android.youtube');
          manager.createSession(req1);

          final req2 = challengeService.createUnlockChallengeRequest('com.instagram.android');
          try {
            manager.createSession(req2);
            return TestScenarioResult.fail('Did not reject concurrent session creation.');
          } catch (e) {
            manager.dispose();
            return TestScenarioResult.pass('Correctly rejected duplicate active session: $e');
          }
        },
      ),

      // -----------------------------------------------------------------------
      // MODULE 06 — ACCESS ENGINE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M06_ISOLATED_INCOMPLETE_REJECTION',
        moduleId: BackendModuleId.accessEngine,
        title: 'Incomplete Workout Access Rejection',
        description: 'AccessService must reject WorkoutResult with <5 verified repetitions.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final bridge = SimulationBridge();
          final accessService = AccessService(bridge: bridge);

          final incompleteResult = WorkoutResult(
            sessionId: 'test_incomplete',
            requestId: 'req_1',
            challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
            challengeContext: ChallengeType.unlockChallenge,
            exerciseType: ExerciseType.squats,
            targetPackage: 'com.google.android.youtube',
            completedRepetitions: 4, // 4 instead of required 5
            duration: const Duration(seconds: 40),
            completedAt: DateTime.now(),
            eligibleForAccess: true,
            accessDurationSeconds: 300,
          );

          try {
            await accessService.grantAccessForCompletedWorkout(incompleteResult);
            return TestScenarioResult.fail('AccessService granted access for incomplete 4-rep workout.');
          } catch (e) {
            return TestScenarioResult.pass('Incomplete workout strictly rejected with: $e');
          } finally {
            accessService.dispose();
          }
        },
      ),
      TestScenario(
        id: 'M06_ISOLATED_FREE_WORKOUT_NO_GRANT',
        moduleId: BackendModuleId.accessEngine,
        title: 'Free Workout Cannot Grant Access Invariant',
        description: 'AccessService must throw when presented with a Free Workout context.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final bridge = SimulationBridge();
          final accessService = AccessService(bridge: bridge);

          final freeResult = WorkoutResult(
            sessionId: 'test_free',
            requestId: 'req_free',
            challengeId: ChallengeCatalog.squatFreeWorkout.challengeId,
            challengeContext: ChallengeType.freeWorkout,
            exerciseType: ExerciseType.squats,
            targetPackage: null,
            completedRepetitions: 5,
            duration: const Duration(seconds: 50),
            completedAt: DateTime.now(),
            eligibleForAccess: false,
            accessDurationSeconds: 0,
          );

          try {
            await accessService.grantAccessForCompletedWorkout(freeResult);
            return TestScenarioResult.fail('AccessService allowed Free Workout to invoke grant.');
          } catch (e) {
            return TestScenarioResult.pass('Free Workout strictly rejected from native grant path: $e');
          } finally {
            accessService.dispose();
          }
        },
      ),

      // -----------------------------------------------------------------------
      // MODULE 07 — SQLITE LOCAL DATABASE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M07_ISOLATED_CRUD_SANDBOX',
        moduleId: BackendModuleId.localDatabase,
        title: 'Disposable SQLite CRUD & State Transitions',
        description: 'Runs isolated DB transactions in a temporary test database (never touches real data).',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final tempDbName = 'test_disposable_${DateTime.now().microsecondsSinceEpoch}.db';
          final tempDb = LevelUpDatabase(customPath: tempDbName);

          final workoutRepo = WorkoutHistoryRepository(databaseManager: tempDb);
          final attemptRepo = AccessAttemptRepository(databaseManager: tempDb);

          // 1. Insert workout
          final res = WorkoutResult(
            sessionId: 'test_crud_1',
            requestId: 'req_crud_1',
            challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
            challengeContext: ChallengeType.unlockChallenge,
            exerciseType: ExerciseType.squats,
            targetPackage: 'com.google.android.youtube',
            completedRepetitions: 5,
            duration: const Duration(seconds: 45),
            completedAt: DateTime.now(),
            eligibleForAccess: true,
            accessDurationSeconds: 300,
          );
          await workoutRepo.saveCompletedWorkout(res);

          final retrieved = await workoutRepo.getWorkoutBySessionId('test_crud_1');
          if (retrieved == null || retrieved.completedRepetitions != 5) {
            await tempDb.close();
            return TestScenarioResult.fail('Workout not accurately retrieved from test SQLite table.');
          }

          // 2. Audit attempt state machine
          final attempt = await attemptRepo.createAttemptIfAbsent(
            sessionId: 'test_crud_1',
            targetPackage: 'com.google.android.youtube',
            durationSeconds: 300,
            attemptedAt: DateTime.now(),
          );
          if (attempt.state != AccessAttemptState.prepared) {
            await tempDb.close();
            return TestScenarioResult.fail('Expected prepared state');
          }

          final confirmed = await attemptRepo.markConfirmed(
            sessionId: 'test_crud_1',
            confirmedAt: DateTime.now(),
            unlockUntil: DateTime.now().add(const Duration(minutes: 5)),
          );
          if (confirmed.state != AccessAttemptState.confirmed) {
            await tempDb.close();
            return TestScenarioResult.fail('Expected confirmed state');
          }

          await tempDb.close();
          return TestScenarioResult.pass('SQLite CRUD and state machine verified in isolated test database.');
        },
      ),
      TestScenario(
        id: 'M07_ISOLATED_CONFLICT_REJECTION',
        moduleId: BackendModuleId.localDatabase,
        title: 'Conflicting Record Rejection Invariant',
        description: 'SQLite repository rejects conflicting payloads for the same session ID.',
        executionType: TestExecutionType.automatedTestRef,
        status: TestRunStatus.pass,
        outputMessage: 'Verified in workout_history_repository_test.dart & access_attempt_repository_test.dart',
      ),

      // -----------------------------------------------------------------------
      // CORE INTEGRATION COORDINATOR
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'COORD_ISOLATED_FULL_WORKFLOW',
        moduleId: BackendModuleId.coordinator,
        title: 'Complete Unlock Workflow in Sandbox',
        description: 'Drives PoseEngine -> Coordinator -> SQLite -> SimulationBridge end-to-end.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final tempDbName = 'test_coord_${DateTime.now().microsecondsSinceEpoch}.db';
          final tempDb = LevelUpDatabase(
            databaseFactory: _controller.database.factory,
            customPath: tempDbName,
          );
          final bridge = SimulationBridge(challengeRequested: true);

          final focusService = FocusService(bridge: bridge);
          final challengeService = ChallengeService();
          final sessionManager = WorkoutSessionManager(challengeService: challengeService);
          final accessService = AccessService(bridge: bridge);
          final workoutRepo = WorkoutHistoryRepository(databaseManager: tempDb);
          final attemptRepo = AccessAttemptRepository(databaseManager: tempDb);

          final coordinator = CoreIntegrationCoordinator(
            nativeBridge: bridge,
            focusService: focusService,
            challengeService: challengeService,
            sessionManager: sessionManager,
            accessService: accessService,
            workoutHistoryRepository: workoutRepo,
            accessAttemptRepository: attemptRepo,
          );

          await coordinator.initialize();
          final session = await coordinator.launchUnlockChallenge(requirePendingRequest: true);

          final adapter = PoseEngineAdapter(isSimulated: true);
          coordinator.attachPoseEventSource(adapter);

          // Simulate 5 verified squats
          for (int i = 0; i < 5; i++) {
            adapter.processAngle(110.0);
            adapter.processAngle(110.0);
            adapter.processAngle(165.0);
            adapter.processAngle(165.0);
            await Future<void>.delayed(Duration.zero);
          }

          await Future<void>.delayed(const Duration(milliseconds: 50));
          await coordinator.waitForCompletion();

          if (coordinator.currentState.sessionStatus != WorkoutSessionStatus.completed) {
            await tempDb.close();
            return TestScenarioResult.fail('Session not completed in coordinator.');
          }

          // Check DB persistence
          final savedWorkout = await workoutRepo.getWorkoutBySessionId(session.sessionId);
          final savedAttempt = await attemptRepo.getAttemptBySessionId(session.sessionId);

          if (savedWorkout == null || savedAttempt == null || savedAttempt.state != AccessAttemptState.confirmed) {
            await tempDb.close();
            return TestScenarioResult.fail('Workflow did not persist confirmed result and attempt in SQLite.');
          }

          coordinator.dispose();
          sessionManager.dispose();
          focusService.dispose();
          accessService.dispose();
          await tempDb.close();

          return TestScenarioResult.pass('End-to-end workflow completed, granted access and persisted in sandbox DB.');
        },
      ),

      // -----------------------------------------------------------------------
      // MODULE 08 — SETTINGS & PERMISSIONS ENGINE
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'M08_PROBE_CURRENT_SETTINGS',
        moduleId: BackendModuleId.settingsEngine,
        title: 'Authoritative Settings & Permissions Probe',
        description: 'Queries SettingsService for live settings snapshot and hardware permission state.',
        executionType: TestExecutionType.realDeviceProbe,
        action: () async {
          final state = await _controller.settingsService.refresh();
          return TestScenarioResult.pass(
            'Target: ${state.activeTargetPackage}, Duration: ${state.settings.defaultUnlockDurationSeconds}s, '
            'A11y: ${state.isAccessibilityGranted}, Camera: ${state.cameraStatus.label}',
          );
        },
      ),
      TestScenario(
        id: 'M08_ISOLATED_DEFAULT_INIT',
        moduleId: BackendModuleId.settingsEngine,
        title: 'Deterministic Settings Defaults Initialization',
        description: 'Verifies standard defaults (YouTube, 300s, emergency pause enabled, sound enabled).',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final repo = InMemorySettingsRepository();
          final bridge = SimulationBridge();
          final focus = FocusService(bridge: bridge);
          final service = SettingsService(
            repository: repo,
            focusService: focus,
            nativeBridge: bridge,
            cameraPermissionChecker: MockCameraPermissionChecker(),
          );

          try {
            final state = await service.initialize();
            if (state.settings.defaultTargetPackage != ChannelConstants.targetYouTube ||
                state.settings.defaultUnlockDurationSeconds != 300 ||
                !state.settings.emergencyPauseAllowed ||
                !state.settings.soundFeedbackEnabled) {
              return TestScenarioResult.fail('Settings defaults mismatch: ${state.settings}');
            }
            return TestScenarioResult.pass('All standard defaults verified.');
          } finally {
            service.dispose();
            focus.dispose();
          }
        },
      ),
      TestScenario(
        id: 'M08_ISOLATED_CRUD_PERSISTENCE',
        moduleId: BackendModuleId.settingsEngine,
        title: 'SQLite App Settings Persistence & Reload',
        description: 'Persists custom preferences to an isolated SQLite DB and verifies reload across instances.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final tempDbName = 'test_settings_${DateTime.now().microsecondsSinceEpoch}.db';
          final tempDb = LevelUpDatabase(
            databaseFactory: _controller.database.factory,
            customPath: tempDbName,
          );

          try {
            final repo1 = SqliteSettingsRepository(databaseManager: tempDb);
            const customSettings = AppSettings(
              defaultTargetPackage: ChannelConstants.targetInstagram,
              defaultUnlockDurationSeconds: 300,
              emergencyPauseAllowed: true,
              soundFeedbackEnabled: false,
              diagnosticLoggingEnabled: false,
            );
            await repo1.saveSettings(customSettings);

            final repo2 = SqliteSettingsRepository(databaseManager: tempDb);
            final loaded = await repo2.loadSettings();

            if (loaded != customSettings) {
              return TestScenarioResult.fail('Loaded settings did not match persisted settings: $loaded');
            }
            return TestScenarioResult.pass('Settings persisted and reloaded cleanly from SQLite.');
          } finally {
            await tempDb.close();
          }
        },
      ),
      TestScenario(
        id: 'M08_ISOLATED_INVALID_SETTINGS_REJECTION',
        moduleId: BackendModuleId.settingsEngine,
        title: 'Domain Validation & Invariant Protection',
        description: 'Verifies rejection of unsupported target packages and invalid durations.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          const invalidTarget = AppSettings(
            defaultTargetPackage: 'com.android.settings',
            defaultUnlockDurationSeconds: 300,
            emergencyPauseAllowed: true,
            soundFeedbackEnabled: true,
            diagnosticLoggingEnabled: true,
          );

          try {
            invalidTarget.validate();
            return TestScenarioResult.fail('Did not reject invalid package "com.android.settings".');
          } catch (_) {}

          const invalidDuration = AppSettings(
            defaultTargetPackage: ChannelConstants.targetYouTube,
            defaultUnlockDurationSeconds: 15, // < 60s
            emergencyPauseAllowed: true,
            soundFeedbackEnabled: true,
            diagnosticLoggingEnabled: true,
          );

          try {
            invalidDuration.validate();
            return TestScenarioResult.fail('Did not reject non-300s duration.');
          } catch (_) {}

          return TestScenarioResult.pass('All invalid settings strictly rejected.');
        },
      ),
      TestScenario(
        id: 'M08_ISOLATED_STORAGE_FAILURE_RECOVERY',
        moduleId: BackendModuleId.settingsEngine,
        title: 'Graceful Storage Failure Recovery',
        description: 'Verifies fallback to deterministic defaults when storage throws or is corrupted.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final faultyRepo = InMemorySettingsRepository()..shouldFailLoad = true;
          final loaded = await faultyRepo.loadSettings();
          if (loaded != AppSettings.defaults()) {
            return TestScenarioResult.fail('Faulty repository did not fall back to defaults: $loaded');
          }
          return TestScenarioResult.pass('Recovered gracefully from storage failure with defaults.');
        },
      ),
      TestScenario(
        id: 'M08_ISOLATED_PERMISSION_REVOCATION',
        moduleId: BackendModuleId.settingsEngine,
        title: 'External Permission Revocation Detection',
        description: 'Simulates OS settings permission revocation and verifies reactive state update.',
        executionType: TestExecutionType.isolatedScenario,
        action: () async {
          final cameraChecker = MockCameraPermissionChecker(status: CameraPermissionStatus.granted);
          final bridge = SimulationBridge();
          final focus = FocusService(bridge: bridge);
          final service = SettingsService(
            repository: InMemorySettingsRepository(),
            focusService: focus,
            nativeBridge: bridge,
            cameraPermissionChecker: cameraChecker,
          );

          try {
            var state = await service.initialize();
            if (!state.isReadyForChallenges) {
              return TestScenarioResult.fail('Initial state was not ready for challenges.');
            }

            // Simulate user revoking camera in Android Settings
            cameraChecker.revokePermission();
            state = await service.refresh();

            if (state.isCameraGranted || state.isReadyForChallenges) {
              return TestScenarioResult.fail('Service failed to detect revoked camera permission.');
            }
            return TestScenarioResult.pass('Externally revoked permission successfully detected on refresh.');
          } finally {
            service.dispose();
            focus.dispose();
          }
        },
      ),

      // -----------------------------------------------------------------------
      // CATEGORY D — MANUAL DEVICE CHECKLIST (Physical Verification Protocol)
      // -----------------------------------------------------------------------
      TestScenario(
        id: 'MANUAL_OVERLAY_LATCH',
        moduleId: BackendModuleId.nativeBridge,
        title: 'Target Launch Shows Latched Overlay',
        description: 'Opening Instagram/YouTube with Focus ON triggers the full-screen blocking overlay.',
        executionType: TestExecutionType.manualChecklist,
      ),
      TestScenario(
        id: 'MANUAL_START_CHALLENGE',
        moduleId: BackendModuleId.focusEngine,
        title: 'Start Challenge Opens DevLab Live Challenge',
        description: 'Tapping Start Challenge on overlay opens LevelUp directly into 0/5 squat challenge.',
        executionType: TestExecutionType.manualChecklist,
      ),
      TestScenario(
        id: 'MANUAL_REAL_SQUATS',
        moduleId: BackendModuleId.poseEngine,
        title: 'Real Physical Squat Camera Counting',
        description: 'Front camera ML Kit pose detector counts 5 real bodyweight squats to 5/5.',
        executionType: TestExecutionType.manualChecklist,
      ),
      TestScenario(
        id: 'MANUAL_EXACT_300S',
        moduleId: BackendModuleId.accessEngine,
        title: 'Authoritative 300-Second Access Grant',
        description: 'Completing 5 squats allows target app use for exactly 300 seconds before re-blocking.',
        executionType: TestExecutionType.manualChecklist,
      ),
      TestScenario(
        id: 'MANUAL_SETTINGS_NAVIGATION',
        moduleId: BackendModuleId.settingsEngine,
        title: 'Safe Navigation to Android System Settings',
        description: 'Tapping Open Accessibility or App Settings dispatches system intent without app crash.',
        executionType: TestExecutionType.manualChecklist,
      ),
    ];
  }
}
