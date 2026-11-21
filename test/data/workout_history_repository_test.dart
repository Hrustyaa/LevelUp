import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/persistence_exceptions.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/workout_result.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late LevelUpDatabase dbManager;
  late WorkoutHistoryRepository repository;
  late DateTime fixedTime;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workout_repo_test_');
    final dbPath = p.join(tempDir.path, 'workout_test.db');
    dbManager = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
    repository = WorkoutHistoryRepository(databaseManager: dbManager);
    fixedTime = DateTime.utc(2026, 11, 21, 17, 30);
  });

  tearDown(() async {
    await dbManager.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  WorkoutResult createUnlockResult({
    String sessionId = 'session_1',
    String targetPackage = ChannelConstants.targetYouTube,
    int completedReps = 5,
    Duration duration = const Duration(seconds: 45),
    DateTime? completedAt,
  }) {
    return WorkoutResult(
      sessionId: sessionId,
      requestId: 'req_$sessionId',
      challengeId: 'squats_unlock_5',
      challengeContext: ChallengeType.unlockChallenge,
      exerciseType: ExerciseType.squats,
      targetPackage: targetPackage,
      completedRepetitions: completedReps,
      duration: duration,
      completedAt: completedAt ?? fixedTime,
      eligibleForAccess: true,
      accessDurationSeconds: 300,
    );
  }

  WorkoutResult createFreeResult({
    String sessionId = 'session_free',
    int completedReps = 5,
    Duration duration = const Duration(seconds: 40),
    DateTime? completedAt,
  }) {
    return WorkoutResult(
      sessionId: sessionId,
      requestId: 'req_$sessionId',
      challengeId: 'squats_free_5',
      challengeContext: ChallengeType.freeWorkout,
      exerciseType: ExerciseType.squats,
      targetPackage: null,
      completedRepetitions: completedReps,
      duration: duration,
      completedAt: completedAt ?? fixedTime,
      eligibleForAccess: false,
      accessDurationSeconds: 0,
    );
  }

  group('WorkoutHistoryRepository CRUD & Constraints', () {
    test('10. retrieving from an empty history returns empty list and zeros', () async {
      final recent = await repository.getRecentWorkouts();
      expect(recent, isEmpty);

      final count = await repository.countCompletedWorkouts();
      expect(count, equals(0));

      final totalReps = await repository.getTotalVerifiedRepetitions();
      expect(totalReps, equals(0));

      final byId = await repository.getWorkoutBySessionId('non_existent');
      expect(byId, isNull);
    });

    test('2 & 3. saves one completed workout and retrieves it by sessionId', () async {
      final workout = createUnlockResult(sessionId: 'session_save_1');
      await repository.saveCompletedWorkout(workout);

      final retrieved = await repository.getWorkoutBySessionId('session_save_1');
      expect(retrieved, isNotNull);
      expect(retrieved!.sessionId, equals('session_save_1'));
      expect(retrieved.challengeId, equals('squats_unlock_5'));
      expect(retrieved.challengeContext, equals(ChallengeType.unlockChallenge));
      expect(retrieved.exerciseType, equals(ExerciseType.squats));
      expect(retrieved.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(retrieved.completedRepetitions, equals(5));
      expect(retrieved.duration, equals(const Duration(seconds: 45)));
      expect(retrieved.completedAt.millisecondsSinceEpoch, equals(fixedTime.millisecondsSinceEpoch));
      expect(retrieved.eligibleForAccess, isTrue);
      expect(retrieved.accessDurationSeconds, equals(300));
    });

    test('5. duplicate identical session ID does not create a second workout (idempotent)', () async {
      final workout = createUnlockResult(sessionId: 'session_dup_1');

      // First save
      await repository.saveCompletedWorkout(workout);
      expect(await repository.countCompletedWorkouts(), equals(1));

      // Second save with identical payload
      await repository.saveCompletedWorkout(workout);
      expect(await repository.countCompletedWorkouts(), equals(1));
    });

    test('6. conflicting payload for an existing session ID throws ConflictingWorkoutRecordException', () async {
      final initial = createUnlockResult(
        sessionId: 'session_conflict',
        completedReps: 5,
      );
      await repository.saveCompletedWorkout(initial);

      // Attempt to save conflicting payload with same sessionId but different repetitions
      final conflicting = createUnlockResult(
        sessionId: 'session_conflict',
        completedReps: 10, // Conflicting!
      );

      await expectLater(
        () => repository.saveCompletedWorkout(conflicting),
        throwsA(
          isA<ConflictingWorkoutRecordException>()
              .having((e) => e.sessionId, 'sessionId', equals('session_conflict')),
        ),
      );

      // Verify the original record was NOT overwritten
      final current = await repository.getWorkoutBySessionId('session_conflict');
      expect(current!.completedRepetitions, equals(5));
    });

    test('7. free workout stores null target package and preserves zero access eligibility', () async {
      final freeWorkout = createFreeResult(sessionId: 'session_free_target_test');
      await repository.saveCompletedWorkout(freeWorkout);

      final retrieved = await repository.getWorkoutBySessionId('session_free_target_test');
      expect(retrieved, isNotNull);
      expect(retrieved!.challengeContext, equals(ChallengeType.freeWorkout));
      expect(retrieved.targetPackage, isNull);
      expect(retrieved.eligibleForAccess, isFalse);
      expect(retrieved.accessDurationSeconds, equals(0));
    });

    test('8. unlock workout preserves its target package', () async {
      final unlockWorkout = createUnlockResult(
        sessionId: 'session_instagram_unlock',
        targetPackage: ChannelConstants.targetInstagram,
      );
      await repository.saveCompletedWorkout(unlockWorkout);

      final retrieved = await repository.getWorkoutBySessionId('session_instagram_unlock');
      expect(retrieved, isNotNull);
      expect(retrieved!.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(retrieved.eligibleForAccess, isTrue);
    });

    test('9. invalid data is rejected with InvalidWorkoutDataException', () async {
      // Empty sessionId
      final emptySession = WorkoutResult(
        sessionId: '   ',
        requestId: 'r1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 40),
        completedAt: fixedTime,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      await expectLater(
        () => repository.saveCompletedWorkout(emptySession),
        throwsA(isA<InvalidWorkoutDataException>()),
      );

      // Negative repetitions
      final negReps = WorkoutResult(
        sessionId: 'neg_reps',
        requestId: 'r1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: -1,
        duration: const Duration(seconds: 40),
        completedAt: fixedTime,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );

      await expectLater(
        () => repository.saveCompletedWorkout(negReps),
        throwsA(isA<InvalidWorkoutDataException>()),
      );
    });

    test('11. retrieves recent workouts ordered by completion date descending', () async {
      final t1 = fixedTime.subtract(const Duration(hours: 3));
      final t2 = fixedTime.subtract(const Duration(hours: 2));
      final t3 = fixedTime.subtract(const Duration(hours: 1));

      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 's1', completedAt: t1));
      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 's2', completedAt: t2));
      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 's3', completedAt: t3));

      final recent = await repository.getRecentWorkouts(limit: 2);
      expect(recent.length, equals(2));
      expect(recent[0].sessionId, equals('s3')); // Most recent first
      expect(recent[1].sessionId, equals('s2'));
    });

    test('12. date-range queries filter workouts accurately', () async {
      final t1 = DateTime.utc(2026, 11, 20, 10, 0);
      final t2 = DateTime.utc(2026, 11, 21, 10, 0);
      final t3 = DateTime.utc(2026, 11, 22, 10, 0);

      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 'd1', completedAt: t1));
      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 'd2', completedAt: t2));
      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 'd3', completedAt: t3));

      // Query only Nov 21
      final range = await repository.getWorkoutsByDateRange(
        DateTime.utc(2026, 11, 21, 0, 0),
        DateTime.utc(2026, 11, 21, 23, 59),
      );

      expect(range.length, equals(1));
      expect(range.first.sessionId, equals('d2'));
    });

    test('13. calculates total verified repetitions accurately', () async {
      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 'r1', completedReps: 5));
      await repository.saveCompletedWorkout(createUnlockResult(sessionId: 'r2', completedReps: 10));
      await repository.saveCompletedWorkout(createFreeResult(sessionId: 'r3', completedReps: 15));

      final total = await repository.getTotalVerifiedRepetitions();
      expect(total, equals(30));

      final squatsTotal = await repository.getTotalVerifiedRepetitions(exerciseType: ExerciseType.squats);
      expect(squatsTotal, equals(30));
    });

    test('19. concurrent duplicate inserts result in exactly one row without error', () async {
      final workout = createUnlockResult(sessionId: 'session_concurrent_insert');

      // Firing 5 identical saves concurrently
      await Future.wait([
        repository.saveCompletedWorkout(workout),
        repository.saveCompletedWorkout(workout),
        repository.saveCompletedWorkout(workout),
        repository.saveCompletedWorkout(workout),
        repository.saveCompletedWorkout(workout),
      ]);

      expect(await repository.countCompletedWorkouts(), equals(1));
      final saved = await repository.getWorkoutBySessionId('session_concurrent_insert');
      expect(saved, isNotNull);
    });
  });
}
