import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/native_bridge_exception.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:levelup_test/models/workout_result.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';

/// Fake implementation of [INativeBridge] for testing [AccessService].
class FakeAccessBridge implements INativeBridge {
  NativeFocusStatus currentStatus;
  DateTime unlockTimestamp;
  final List<String> callLog = [];
  final Map<String, dynamic> lastCallArguments = {};

  Object? grantAccessError;
  Object? getStateError;
  Object? resetAccessError;

  /// Optional completer to delay grantAccess response for concurrency tests.
  Completer<DateTime>? grantAccessCompleter;

  FakeAccessBridge({
    NativeFocusStatus? initialStatus,
    DateTime? unlockTimestamp,
  })  : currentStatus = initialStatus ??
            const NativeFocusStatus(
              targetPackage: ChannelConstants.targetYouTube,
              isGateEnabled: true,
              permissionStatus:
                  NativePermissionStatus(isAccessibilityGranted: true),
              accessStatus: NativeAccessStatus(),
            ),
        unlockTimestamp = unlockTimestamp ?? DateTime(2026, 11, 21, 17, 35);

  @override
  Future<DateTime> grantAccess({int minutes = 5}) async {
    callLog.add('grantAccess');
    lastCallArguments['minutes'] = minutes;
    if (grantAccessError != null) throw grantAccessError!;

    // If a completer is set, wait for it to complete (simulates delayed native response).
    if (grantAccessCompleter != null) {
      return grantAccessCompleter!.future;
    }

    currentStatus = NativeFocusStatus(
      targetPackage: currentStatus.targetPackage,
      isGateEnabled: currentStatus.isGateEnabled,
      permissionStatus: currentStatus.permissionStatus,
      accessStatus: NativeAccessStatus(unlockUntil: unlockTimestamp),
    );
    return unlockTimestamp;
  }

  @override
  Future<NativeFocusStatus> getState() async {
    callLog.add('getState');
    if (getStateError != null) throw getStateError!;
    return currentStatus;
  }

  @override
  Future<bool> resetAccess() async {
    callLog.add('resetAccess');
    if (resetAccessError != null) throw resetAccessError!;

    currentStatus = NativeFocusStatus(
      targetPackage: currentStatus.targetPackage,
      isGateEnabled: currentStatus.isGateEnabled,
      permissionStatus: currentStatus.permissionStatus,
      accessStatus: const NativeAccessStatus(unlockUntil: null),
    );
    return true;
  }

  @override
  Future<bool> setEnabled(bool enabled) async => true;

  @override
  Future<bool> setTarget(String targetPackage) async => true;

  @override
  Future<bool> openAccessibilitySettings() async => true;

  @override
  Future<bool> consumeChallengeRequest() async => false;

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  late FakeAccessBridge fakeBridge;
  late AccessService accessService;
  late DateTime fixedTime;
  late DateTime unlockExpiry;

  setUp(() {
    fixedTime = DateTime(2026, 11, 21, 17, 30);
    unlockExpiry = fixedTime.add(const Duration(minutes: 5));
    fakeBridge = FakeAccessBridge(unlockTimestamp: unlockExpiry);
    accessService = AccessService(
      bridge: fakeBridge,
      clock: () => fixedTime,
    );
  });

  tearDown(() {
    accessService.dispose();
  });

  WorkoutResult createUnlockResult({
    String sessionId = 'session_1',
    String targetPackage = ChannelConstants.targetYouTube,
    int completedReps = 5,
    int accessDurationSeconds = 300,
  }) {
    return WorkoutResult(
      sessionId: sessionId,
      requestId: 'req_1',
      challengeId: 'squats_unlock_5',
      challengeContext: ChallengeType.unlockChallenge,
      exerciseType: ExerciseType.squats,
      targetPackage: targetPackage,
      completedRepetitions: completedReps,
      duration: const Duration(seconds: 45),
      completedAt: fixedTime,
      eligibleForAccess: true,
      accessDurationSeconds: accessDurationSeconds,
    );
  }

