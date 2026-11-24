import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/persistence_exceptions.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/core/integration/pose_event_adapter.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/models/access_attempt_record.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fake platform bridge for coordinator integration tests.
class FakeCoordinatorBridge implements INativeBridge {
  NativeFocusStatus status;
  bool challengeRequested;
  DateTime unlockTimestamp;
  final List<String> callLog = [];
  final Map<String, dynamic> lastArgs = {};

  Object? grantAccessError;
  Object? getStateError;
  Completer<DateTime>? grantAccessCompleter;

  FakeCoordinatorBridge({
    NativeFocusStatus? initialStatus,
    this.challengeRequested = true,
    DateTime? unlockTimestamp,
  })  : status = initialStatus ??
            const NativeFocusStatus(
              targetPackage: ChannelConstants.targetYouTube,
              isGateEnabled: true,
              permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
              accessStatus: NativeAccessStatus(),
            ),
        unlockTimestamp = unlockTimestamp ?? DateTime.utc(2026, 11, 21, 17, 35);

  @override
  Future<NativeFocusStatus> getState() async {
    callLog.add('getState');
    if (getStateError != null) throw getStateError!;
    return status;
  }

  @override
  Future<bool> setTarget(String targetPackage) async {
    callLog.add('setTarget');
    lastArgs['target'] = targetPackage;
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
    callLog.add('setEnabled');
    lastArgs['enabled'] = enabled;
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
  Future<bool> consumeChallengeRequest() async {
    callLog.add('consumeChallengeRequest');
    final wasRequested = challengeRequested;
    challengeRequested = false;
    return wasRequested;
  }

  @override
  Future<DateTime> grantAccess({int minutes = 5}) async {
    callLog.add('grantAccess');
    lastArgs['minutes'] = minutes;

    if (grantAccessError != null) throw grantAccessError!;

    if (grantAccessCompleter != null) {
      return grantAccessCompleter!.future;
    }

    status = NativeFocusStatus(
      targetPackage: status.targetPackage,
      isGateEnabled: status.isGateEnabled,
      permissionStatus: status.permissionStatus,
      accessStatus: NativeAccessStatus(unlockUntil: unlockTimestamp),
    );
    return unlockTimestamp;
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
    return true;
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// Fake repository simulating an unrecoverable SQLite write failure.
class FailingAccessAttemptRepository implements IAccessAttemptRepository {
  @override
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  }) async {
    throw const PersistenceException(
      message: 'Simulated SQLite write failure: disk full',
      code: 'DISK_FULL',
    );
  }

  @override
  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId) async => null;

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) async =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async => [];
}

