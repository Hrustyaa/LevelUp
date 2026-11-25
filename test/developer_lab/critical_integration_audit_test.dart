import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/core/integration/pose_event_adapter.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/screens/live_challenge_screen.dart';
import 'package:levelup_test/features/developer_lab/screens/system_hub_screen.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late String dbPath;
  late LevelUpDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audit_test_');
    dbPath = p.join(tempDir.path, 'audit.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget createTestWidget(DevLabController controller, {Widget? home}) {
    return DevLabScope(
      notifier: controller,
      child: MaterialApp(
        theme: DevLabTheme.theme,
        home: home ?? const SystemHubScreen(),
      ),
    );
  }

  group('Critical Integration Audit Regression Tests', () {
    test('1. Native request is consumed exactly once by Coordinator and never by status refresh', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      // Multiple refresh operations must NOT consume the native flag
      await controller.refreshAll();
      await controller.refreshAll();
      expect(bridge.challengeRequested, isTrue);

      final consumeCallsBefore = bridge.callLog.where((c) => c == 'consumeChallengeRequest').length;
      expect(consumeCallsBefore, equals(0));

      // Coordinator consumes it authoritatively when launching unlock challenge
      await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      expect(bridge.challengeRequested, isFalse);

      final consumeCallsAfter = bridge.callLog.where((c) => c == 'consumeChallengeRequest').length;
      expect(consumeCallsAfter, equals(1));

      controller.dispose();
    });

    testWidgets('2. Pending native challenge successfully starts from the Developer Lab', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await tester.runAsync(() async {
        await controller.refreshAll();
      });

      await tester.pumpWidget(createTestWidget(controller));
      await tester.pumpAndSettle();

      expect(find.text('Blocker Overlay Challenge'), findsOneWidget);
      expect(find.text('Check & Launch'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Check & Launch'));
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(controller.coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.active));
      expect(controller.coordinator.currentState.challengeContext, equals(ChallengeType.unlockChallenge));
      expect(bridge.challengeRequested, isFalse);

      controller.dispose();
    });

    test('3. Repeated Launch taps do not create two sessions or lose consumed flag', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();

      // First launch succeeds
      final session1 = await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      expect(session1.status, equals(WorkoutSessionStatus.active));

      // Immediate second launch while session is active throws SessionAlreadyActiveException
      // WITHOUT re-consuming or corrupting the state
      expect(
        () => controller.coordinator.launchUnlockChallenge(requirePendingRequest: true),
        throwsA(isA<SessionAlreadyActiveException>()),
      );

      expect(controller.coordinator.currentState.sessionId, equals(session1.sessionId));

      controller.dispose();
    });

    test('4. Real Device mode rejects injected squat angles at service boundary', () async {
      // Setup coordinator with real NativeBridge class
      const realBridge = NativeBridge();
      final focusService = FocusService(bridge: realBridge);
      final challengeService = ChallengeService();
      final sessionManager = WorkoutSessionManager(challengeService: challengeService);
      final accessService = AccessService(bridge: realBridge);
      final workoutHistoryRepo = WorkoutHistoryRepository(databaseManager: database);
      final accessAttemptRepo = AccessAttemptRepository(databaseManager: database);

      final coordinator = CoreIntegrationCoordinator(
        nativeBridge: realBridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: workoutHistoryRepo,
        accessAttemptRepository: accessAttemptRepo,
      );

      // Attaching simulated pose adapter to a coordinator backed by real NativeBridge must throw StateError
      final simulatedAdapter = PoseEngineAdapter(isSimulated: true);
      expect(
        () => coordinator.attachPoseEventSource(simulatedAdapter),
        throwsStateError,
      );

      // Sending a simulated result directly to handlePoseResult must throw StateError
      const simulatedResult = SquatCounterResult(
        repetitionCount: 1,
        phase: SquatPhase.down,
        isRepetitionCompleted: false,
        kneeAngle: 110.0,
        isValidTracking: true,
        consecutiveDownFrames: 2,
        consecutiveUpFrames: 0,
        feedbackMessage: 'Down',
        isSimulated: true,
      );

      expect(
        () => coordinator.handlePoseResult(simulatedResult),
        throwsStateError,
      );

      coordinator.dispose();
      simulatedAdapter.dispose();
      sessionManager.dispose();
      focusService.dispose();
      accessService.dispose();
    });

    testWidgets('5. Camera unavailable in Real Device mode does not enable simulated real unlocking', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Controller in Real Device mode
      final bridge = SimulationBridge(); // Bridge can be simulation for test harness, but mode is realDevice
      final controller = DevLabController(
        initialMode: DevExecutionMode.realDevice,
        customBridge: bridge,
        customDatabase: database,
      );

      await tester.runAsync(() async {
        await controller.refreshAll();
      });

      await tester.pumpWidget(createTestWidget(controller, home: const LiveChallengeScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Camera is unavailable in desktop/test environment: must show blocked sensor state
      expect(find.text('Camera Sensor Required in Real Device Mode'), findsOneWidget);

      // Simulation testing toolset must NOT be rendered in Real Device mode
      expect(find.text('QA Simulation Toolset'), findsNothing);
      expect(find.text('Finish 5 Reps'), findsNothing);
      expect(find.text('Down (110°)'), findsNothing);

      controller.dispose();
    });

    test('6. Simulation Mode cannot invoke real native grant MethodChannel', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();
      await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);

      final adapter = PoseEngineAdapter(isSimulated: true);
      controller.coordinator.attachPoseEventSource(adapter);

      // Complete 5 simulated repetitions
      for (int i = 0; i < 5; i++) {
        adapter.processAngle(110.0);
        adapter.processAngle(110.0);
        adapter.processAngle(165.0);
        adapter.processAngle(165.0);
        await pumpEventQueue();
      }

      await controller.coordinator.waitForCompletion();

      // Granted in SimulationBridge in-memory state only
      expect(controller.coordinator.currentState.accessGrantStatus, equals(AccessGrantStatus.granted));
      expect(bridge.status.accessStatus.unlockUntil, isNotNull);
      expect(bridge.callLog, contains('grantAccess(5)'));

      // Real MethodChannel is untouched because NativeBridge was never created
      expect(controller.nativeBridge, isA<SimulationBridge>());

      controller.dispose();
      adapter.dispose();
    });

    test('7. Switching modes does not preserve an active session or its pending events', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();
      await controller.coordinator.launchFreeWorkout();

      expect(controller.coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.active));

      // Switch mode while workout is active
      await controller.switchMode(DevExecutionMode.realDevice);

      // The previous workout is terminated and coordinator is reset
      expect(controller.executionMode, equals(DevExecutionMode.realDevice));
      expect(controller.coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.created));
      expect(controller.coordinator.currentState.sessionId, isNull);

      controller.dispose();
    });

    test('8. Lifecycle resume does not double-consume the native request', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      // Multiple refresh cycles simulating resume
      await controller.refreshAll();
      expect(bridge.challengeRequested, isTrue);

      await controller.refreshAll();
      expect(bridge.challengeRequested, isTrue);

      // The one-time flag remains available for authoritative launch
      await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      expect(bridge.challengeRequested, isFalse);

      controller.dispose();
    });

    test('9. Free Workout cannot grant native access under any condition', () async {
      final bridge = SimulationBridge();
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();
      await controller.coordinator.launchFreeWorkout();

      final adapter = PoseEngineAdapter(isSimulated: true);
      controller.coordinator.attachPoseEventSource(adapter);

      for (int i = 0; i < 5; i++) {
        adapter.processAngle(110.0);
        adapter.processAngle(110.0);
        adapter.processAngle(165.0);
        adapter.processAngle(165.0);
        await pumpEventQueue();
      }

      await controller.coordinator.waitForCompletion();

      expect(controller.coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.completed));
      expect(controller.coordinator.currentState.verifiedRepetitions, equals(5));
      expect(controller.coordinator.currentState.accessGrantStatus, isNull);
      expect(bridge.status.accessStatus.unlockUntil, isNull);
      expect(bridge.callLog, isNot(contains('grantAccess(5)')));

      // SQLite workout history row was persisted
      final historyCount = await controller.workoutHistoryRepository.countCompletedWorkouts();
      expect(historyCount, equals(1));

      // Access attempts table has 0 rows for free workout
      final attempt = await controller.accessAttemptRepository.getAttemptBySessionId(
        controller.coordinator.currentState.sessionId!,
      );
      expect(attempt, isNull);

      controller.dispose();
      adapter.dispose();
    });

    test('10. Existing full unlock flow remains 100% compatible end-to-end', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();

      // Launch unlock challenge with pending native flag
      final session = await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      expect(session.status, equals(WorkoutSessionStatus.active));
      expect(bridge.challengeRequested, isFalse);

      final adapter = PoseEngineAdapter(isSimulated: true);
      controller.coordinator.attachPoseEventSource(adapter);

      // Perform 5 squats
      for (int i = 0; i < 5; i++) {
        adapter.processAngle(110.0);
        adapter.processAngle(110.0);
        adapter.processAngle(165.0);
        adapter.processAngle(165.0);
        await pumpEventQueue();
      }

      await controller.coordinator.waitForCompletion();

      expect(controller.coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.completed));
      expect(controller.coordinator.currentState.verifiedRepetitions, equals(5));
      expect(controller.coordinator.currentState.accessGrantStatus, equals(AccessGrantStatus.granted));
      expect(bridge.status.accessStatus.unlockUntil, isNotNull);

      // Verify SQLite records
      final historyCount = await controller.workoutHistoryRepository.countCompletedWorkouts();
      expect(historyCount, equals(1));

      final attempt = await controller.accessAttemptRepository.getAttemptBySessionId(session.sessionId);
      expect(attempt, isNotNull);
      expect(attempt!.isConfirmed, isTrue);

      controller.dispose();
      adapter.dispose();
    });
  });
}
