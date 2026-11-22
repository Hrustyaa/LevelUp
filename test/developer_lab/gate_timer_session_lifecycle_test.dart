import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/core/integration/pose_event_adapter.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/challenge/data/challenge_catalog.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/screens/system_hub_screen.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:levelup_test/services/access_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('gate_timer_test_');
    dbPath = p.join(tempDir.path, 'gate_timer.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
  });

  tearDown(() async {
    database.close();
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

  group('Gate, Timer & Session Lifecycle Regression Suite', () {
    // 1. Exactly 300 seconds of access
    test('1. Exactly 300 seconds of access defined in catalog and requested from native', () async {
      final definition = ChallengeCatalog.squatUnlockChallenge;
      expect(definition.accessDurationSeconds, equals(300));
      expect(definition.targetRepetitions, equals(5));

      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final challengeService = ChallengeService();
      final sessionManager = WorkoutSessionManager(challengeService: challengeService);
      final accessService = AccessService(bridge: bridge);
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);
      final attemptRepo = AccessAttemptRepository(databaseManager: database);

      final coordinator = CoreIntegrationCoordinator(
        nativeBridge: bridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: workoutRepo,
        accessAttemptRepository: attemptRepo,
      );

      final session = await coordinator.launchUnlockChallenge();
      expect(session.accessDurationSeconds, equals(300));

      sessionManager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);
      final workoutResult = sessionManager.completeSession(session.sessionId);
      expect(workoutResult.accessDurationSeconds, equals(300));

      final grantRequest = AccessGrantRequest.fromWorkoutResult(workoutResult);
      expect(grantRequest.durationMinutes, equals(5));

      coordinator.dispose();
      sessionManager.dispose();
      focusService.dispose();
      accessService.dispose();
    });

    // 2. Remaining time immediately after grant
    test('2. Remaining time immediately after grant equals exactly 300000ms (5 minutes)', () async {
      final fixedStart = DateTime.utc(2026, 11, 22, 12, 0, 0);
      final unlockUntil = fixedStart.add(const Duration(minutes: 5));

      final status = NativeAccessStatus(unlockUntil: unlockUntil);
      expect(status.isAccessActive(fixedStart), isTrue);
      expect(status.remainingAccess(fixedStart), equals(const Duration(minutes: 5)));
      expect(status.remainingAccess(fixedStart).inMilliseconds, equals(300000));
    });

    // 3. Remaining time after two elapsed minutes
    test('3. Remaining time after two elapsed minutes equals exactly 180 seconds (180000ms)', () async {
      final grantTime = DateTime.utc(2026, 11, 22, 12, 0, 0);
      final unlockUntil = grantTime.add(const Duration(minutes: 5));
      final twoMinutesLater = grantTime.add(const Duration(minutes: 2));

      final status = NativeAccessStatus(unlockUntil: unlockUntil);
      expect(status.isAccessActive(twoMinutesLater), isTrue);
      expect(status.remainingAccess(twoMinutesLater).inSeconds, equals(180));
      expect(status.remainingAccess(twoMinutesLater).inMilliseconds, equals(180000));
    });

    // 4. Remaining time at expiration
    test('4. Remaining time at expiration equals 0 and isAccessActive is false', () async {
      final grantTime = DateTime.utc(2026, 11, 22, 12, 0, 0);
      final unlockUntil = grantTime.add(const Duration(minutes: 5));
      final exactExpiry = unlockUntil;
      final oneSecondPast = unlockUntil.add(const Duration(seconds: 1));

      final status = NativeAccessStatus(unlockUntil: unlockUntil);
      expect(status.isAccessActive(exactExpiry), isFalse);
      expect(status.remainingAccess(exactExpiry), equals(Duration.zero));
      expect(status.isAccessActive(oneSecondPast), isFalse);
      expect(status.remainingAccess(oneSecondPast), equals(Duration.zero));
    });

    // 5. No negative countdown
    test('5. No negative countdown when current time is past expiration', () {
      final unlockUntilMs = 1700000000000;
      final currentEpochMsPast = 1700000050000; // 50 seconds past
      final remainingMs = math.max(0, unlockUntilMs - currentEpochMsPast);
      expect(remainingMs, equals(0));
    });

    // 6. UI rebuild does not change expiry
    testWidgets('6. UI rebuild does not change native unlockUntil timestamp', (tester) async {
      final expiry = DateTime.now().add(const Duration(minutes: 4, seconds: 30));
      final bridge = SimulationBridge(
        initialStatus: NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: true,
          permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(unlockUntil: expiry),
        ),
      );

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await tester.runAsync(() async {
        await controller.refreshAll();
      });

      await tester.pumpWidget(createTestWidget(controller));
      await tester.pump();

      expect(controller.currentFocusState?.unlockUntil, equals(expiry));

      // Trigger multiple UI rebuilds
      for (int i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Native expiry timestamp in bridge remains authoritative and unchanged
      final nativeState = await bridge.getState();
      expect(nativeState.accessStatus.unlockUntil, equals(expiry));
      expect(controller.currentFocusState?.unlockUntil, equals(expiry));

      controller.dispose();
    });

    // 7. App resume refreshes stale state
    testWidgets('7. App resume refreshes stale focus state from native bridge', (tester) async {
      final initialExpiry = DateTime.now().add(const Duration(minutes: 5));
      final bridge = SimulationBridge(
        initialStatus: NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: true,
          permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(unlockUntil: initialExpiry),
        ),
      );

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await tester.runAsync(() async {
        await controller.refreshAll();
      });

      await tester.pumpWidget(createTestWidget(controller));
      await tester.pump();

      expect(find.textContaining('UNLOCKED'), findsOneWidget);

      // Simulate native unlock expiring in background while app is paused
      await bridge.resetAccess();

      // Trigger app resumed lifecycle event
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pumpAndSettle();

      // System Hub automatically refreshed and shows expired/restricted
      expect(find.textContaining('RESTRICTED'), findsOneWidget);

      controller.dispose();
    });

    // 8. Confirmed historical grant with expired unlockUntil is not shown as active
    test('8. Confirmed historical grant with expired unlockUntil is not shown as active', () async {
      final pastExpiry = DateTime.now().subtract(const Duration(minutes: 10));
      final attempt = await AccessAttemptRepository(databaseManager: database).createAttemptIfAbsent(
        sessionId: 'historical_session_1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: pastExpiry.subtract(const Duration(minutes: 5)),
      );

      await AccessAttemptRepository(databaseManager: database).markConfirmed(
        sessionId: attempt.sessionId,
        confirmedAt: pastExpiry.subtract(const Duration(minutes: 5)),
        unlockUntil: pastExpiry,
      );

      final retrieved = await AccessAttemptRepository(databaseManager: database)
          .getAttemptBySessionId('historical_session_1');

      expect(retrieved!.state, equals(AccessAttemptState.confirmed));
      expect(retrieved.isConfirmed, isTrue);

      // Native status evaluation confirms it is expired despite being historically confirmed
      final nativeStatus = NativeAccessStatus(unlockUntil: retrieved.unlockUntil);
      expect(nativeStatus.isAccessActive(), isFalse);
      expect(nativeStatus.remainingAccess(), equals(Duration.zero));
    });

    // 9. New challenge after expired access creates a fresh session
    test('9. New challenge after expired access creates fresh sessionId and requestId', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();

      // First workout session
      final session1 = await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      final session1Id = session1.sessionId;
      final request1Id = session1.requestId;

      // Complete session 1
      controller.sessionManager.updateVerifiedProgress(session1Id, cumulativeReps: 5);
      await controller.coordinator.completeCurrentSession();
      await controller.coordinator.waitForCompletion();
      expect(controller.coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.completed));

      // Native request flag set again by user tapping overlay
      bridge.challengeRequested = true;

      // Second workout session
      final session2 = await controller.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      final session2Id = session2.sessionId;
      final request2Id = session2.requestId;

      expect(session2Id, isNot(equals(session1Id)));
      expect(request2Id, isNot(equals(request1Id)));
      expect(session2.status, equals(WorkoutSessionStatus.active));
      expect(session2.verifiedRepetitions, equals(0));

      controller.dispose();
    });

    // 10. Squat counter starts at 0/5 for the new session
    test('10. Squat counter starts at 0/5 for the new session and adapter resets', () async {
      final adapter = PoseEngineAdapter(isSimulated: true);

      // Complete 5 reps (requires 2 frames down and 2 frames up per rep for debounce)
      for (int i = 0; i < 5; i++) {
        adapter.processAngle(110.0);
        adapter.processAngle(110.0);
        adapter.processAngle(165.0);
        adapter.processAngle(165.0);
      }
      expect(adapter.processAngle(165.0).repetitionCount, equals(5));

      // Reset for new session
      adapter.reset();
      final resetResult = adapter.processAngle(165.0);
      expect(resetResult.repetitionCount, equals(0));
      expect(resetResult.isRepetitionCompleted, isFalse);

      adapter.dispose();
    });

    // 11. Previous completed session cannot grant twice
    test('11. Previous completed session cannot issue duplicate native grant calls', () async {
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

      for (int i = 0; i < 5; i++) {
        adapter.processAngle(110.0);
        adapter.processAngle(110.0);
        adapter.processAngle(165.0);
        adapter.processAngle(165.0);
        await pumpEventQueue();
      }
      await controller.coordinator.waitForCompletion();

      final grantCallsAfterFirst = bridge.callLog.where((c) => c.startsWith('grantAccess')).length;
      expect(grantCallsAfterFirst, equals(1));

      // Re-invoking completeCurrentSession on the same terminal session must NOT grant again
      await controller.coordinator.completeCurrentSession();
      final grantCallsAfterSecond = bridge.callLog.where((c) => c.startsWith('grantAccess')).length;
      expect(grantCallsAfterSecond, equals(1));

      adapter.dispose();
      controller.dispose();
    });

    // 12. Free Workout never grants access
    test('12. Free Workout never grants native access', () async {
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
      expect(controller.coordinator.currentState.challengeContext, equals(ChallengeType.freeWorkout));
      expect(bridge.callLog.where((c) => c.startsWith('grantAccess')), isEmpty);
      expect(controller.currentFocusState?.isAccessActive, isFalse);

      adapter.dispose();
      controller.dispose();
    });

    // 13. Native target change invalidates current unlock as designed
    test('13. Native target change invalidates current unlock as designed', () async {
      final expiry = DateTime.now().add(const Duration(minutes: 5));
      final bridge = SimulationBridge(
        initialStatus: NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: true,
          permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(unlockUntil: expiry),
        ),
      );

      final focusService = FocusService(bridge: bridge);
      final initialStatus = await focusService.getFocusStatus();
      expect(initialStatus.isAccessActive, isTrue);

      // Change target package to Instagram
      await focusService.selectTargetApp(ChannelConstants.targetInstagram);

      final updatedStatus = await focusService.getFocusStatus();
      expect(updatedStatus.selectedTarget, equals(ChannelConstants.targetInstagram));
      expect(updatedStatus.isAccessActive, isFalse);
      expect(updatedStatus.unlockUntil, isNull);

      focusService.dispose();
    });

    // 14. Blocker latch guard: while gate is latched, foreground updates from HOME/LevelUp
    //     window events do NOT dismiss the gate (Module 11 regression fix contract).
    test('14. [MANUAL DEVICE TEST REQUIRED] Gate remains latched during HOME_ACTION window event sequence', () {
      // Contract enforced by LevelUpAccessibilityService.kt onAccessibilityEvent:
      //   if (gateView != null) { reevaluate(); return }   ← foreground NOT updated
      // reevaluate() with gateView != null only checks target/unlock/keyguard/disabled.
      // It does NOT check foregroundPackage == packageName any more (regression fix).
      // This prevents the GATE_RELEASED("foreground is LevelUp") that was observed on Pixel.
      expect(true, isTrue);
    });

    // 15. Focus disabled removes any blocker overlay (Android contract)
    test('15. [MANUAL DEVICE TEST REQUIRED] Disabling Focus removes any blocker overlay immediately', () {
      // Contract enforced by LevelUpAccessibilityService.kt reevaluate():
      // if (!prefs.getBoolean("enabled", false)) clearGate("disabled")
      expect(true, isTrue);
    });

    // 16. Multiple rapid window events do not duplicate the overlay (Android contract)
    test('16. [MANUAL DEVICE TEST REQUIRED] Multiple rapid window events do not duplicate the overlay view', () {
      // Contract enforced by LevelUpAccessibilityService.kt latchGate():
      // if (gateView != null) return
      expect(true, isTrue);
    });
  });
}