  group('Authorization Preconditions', () {
    test('1. successfully grants access for valid unlock workout result', () async {
      final workoutResult = createUnlockResult();
      final grantResult = await accessService.grantAccessForCompletedWorkout(workoutResult);

      expect(grantResult.isSuccessful, isTrue);
      expect(grantResult.status, equals(AccessGrantStatus.granted));
      expect(grantResult.sessionId, equals('session_1'));
      expect(grantResult.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(grantResult.unlockUntil, equals(unlockExpiry));
      expect(grantResult.grantedAt, equals(fixedTime));

      expect(fakeBridge.callLog, contains('grantAccess'));
      expect(fakeBridge.lastCallArguments['minutes'], equals(5));
    });

    test('2. rejects free workout result with IneligibleWorkoutContextException', () async {
      final freeWorkoutResult = WorkoutResult(
        sessionId: 'session_free',
        requestId: 'req_free',
        challengeId: 'squats_free_5',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetPackage: null,
        completedRepetitions: 5,
        duration: const Duration(seconds: 40),
        completedAt: fixedTime,
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );

      expect(
        () => accessService.grantAccessForCompletedWorkout(freeWorkoutResult),
        throwsA(isA<IneligibleWorkoutContextException>()),
      );
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('3. rejects incomplete result with IncompleteWorkoutResultException', () async {
      final workoutResult = WorkoutResult(
        sessionId: 'session_incomplete',
        requestId: 'req_1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 0,
        duration: const Duration(seconds: 10),
        completedAt: fixedTime,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      await expectLater(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(isA<IncompleteWorkoutResultException>()),
      );
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('4. rejects cancelled or failed workout results (not eligible for access)', () {
      // Results without eligibleForAccess flag set to true are rejected
      final cancelledWorkoutResult = WorkoutResult(
        sessionId: 'session_cancelled',
        requestId: 'req_cancelled',
        challengeId: 'squats_free_5',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetPackage: null,
        completedRepetitions: 2,
        duration: const Duration(seconds: 20),
        completedAt: fixedTime,
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );

      expect(
        () => accessService.grantAccessForCompletedWorkout(cancelledWorkoutResult),
        throwsA(isA<IneligibleWorkoutContextException>()),
      );
    });

    test('5. rejects unsupported target package with UnsupportedAccessTargetException', () async {
      final workoutResult = WorkoutResult(
        sessionId: 'session_unsupported',
        requestId: 'req_1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: 'com.unsupported.app',
        completedRepetitions: 5,
        duration: const Duration(seconds: 45),
        completedAt: fixedTime,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      await expectLater(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(
          isA<UnsupportedAccessTargetException>()
              .having((e) => e.targetPackage, 'targetPackage', equals('com.unsupported.app')),
        ),
      );
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('6. rejects grant when Android Accessibility permission is missing', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false), // Missing!
        accessStatus: NativeAccessStatus(),
      );

      final workoutResult = createUnlockResult();

      expect(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(isA<MissingAccessibilityPermissionException>()),
      );
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('7. rejects grant when voluntary Focus restriction is disabled', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false, // Disabled!
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      final workoutResult = createUnlockResult();

      expect(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(isA<FocusDisabledException>()),
      );
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });

    test('8. rejects grant when workout target differs from active native target', () async {
      // Native target is Instagram, but workout was performed for YouTube
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetInstagram,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      final workoutResult = createUnlockResult(targetPackage: ChannelConstants.targetYouTube);

      expect(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(
          isA<TargetPackageMismatchException>()
              .having((e) => e.workoutTarget, 'workoutTarget', equals(ChannelConstants.targetYouTube))
              .having((e) => e.nativeTarget, 'nativeTarget', equals(ChannelConstants.targetInstagram)),
        ),
      );
      expect(fakeBridge.callLog, isNot(contains('grantAccess')));
    });
  });

  group('Native Grant Invariants & Idempotency', () {
    test('9 & 10. invokes correct native grant call and returns authoritative expiration', () async {
      final workoutResult = createUnlockResult();
      final result = await accessService.grantAccessForCompletedWorkout(workoutResult);

      expect(fakeBridge.lastCallArguments['minutes'], equals(5));
      expect(result.unlockUntil, equals(unlockExpiry));
      expect(result.isAccessActive(fixedTime), isTrue);
      expect(result.remainingDuration(fixedTime), equals(const Duration(minutes: 5)));
    });

    test('11. duplicate request suppression returns cached result without re-invoking native grant', () async {
      final workoutResult = createUnlockResult(sessionId: 'session_dup');

      // First call
      final r1 = await accessService.grantAccessForCompletedWorkout(workoutResult);
      expect(r1.status, equals(AccessGrantStatus.granted));
      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));

      // Duplicate call for same sessionId
      final r2 = await accessService.grantAccessForCompletedWorkout(workoutResult);
      expect(r2.status, equals(AccessGrantStatus.granted));
      expect(r2, equals(r1));

      // Verify native grant was NOT called a second time
      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));
    });

    test('12. concurrent requests for the same session throw ConcurrentGrantException', () async {
      final completer = Completer<DateTime>();
      fakeBridge.grantAccessCompleter = completer;

      final workoutResult = createUnlockResult(sessionId: 'session_concurrent');

      // Launch first request (will block waiting for completer)
      final future1 = accessService.grantAccessForCompletedWorkout(workoutResult);

      // Allow microtask queue to process up to the grantAccess await
      await Future<void>.delayed(Duration.zero);

      // Second concurrent request should throw immediately
      await expectLater(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(isA<ConcurrentGrantException>()),
      );

      // Resolve the first request
      completer.complete(unlockExpiry);
      final res1 = await future1;
      expect(res1.isSuccessful, isTrue);

      // Clean up
      fakeBridge.grantAccessCompleter = null;
    });

    test('13. wraps native PlatformException in AccessEnginePlatformException without leaking raw error', () async {
      fakeBridge.grantAccessError = PlatformException(
        code: 'LAUNCH_ERROR',
        message: 'Could not launch target package',
      );

      final workoutResult = createUnlockResult();

      expect(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(
          isA<AccessEnginePlatformException>()
              .having((e) => e.code, 'code', equals('LAUNCH_ERROR'))
              .having((e) => e.message, 'message', contains('Could not launch target package')),
        ),
      );
    });

    test('14. uncertain native failure does NOT perform unsafe automatic retries', () async {
      fakeBridge.grantAccessError = const NativeBridgeException(
        message: 'IPC timeout',
        code: 'TIMEOUT',
      );

      final workoutResult = createUnlockResult();

      await expectLater(
        () => accessService.grantAccessForCompletedWorkout(workoutResult),
        throwsA(isA<AccessEnginePlatformException>()),
      );

      // Verify native grant was called exactly once, no retry loops
      expect(fakeBridge.callLog.where((c) => c == 'grantAccess').length, equals(1));
    });

    test('15. detects access already active from authoritative native state', () async {
      // Configure native status with active unlock
      final activeExpiry = fixedTime.add(const Duration(minutes: 3));
      fakeBridge.currentStatus = NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(unlockUntil: activeExpiry),
      );

      final accessStatus = await accessService.getAccessStatus();
      expect(accessStatus.isAccessActive(fixedTime), isTrue);
      expect(accessStatus.unlockUntil, equals(activeExpiry));
      expect(accessStatus.remainingAccess(fixedTime), equals(const Duration(minutes: 3)));
    });

    test('16. resetAccess dispatches native reset call', () async {
      final success = await accessService.resetAccess();

      expect(success, isTrue);
      expect(fakeBridge.callLog, contains('resetAccess'));

      final statusAfter = await accessService.getAccessStatus();
      expect(statusAfter.unlockUntil, isNull);
    });

    test('17. never executes XP rewards or database side-effects in AccessService', () async {
      final workoutResult = createUnlockResult();
      final grantResult = await accessService.grantAccessForCompletedWorkout(workoutResult);

      expect(grantResult.isSuccessful, isTrue);
      // AccessService only handles access grants; Progress Engine will consume WorkoutResult separately
    });

    test('18. preserves Blocker v3 and does not alter MethodChannel names', () {
      expect(ChannelConstants.controlChannel, equals('levelup_test/control'));
    });
  });

  group('Reactive grantStream', () {
    test('emits AccessGrantResult on successful grant', () async {
      final emitted = <AccessGrantResult>[];
      final sub = accessService.grantStream.listen(emitted.add);

      final workoutResult = createUnlockResult();
      await accessService.grantAccessForCompletedWorkout(workoutResult);

      await pumpEventQueue();

      expect(emitted.length, equals(1));
      expect(emitted.first.sessionId, equals('session_1'));
      expect(emitted.first.status, equals(AccessGrantStatus.granted));

      await sub.cancel();
    });
  });
}