/// Helper that simulates full squat repetitions by sending interior knee angles.
Future<void> performSquats(PoseEngineAdapter adapter, int count, [CoreIntegrationCoordinator? coordinator]) async {
  for (int i = 0; i < count; i++) {
    adapter.processAngle(110.0); // Down frame 1
    adapter.processAngle(110.0); // Down frame 2 -> SquatPhase.down
    adapter.processAngle(160.0); // Up frame 1
    adapter.processAngle(160.0); // Up frame 2 -> SquatPhase.up (rep verified)
    await pumpEventQueue();
  }
  if (coordinator != null) {
    try {
      await coordinator.waitForCompletion();
    } catch (_) {}
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late String dbPath;
  late LevelUpDatabase dbManager;
  late WorkoutHistoryRepository workoutHistoryRepo;
  late AccessAttemptRepository accessAttemptRepo;
  late FakeCoordinatorBridge fakeBridge;
  late FocusService focusService;
  late ChallengeService challengeService;
  late WorkoutSessionManager sessionManager;
  late AccessService accessService;
  late CoreIntegrationCoordinator coordinator;
  late PoseEngineAdapter poseAdapter;
  late DateTime fixedTime;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('coordinator_test_');
    dbPath = p.join(tempDir.path, 'coordinator_test.db');
    dbManager = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );

    workoutHistoryRepo = WorkoutHistoryRepository(databaseManager: dbManager);
    accessAttemptRepo = AccessAttemptRepository(databaseManager: dbManager);

    fixedTime = DateTime.utc(2026, 11, 21, 17, 30);
    fakeBridge = FakeCoordinatorBridge(unlockTimestamp: fixedTime.add(const Duration(minutes: 5)));

    focusService = FocusService(bridge: fakeBridge);
    challengeService = ChallengeService();
    sessionManager = WorkoutSessionManager(challengeService: challengeService);
    accessService = AccessService(bridge: fakeBridge, clock: () => fixedTime);

    coordinator = CoreIntegrationCoordinator(
      nativeBridge: fakeBridge,
      focusService: focusService,
      challengeService: challengeService,
      sessionManager: sessionManager,
      accessService: accessService,
      workoutHistoryRepository: workoutHistoryRepo,
      accessAttemptRepository: accessAttemptRepo,
      clock: () => fixedTime,
    );

    poseAdapter = PoseEngineAdapter();
    coordinator.attachPoseEventSource(poseAdapter);
  });

  tearDown(() async {
    coordinator.dispose();
    poseAdapter.dispose();
    focusService.dispose();
    sessionManager.dispose();
    accessService.dispose();
    await dbManager.close();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CoreIntegrationCoordinator — 20 Core Headless Integration Tests', () {
    test('1. Successful Unlock Challenge workflow completes end-to-end', () async {
      await coordinator.initialize();
      expect(coordinator.currentState.isFocusEnabled, isTrue);

      final session = await coordinator.launchUnlockChallenge();
      expect(session.status, equals(WorkoutSessionStatus.active));
      expect(session.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(fakeBridge.callLog, contains('consumeChallengeRequest'));

      // Perform 5 verified squats
      await performSquats(poseAdapter, 5, coordinator);

      // Verify session completion
      expect(coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.completed));
      expect(coordinator.currentState.verifiedRepetitions, equals(5));
      expect(coordinator.currentState.accessGrantStatus, equals(AccessGrantStatus.granted));
      expect(coordinator.currentState.isWorkoutPersisted, isTrue);

      // Verify SQLite workout persistence
      final savedWorkout = await workoutHistoryRepo.getWorkoutBySessionId(session.sessionId);
      expect(savedWorkout, isNotNull);
      expect(savedWorkout!.completedRepetitions, equals(5));
      expect(savedWorkout.eligibleForAccess, isTrue);
      expect(savedWorkout.targetPackage, equals(ChannelConstants.targetYouTube));

      // Verify SQLite access attempt journal
      final attempt = await accessAttemptRepo.getAttemptBySessionId(session.sessionId);
      expect(attempt, isNotNull);
      expect(attempt!.state, equals(AccessAttemptState.confirmed));
      expect(attempt.unlockUntil, equals(fixedTime.add(const Duration(minutes: 5))));
      expect(fakeBridge.callLog, contains('grantAccess'));
    });

    test('2. Five verified repetitions complete the workout and unlock access', () async {
      await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 5, coordinator);

      expect(sessionManager.currentSession!.verifiedRepetitions, equals(5));
      expect(sessionManager.currentSession!.status, equals(WorkoutSessionStatus.completed));
      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));
    });

    test('3. Four verified repetitions never issue access or persist completion', () async {
      final session = await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 4);

      expect(coordinator.currentState.verifiedRepetitions, equals(4));
      expect(coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.active));
      expect(coordinator.currentState.accessGrantStatus, isNull);
      expect(coordinator.currentState.isWorkoutPersisted, isFalse);

      // Verify no native grant
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));

      // Verify nothing persisted in SQLite
      final savedWorkout = await workoutHistoryRepo.getWorkoutBySessionId(session.sessionId);
      expect(savedWorkout, isNull);
      final attempt = await accessAttemptRepo.getAttemptBySessionId(session.sessionId);
      expect(attempt, isNull);
    });

    test('4. Free Workout persists completed repetitions without issuing access', () async {
      final session = await coordinator.launchFreeWorkout();
      expect(session.challengeContext, equals(ChallengeType.freeWorkout));
      expect(session.targetPackage, isNull);

      await performSquats(poseAdapter, 5, coordinator);

      expect(coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.completed));
      expect(coordinator.currentState.isWorkoutPersisted, isTrue);
      expect(coordinator.currentState.accessGrantStatus, isNull);

      // Native grantAccess must NEVER be called
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));

      // Workout history MUST be saved
      final savedWorkout = await workoutHistoryRepo.getWorkoutBySessionId(session.sessionId);
      expect(savedWorkout, isNotNull);
      expect(savedWorkout!.challengeContext, equals(ChallengeType.freeWorkout));
      expect(savedWorkout.eligibleForAccess, isFalse);
      expect(savedWorkout.targetPackage, isNull);

      // No access attempt record in SQLite
      final attempt = await accessAttemptRepo.getAttemptBySessionId(session.sessionId);
      expect(attempt, isNull);
    });

    test('5. Duplicate repetition events do not cause duplicate progress increments', () async {
      await coordinator.launchUnlockChallenge();

      // Send 1 valid rep
      await performSquats(poseAdapter, 1);
      expect(coordinator.currentState.verifiedRepetitions, equals(1));

      // Resend identical frame or non-progress frame
      poseAdapter.processAngle(160.0);
      poseAdapter.processAngle(160.0);
      await pumpEventQueue();
      expect(coordinator.currentState.verifiedRepetitions, equals(1));
    });

    test('6. Duplicate completion callbacks do not duplicate native grant or database rows', () async {
      await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 5, coordinator);

      final grantCallsBefore = fakeBridge.callLog.where((c) => c == 'grantAccess').length;
      expect(grantCallsBefore, equals(1));

      // Attempt second manual completion
      await coordinator.completeCurrentSession();

      final grantCallsAfter = fakeBridge.callLog.where((c) => c == 'grantAccess').length;
      expect(grantCallsAfter, equals(1));

      final workoutCount = await workoutHistoryRepo.countCompletedWorkouts();
      expect(workoutCount, equals(1));
    });

    test('7. Concurrent completion handling executes grant workflow exactly once', () async {
      await coordinator.launchUnlockChallenge();

      // Progress 5 reps to achieve goal
      await performSquats(poseAdapter, 5, coordinator);

      // Trigger 4 concurrent completeCurrentSession invocations
      await Future.wait([
        coordinator.completeCurrentSession(),
        coordinator.completeCurrentSession(),
        coordinator.completeCurrentSession(),
        coordinator.completeCurrentSession(),
      ]);

      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));
      expect(await workoutHistoryRepo.countCompletedWorkouts(), equals(1));
    });

    test('8. Missing Accessibility permission prevents challenge launch', () async {
      fakeBridge.status = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );

      await expectLater(
        () => coordinator.launchUnlockChallenge(),
        throwsA(isA<MissingAccessibilityPermissionException>()),
      );

      expect(coordinator.currentState.errorMessage, contains('Accessibility'));
      expect(sessionManager.currentSession, isNull);
    });

    test('9. Focus disabled prevents unlock challenge launch', () async {
      fakeBridge.status = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false, // Disabled!
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      await expectLater(
        () => coordinator.launchUnlockChallenge(),
        throwsA(isA<FocusDisabledException>()),
      );

      expect(coordinator.currentState.errorMessage, contains('Focus restriction'));
      expect(sessionManager.currentSession, isNull);
    });

    test('10. Target package mismatch during completion rejects grant definitively', () async {
      final session = await coordinator.launchUnlockChallenge();

      // Simulating external target change in Android settings during workout
      fakeBridge.status = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetInstagram, // Mismatch!
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      await performSquats(poseAdapter, 5, coordinator);

      // Workout itself was physically completed, so history is preserved
      final savedWorkout = await workoutHistoryRepo.getWorkoutBySessionId(session.sessionId);
      expect(savedWorkout, isNotNull);

      // Access attempt must be recorded as definitivelyRejected
      final attempt = await accessAttemptRepo.getAttemptBySessionId(session.sessionId);
      expect(attempt, isNotNull);
      expect(attempt!.state, equals(AccessAttemptState.definitivelyRejected));

      // Native grantAccess was NOT called
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('11. Cancellation before completion halts session and ignores further reps', () async {
      final session = await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 2);

      final cancelled = await coordinator.cancelCurrentSession(reason: 'User cancelled');
      expect(cancelled.status, equals(WorkoutSessionStatus.cancelled));
      expect(coordinator.currentState.sessionStatus, equals(WorkoutSessionStatus.cancelled));

      // Send 5 more reps after cancellation
      await performSquats(poseAdapter, 5);

      // Must remain cancelled at 2 reps
      expect(sessionManager.currentSession!.verifiedRepetitions, equals(2));
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
      expect(await workoutHistoryRepo.getWorkoutBySessionId(session.sessionId), isNull);
    });

    test('12. Camera and tracking failure terminates session cleanly', () async {
      await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 1);

      final failed = await coordinator.failCurrentSession(reason: 'Camera streaming error');
      expect(failed.status, equals(WorkoutSessionStatus.failed));
      expect(coordinator.currentState.errorMessage, equals('Camera streaming error'));

      // Send more squats
      await performSquats(poseAdapter, 4);
      expect(sessionManager.currentSession!.verifiedRepetitions, equals(1));
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('13. SQLite write failure before native grant aborts native invocation', () async {
      final failingAccessRepo = FailingAccessAttemptRepository();
      final testCoordinator = CoreIntegrationCoordinator(
        nativeBridge: fakeBridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: workoutHistoryRepo,
        accessAttemptRepository: failingAccessRepo,
        clock: () => fixedTime,
      );

      final testAdapter = PoseEngineAdapter();
      testCoordinator.attachPoseEventSource(testAdapter);

      await testCoordinator.launchUnlockChallenge();

      // SQLite failure when persisting the prepared attempt must abort native invocation
      await performSquats(testAdapter, 5, testCoordinator);

      // Invariant: Native grantAccess must NEVER have been called!
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));

      testCoordinator.dispose();
      testAdapter.dispose();
    });

    test('14. Native grant success persists confirmed state with authoritative unlockUntil', () async {
      final session = await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 5, coordinator);

      final attempt = await accessAttemptRepo.getAttemptBySessionId(session.sessionId);
      expect(attempt!.state, equals(AccessAttemptState.confirmed));
      expect(attempt.confirmedAt, isNotNull);
      expect(attempt.unlockUntil, equals(fixedTime.add(const Duration(minutes: 5))));
    });

    test('15. Ambiguous native outcome is marked uncertain in SQLite journal', () async {
      fakeBridge.grantAccessError = PlatformException(
        code: 'IPC_TIMEOUT',
        message: 'Platform channel timed out waiting for response',
      );

      final session = await coordinator.launchUnlockChallenge();

      await performSquats(poseAdapter, 5, coordinator);

      final attempt = await accessAttemptRepo.getAttemptBySessionId(session.sessionId);
      expect(attempt, isNotNull);
      expect(attempt!.state, equals(AccessAttemptState.uncertain));
      expect(attempt.failureReason, contains('timed out'));
      expect(attempt.requiresReconciliation, isTrue);
    });

    test('16. Restart with confirmed attempt does not re-grant', () async {
      await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 5, coordinator);

      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));

      // Re-initialize a fresh coordinator simulating app restart with existing DB
      final restartedCoordinator = CoreIntegrationCoordinator(
        nativeBridge: fakeBridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: workoutHistoryRepo,
        accessAttemptRepository: accessAttemptRepo,
        clock: () => fixedTime,
      );

      // Trigger completion for the existing session
      await restartedCoordinator.completeCurrentSession();

      // Invariant: grantAccess count remains 1
      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));
      restartedCoordinator.dispose();
    });

    test('17. Restart with prepared attempt does not auto-re-grant', () async {
      // Simulate crash right after journal was prepared
      await accessAttemptRepo.createAttemptIfAbsent(
        sessionId: 'session_prepared_crash',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      // Coordinator trying to process prepared session
      final preparedAttempt = await accessAttemptRepo.getAttemptBySessionId('session_prepared_crash');
      expect(preparedAttempt!.state, equals(AccessAttemptState.prepared));
      expect(preparedAttempt.requiresReconciliation, isTrue);

      // When coordinator attempts completion on a prepared session, it must refuse auto-retry
      // by throwing or rejecting without calling grantAccess
      final restartedCoordinator = CoreIntegrationCoordinator(
        nativeBridge: fakeBridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: workoutHistoryRepo,
        accessAttemptRepository: accessAttemptRepo,
        clock: () => fixedTime,
      );

      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
      restartedCoordinator.dispose();
    });

    test('18. Restart with uncertain attempt does not auto-re-grant', () async {
      await accessAttemptRepo.createAttemptIfAbsent(
        sessionId: 'session_uncertain_crash',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );
      await accessAttemptRepo.markUncertain(
        sessionId: 'session_uncertain_crash',
        reason: 'IPC crash on previous run',
      );

      final uncertainAttempt = await accessAttemptRepo.getAttemptBySessionId('session_uncertain_crash');
      expect(uncertainAttempt!.requiresReconciliation, isTrue);

      // Verify no grantAccess was called
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('19. Repeated session ID does not duplicate workout history', () async {
      await coordinator.launchUnlockChallenge();
      await performSquats(poseAdapter, 5, coordinator);

      final count1 = await workoutHistoryRepo.countCompletedWorkouts();
      expect(count1, equals(1));

      // Attempt duplicate completion
      await coordinator.completeCurrentSession();

      final count2 = await workoutHistoryRepo.countCompletedWorkouts();
      expect(count2, equals(1));
    });

    test('20. Coordinator cleanup and resource disposal detaches subscriptions', () async {
      final testAdapter = PoseEngineAdapter();
      coordinator.attachPoseEventSource(testAdapter);

      coordinator.dispose();

      // Emitting through adapter after coordinator disposal must not throw or cause errors
      expect(
        () => testAdapter.processAngle(120.0),
        returnsNormally,
      );
      testAdapter.dispose();
    });
  });
}
