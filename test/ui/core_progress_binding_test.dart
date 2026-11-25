import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/push_up_verification.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/workout_result.dart';
import 'package:levelup_test/progress/progress_models.dart';
import 'package:levelup_test/progress/progress_repository.dart';

class _History implements IWorkoutHistoryRepository {
  _History(this.results);

  final List<WorkoutResult> results;

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async => results
      .where(
        (result) =>
            !result.completedAt.isBefore(start) &&
            !result.completedAt.isAfter(end),
      )
      .toList();

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async =>
      results.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Core-backed chart and history retain exercise identity and reject unverified sessions',
    () async {
      final now = DateTime.now();
      WorkoutResult record(
        String id,
        ExerciseType type,
        String source, {
        int daysAgo = 0,
      }) => WorkoutResult(
        sessionId: id,
        requestId: id,
        challengeId: id,
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: type,
        completedRepetitions: 5,
        duration: const Duration(seconds: 19),
        completedAt: now.subtract(Duration(days: daysAgo)),
        eligibleForAccess: false,
        accessDurationSeconds: 0,
        source: source,
      );
      final repository = LocalProgressRepository(
        history: _History([
          record('squat', ExerciseType.squats, 'camera'),
          record(
            'push-up',
            ExerciseType.pushUp,
            PushUpVerification.verifiedSource,
          ),
          record('simulated', ExerciseType.squats, 'simulated'),
          record(
            'experimental',
            ExerciseType.pushUp,
            PushUpVerification.experimentalSource,
          ),
          record('older', ExerciseType.squats, 'camera', daysAgo: 35),
        ]),
      );

      final chart = await repository.loadWorkouts();
      expect(
        chart.map((workout) => progressExerciseLabel(workout.exercise, 'en')),
        ['Squats', 'Push-ups'],
      );
      expect(chart.map((workout) => workout.totalReps), [5, 5]);
      expect(chart.last.durationSeconds, 19);

      final first = await repository.historyLoader!(2);
      expect(first.workouts.length, 2);
      expect(first.hasMore, isTrue);
      final all = await repository.historyLoader!(10);
      expect(all.workouts.length, 3);
      expect(all.workouts.last.endedAt, now.subtract(const Duration(days: 35)));
      expect(all.hasMore, isFalse);
    },
  );
}
