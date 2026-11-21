import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/workout_result.dart';
import 'package:levelup_test/models/workout_session.dart';
import 'package:levelup_test/models/workout_session_status.dart';

void main() {
  group('WorkoutSessionStatus', () {
    test('isTerminal is true only for terminal states', () {
      expect(WorkoutSessionStatus.created.isTerminal, isFalse);
      expect(WorkoutSessionStatus.preparing.isTerminal, isFalse);
      expect(WorkoutSessionStatus.active.isTerminal, isFalse);

      expect(WorkoutSessionStatus.completed.isTerminal, isTrue);
      expect(WorkoutSessionStatus.cancelled.isTerminal, isTrue);
      expect(WorkoutSessionStatus.failed.isTerminal, isTrue);
    });

    test('canAcceptProgress is true only for active status', () {
      expect(WorkoutSessionStatus.active.canAcceptProgress, isTrue);
      expect(WorkoutSessionStatus.created.canAcceptProgress, isFalse);
      expect(WorkoutSessionStatus.preparing.canAcceptProgress, isFalse);
      expect(WorkoutSessionStatus.completed.canAcceptProgress, isFalse);
      expect(WorkoutSessionStatus.cancelled.canAcceptProgress, isFalse);
      expect(WorkoutSessionStatus.failed.canAcceptProgress, isFalse);
    });

    test('isSuccessful is true only for completed status', () {
      expect(WorkoutSessionStatus.completed.isSuccessful, isTrue);
      expect(WorkoutSessionStatus.cancelled.isSuccessful, isFalse);
      expect(WorkoutSessionStatus.failed.isSuccessful, isFalse);
    });
  });

  group('WorkoutResult', () {
    test('constructs valid unlock result', () {
      final now = DateTime(2026, 11, 21, 17, 0);
      final result = WorkoutResult(
        sessionId: 'session_1',
        requestId: 'req_1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 45),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
        earnedXp: 50,
      );

      expect(result.eligibleForAccess, isTrue);
      expect(result.accessDurationSeconds, equals(300));
      expect(result.targetPackage, equals(ChannelConstants.targetYouTube));
    });

    test('constructs valid free workout result with 0 access and no target', () {
      final now = DateTime(2026, 11, 21, 17, 0);
      final result = WorkoutResult(
        sessionId: 'session_2',
        requestId: 'req_2',
        challengeId: 'squats_free_5',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetPackage: null,
        completedRepetitions: 5,
        duration: const Duration(seconds: 40),
        completedAt: now,
        eligibleForAccess: false,
        accessDurationSeconds: 0,
        earnedXp: 50,
      );

      expect(result.eligibleForAccess, isFalse);
      expect(result.accessDurationSeconds, equals(0));
      expect(result.targetPackage, isNull);
    });

    test('asserts that free workout cannot produce access authorization', () {
      final now = DateTime(2026, 11, 21, 17, 0);

      expect(
        () => WorkoutResult(
          sessionId: 'session_3',
          requestId: 'req_3',
          challengeId: 'squats_free_5',
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          completedRepetitions: 5,
          duration: const Duration(seconds: 40),
          completedAt: now,
          eligibleForAccess: true, // Violation!
          accessDurationSeconds: 300,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('implements equality and toMap', () {
      final now = DateTime(2026, 11, 21);
      final a = WorkoutResult(
        sessionId: 'session_1',
        requestId: 'req_1',
        challengeId: 'squats_free_5',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        completedRepetitions: 5,
        duration: const Duration(seconds: 30),
        completedAt: now,
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );
      final b = WorkoutResult(
        sessionId: 'session_1',
        requestId: 'req_1',
        challengeId: 'squats_free_5',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        completedRepetitions: 5,
        duration: const Duration(seconds: 30),
        completedAt: now,
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final map = a.toMap();
      expect(map['sessionId'], equals('session_1'));
      expect(map['eligibleForAccess'], isFalse);
    });
  });

  group('WorkoutSession', () {
    test('duration computes difference between startedAt and completedAt', () {
      final start = DateTime(2026, 11, 21, 17, 0, 0);
      final end = DateTime(2026, 11, 21, 17, 0, 45);

      final session = WorkoutSession(
        sessionId: 's1',
        requestId: 'r1',
        challengeId: 'c1',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetRepetitions: 5,
        startedAt: start,
        completedAt: end,
        status: WorkoutSessionStatus.completed,
      );

      expect(session.duration, equals(const Duration(seconds: 45)));
    });

    test('toWorkoutResult throws if session is not completed', () {
      const session = WorkoutSession(
        sessionId: 's1',
        requestId: 'r1',
        challengeId: 'c1',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetRepetitions: 5,
        status: WorkoutSessionStatus.active,
      );

      expect(() => session.toWorkoutResult(), throwsA(isA<StateError>()));
    });

    test('toWorkoutResult succeeds when session is completed', () {
      final start = DateTime(2026, 11, 21, 17, 0, 0);
      final end = DateTime(2026, 11, 21, 17, 0, 30);

      final session = WorkoutSession(
        sessionId: 's1',
        requestId: 'r1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        targetPackage: ChannelConstants.targetInstagram,
        exerciseType: ExerciseType.squats,
        targetRepetitions: 5,
        verifiedRepetitions: 5,
        startedAt: start,
        completedAt: end,
        status: WorkoutSessionStatus.completed,
        accessDurationSeconds: 300,
        xpReward: 50,
      );

      final result = session.toWorkoutResult();
      expect(result.sessionId, equals('s1'));
      expect(result.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(result.eligibleForAccess, isTrue);
      expect(result.accessDurationSeconds, equals(300));
    });

    test('implements copyWith and equality', () {
      const a = WorkoutSession(
        sessionId: 's1',
        requestId: 'r1',
        challengeId: 'c1',
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetRepetitions: 5,
      );

      final updated = a.copyWith(verifiedRepetitions: 3);
      expect(updated.verifiedRepetitions, equals(3));
      expect(updated.sessionId, equals(a.sessionId));
    });
  });
}
