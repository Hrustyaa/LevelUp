import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/adapters/core_insights_adapter.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/models/access_attempt_record.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/workout_result.dart';

class _FakeHistoryRepo implements IWorkoutHistoryRepository {
  final List<WorkoutResult> workouts;
  _FakeHistoryRepo(this.workouts);

  @override
  Future<int> countCompletedWorkouts() async => workouts.length;

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async =>
      workouts;

  @override
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType}) async =>
      0;

  @override
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId) async => null;

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      workouts;

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {}
}

class _FakeAccessRepo implements IAccessAttemptRepository {
  final List<AccessAttemptRecord> attempts;
  _FakeAccessRepo(this.attempts);

  @override
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId) async =>
      null;

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async =>
      attempts;

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) =>
      throw UnimplementedError();
}

void main() {
  group('CoreInsightsAdapter XP & Progress Honesty Tests', () {
    test('1. Reports totalXp and activity xp as null when Module 09 is unimplemented', () async {
      final now = DateTime.now();
      final workout = WorkoutResult(
        sessionId: 'sess-1',
        requestId: 'req-1',
        challengeId: 'squats_unlock_5',
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 30),
        completedAt: now,
        eligibleForAccess: true,
        accessDurationSeconds: 300,
        earnedXp: 50,
      );
      final attempt = AccessAttemptRecord(
        sessionId: 'sess-1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        state: AccessAttemptState.confirmed,
        attemptedAt: now,
        confirmedAt: now,
        unlockUntil: now.add(const Duration(minutes: 5)),
      );

      final adapter = CoreInsightsAdapter(
        historyRepo: _FakeHistoryRepo([workout]),
        accessRepo: _FakeAccessRepo([attempt]),
      );

      final insights = await adapter.loadInsights();

      expect(insights.historyReady, isTrue);
      expect(insights.todayUsageMinutes, isNull);
      expect(insights.todayUnlocks, 1);
      expect(insights.totalXp, isNull);
      expect(insights.events.length, 1);
      expect(insights.events.single.xp, isNull);
    });

    test('2. Empty history still reports totalXp as null rather than fabricating Level 1 (0 XP)', () async {
      final adapter = CoreInsightsAdapter(
        historyRepo: _FakeHistoryRepo(const []),
        accessRepo: _FakeAccessRepo(const []),
      );

      final insights = await adapter.loadInsights();

      expect(insights.historyReady, isTrue);
      expect(insights.totalXp, isNull);
      expect(insights.todayUnlocks, 0);
    });
  });
}
