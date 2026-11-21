import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/access_exceptions.dart';
import 'package:levelup_test/models/access_grant_request.dart';
import 'package:levelup_test/models/access_grant_result.dart';
import 'package:levelup_test/models/access_grant_status.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/workout_result.dart';

void main() {
  group('AccessGrantStatus', () {
    test('isSuccessful is true only for granted and alreadyActive', () {
      expect(AccessGrantStatus.granted.isSuccessful, isTrue);
      expect(AccessGrantStatus.alreadyActive.isSuccessful, isTrue);

      expect(AccessGrantStatus.rejected.isSuccessful, isFalse);
      expect(AccessGrantStatus.failed.isSuccessful, isFalse);
    });
  });

  group('AccessGrantRequest', () {
    test('constructs valid request from unlock workout result', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final workoutResult = WorkoutResult(
        sessionId: 'session_100',
        requestId: 'req_100',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 40),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      final grantRequest = AccessGrantRequest.fromWorkoutResult(workoutResult);

      expect(grantRequest.sessionId, equals('session_100'));
      expect(grantRequest.challengeId, equals('squats_unlock_5'));
      expect(grantRequest.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(grantRequest.durationMinutes, equals(5));
      expect(grantRequest.challengeContext, equals(ChallengeType.unlockChallenge));
      expect(grantRequest.completedAt, equals(now));
    });

    test('rejects free workout result with IneligibleWorkoutContextException', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final freeWorkoutResult = WorkoutResult(
        sessionId: 'session_200',
        requestId: 'req_200',
        challengeId: 'squats_free_5',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetPackage: null,
        completedRepetitions: 5,
        duration: const Duration(seconds: 35),
        completedAt: now,
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );

      expect(
        () => AccessGrantRequest.fromWorkoutResult(freeWorkoutResult),
        throwsA(isA<IneligibleWorkoutContextException>()),
      );
    });

    test('rejects 0 of 5 repetitions with IncompleteWorkoutResultException', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final workoutResult = WorkoutResult(
        sessionId: 's0',
        requestId: 'r0',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 0,
        duration: const Duration(seconds: 10),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      expect(
        () => AccessGrantRequest.fromWorkoutResult(workoutResult),
        throwsA(
          isA<IncompleteWorkoutResultException>()
              .having((e) => e.completedReps, 'completedReps', equals(0))
              .having((e) => e.targetReps, 'targetReps', equals(5)),
        ),
      );
    });

    test('rejects 1 of 5 repetitions with IncompleteWorkoutResultException', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final workoutResult = WorkoutResult(
        sessionId: 's1',
        requestId: 'r1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 1,
        duration: const Duration(seconds: 15),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      expect(
        () => AccessGrantRequest.fromWorkoutResult(workoutResult),
        throwsA(
          isA<IncompleteWorkoutResultException>()
              .having((e) => e.completedReps, 'completedReps', equals(1))
              .having((e) => e.targetReps, 'targetReps', equals(5)),
        ),
      );
    });

    test('rejects 4 of 5 repetitions with IncompleteWorkoutResultException', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final workoutResult = WorkoutResult(
        sessionId: 's4',
        requestId: 'r4',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 4,
        duration: const Duration(seconds: 35),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      expect(
        () => AccessGrantRequest.fromWorkoutResult(workoutResult),
        throwsA(
          isA<IncompleteWorkoutResultException>()
              .having((e) => e.completedReps, 'completedReps', equals(4))
              .having((e) => e.targetReps, 'targetReps', equals(5)),
        ),
      );
    });

    test('rejects unknown challengeId with IneligibleWorkoutContextException', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final workoutResult = WorkoutResult(
        sessionId: 's_unknown',
        requestId: 'r_unknown',
        challengeId: 'unknown_challenge_999',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 45),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      expect(
        () => AccessGrantRequest.fromWorkoutResult(workoutResult),
        throwsA(
          isA<IneligibleWorkoutContextException>()
              .having((e) => e.message, 'message', contains('Unknown challenge ID')),
        ),
      );
    });

    test('rejects mismatched challenge definition (0 access duration definition) with IneligibleWorkoutContextException', () {
      final now = DateTime(2026, 11, 21, 17, 30);
      final workoutResult = WorkoutResult(
        sessionId: 's_mismatch',
        requestId: 'r_mismatch',
        challengeId: 'squats_free_5', // Free workout definition does not grant access!
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 45),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      expect(
        () => AccessGrantRequest.fromWorkoutResult(workoutResult),
        throwsA(
          isA<IneligibleWorkoutContextException>()
              .having((e) => e.message, 'message', contains('does not grant access')),
        ),
      );
    });

    test('enforces runtime invariants on direct constructor', () {
      final now = DateTime(2026, 11, 21);

      // freeWorkout context rejected
      expect(
        () => AccessGrantRequest(
          sessionId: 's1',
          challengeId: 'c1',
          targetPackage: ChannelConstants.targetYouTube,
          durationMinutes: 5,
          challengeContext: ChallengeType.freeWorkout,
          completedAt: now,
        ),
        throwsA(isA<IneligibleWorkoutContextException>()),
      );

      // unsupported target package rejected
      expect(
        () => AccessGrantRequest(
          sessionId: 's1',
          challengeId: 'c1',
          targetPackage: 'com.malicious.app',
          durationMinutes: 5,
          challengeContext: ChallengeType.unlockChallenge,
          completedAt: now,
        ),
        throwsA(isA<UnsupportedAccessTargetException>()),
      );

      // duration < 1 rejected
      expect(
        () => AccessGrantRequest(
          sessionId: 's1',
          challengeId: 'c1',
          targetPackage: ChannelConstants.targetYouTube,
          durationMinutes: 0,
          challengeContext: ChallengeType.unlockChallenge,
          completedAt: now,
        ),
        throwsA(isA<InvalidAccessDurationException>()),
      );

      // duration > 15 rejected
      expect(
        () => AccessGrantRequest(
          sessionId: 's1',
          challengeId: 'c1',
          targetPackage: ChannelConstants.targetYouTube,
          durationMinutes: 16,
          challengeContext: ChallengeType.unlockChallenge,
          completedAt: now,
        ),
        throwsA(isA<InvalidAccessDurationException>()),
      );

      // empty sessionId rejected
      expect(
        () => AccessGrantRequest(
          sessionId: '   ',
          challengeId: 'c1',
          targetPackage: ChannelConstants.targetYouTube,
          durationMinutes: 5,
          challengeContext: ChallengeType.unlockChallenge,
          completedAt: now,
        ),
        throwsA(isA<AccessEngineException>()),
      );
    });

    test('implements equality and toMap', () {
      final now = DateTime(2026, 11, 21);
      final a = AccessGrantRequest(
        sessionId: 's1',
        challengeId: 'c1',
        targetPackage: ChannelConstants.targetYouTube,
        durationMinutes: 5,
        challengeContext: ChallengeType.unlockChallenge,
        completedAt: now,
      );
      final b = AccessGrantRequest(
        sessionId: 's1',
        challengeId: 'c1',
        targetPackage: ChannelConstants.targetYouTube,
        durationMinutes: 5,
        challengeContext: ChallengeType.unlockChallenge,
        completedAt: now,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final map = a.toMap();
      expect(map['sessionId'], equals('s1'));
      expect(map['durationMinutes'], equals(5));
    });
  });

  group('AccessGrantResult', () {
    test('isAccessActive and remainingDuration compute relative to reference time', () {
      final now = DateTime(2026, 11, 21, 17, 0);
      final future = now.add(const Duration(minutes: 5));

      final activeResult = AccessGrantResult(
        sessionId: 's1',
        targetPackage: ChannelConstants.targetYouTube,
        status: AccessGrantStatus.granted,
        unlockUntil: future,
        grantedAt: now,
      );

      expect(activeResult.isSuccessful, isTrue);
      expect(activeResult.isAccessActive(now), isTrue);
      expect(activeResult.remainingDuration(now), equals(const Duration(minutes: 5)));

      // Expired reference time
      final past = now.add(const Duration(minutes: 6));
      expect(activeResult.isAccessActive(past), isFalse);
      expect(activeResult.remainingDuration(past), equals(Duration.zero));
    });

    test('implements equality and toMap', () {
      final now = DateTime(2026, 11, 21);
      final a = AccessGrantResult(
        sessionId: 's1',
        targetPackage: ChannelConstants.targetYouTube,
        status: AccessGrantStatus.granted,
        unlockUntil: now.add(const Duration(minutes: 5)),
        grantedAt: now,
      );
      final b = AccessGrantResult(
        sessionId: 's1',
        targetPackage: ChannelConstants.targetYouTube,
        status: AccessGrantStatus.granted,
        unlockUntil: now.add(const Duration(minutes: 5)),
        grantedAt: now,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final map = a.toMap();
      expect(map['isSuccessful'], isTrue);
      expect(map['status'], equals('granted'));
    });
  });
}
