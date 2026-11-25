import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/free_workout/workout_session.dart';
import 'package:levelup_test/progress/progress_models.dart';

WorkoutResult session(DateTime end, List<int> sets) => WorkoutResult(
  exercise: 'squat',
  startedAt: end.subtract(const Duration(minutes: 4)),
  endedAt: end,
  sets: List.unmodifiable(sets),
);

void main() {
  test('7-day overview uses real completed sets only', () {
    final now = DateTime(2026, 11, 25, 14);
    final summary = WorkoutProgressSummary.fromWorkouts(
      [
        session(DateTime(2026, 11, 25, 11), [12, 9, 7]),
        session(DateTime(2026, 11, 24, 18), [8]),
        session(DateTime(2026, 11, 17, 11), [100]),
        session(DateTime(2026, 12, 1, 11), [50]),
      ],
      now: now,
      period: ProgressPeriod.sevenDays,
    );
    expect(summary.sessions, 2);
    expect(summary.sets, 4);
    expect(summary.repetitions, 36);
    expect(summary.activeDays, 2);
    expect(summary.dailyRepetitions.length, 7);
    expect(summary.dailyRepetitions.last.value, 28);
    expect(summary.dailyRepetitions[5].value, 8);
  });

  test('30-day chart includes each date and the first day of the period', () {
    final now = DateTime(2026, 11, 25, 14);
    final summary = WorkoutProgressSummary.fromWorkouts(
      [
        session(DateTime(2026, 11, 25, 11), [12]),
        session(DateTime(2026, 10, 27, 11), [8]),
        session(DateTime(2026, 10, 26, 23, 59), [100]),
        session(DateTime(2026, 10, 15, 11), [100]),
      ],
      now: now,
      period: ProgressPeriod.thirtyDays,
    );
    expect(summary.sessions, 2);
    final bars = summary.dailyRepetitions;
    expect(bars.length, 30);
    expect(bars.fold<int>(0, (sum, bar) => sum + bar.value), 20);
    expect(bars.last.value, 12);
    expect(bars.first.date, DateTime(2026, 10, 27));
    expect(bars.first.value, 8);
  });

  test('missing Android usage dates stay unknown instead of becoming zero', () {
    final now = DateTime(2026, 11, 25, 14);
    final today = DateTime(2026, 11, 25);
    final snapshot = FocusUsageSnapshot.fromNative({
      'week': [
        {'dateMs': today.millisecondsSinceEpoch, 'durationMs': 1800000},
      ],
    }, now: now);
    expect(snapshot.days.length, 7);
    expect(snapshot.observedDays, 1);
    expect(snapshot.days.first.milliseconds, isNull);
    expect(snapshot.days.last.milliseconds, 1800000);
    expect(snapshot.totalMilliseconds, 1800000);
  });

  test('unknown or invalid usage values are ignored', () {
    final now = DateTime(2026, 11, 25);
    final snapshot = FocusUsageSnapshot.fromNative({
      'week': [
        {'dateMs': now.millisecondsSinceEpoch, 'durationMs': -1},
        {'dateMs': 'invalid', 'durationMs': 100},
      ],
    }, now: now);
    expect(snapshot.observedDays, 0);
    expect(snapshot.totalMilliseconds, 0);
  });

  test('groups by local completion date and filters only recorded types', () {
    final now = DateTime(2026, 11, 25, 20);
    final today = session(DateTime(2026, 11, 25, 19), [12]);
    final yesterday = session(DateTime(2026, 11, 24, 19), [9]);
    final earlier = session(DateTime(2026, 11, 24, 9), [5]);
    final broken = WorkoutResult(
      exercise: 'squat',
      startedAt: now,
      endedAt: now.subtract(const Duration(minutes: 1)),
      sets: [4],
    );
    final groups = groupWorkoutHistory([
      earlier,
      today,
      yesterday,
      broken,
    ], now: now);
    expect(groups.keys, [DateTime(2026, 11, 25), DateTime(2026, 11, 24)]);
    expect(groups[DateTime(2026, 11, 24)], [yesterday, earlier]);
    expect(
      groupWorkoutHistory([today], now: now, exercise: 'different'),
      isEmpty,
    );
    final summary = WorkoutProgressSummary.fromWorkouts(
      [today, yesterday, earlier, broken],
      now: now,
      period: ProgressPeriod.sevenDays,
    );
    expect(summary.activeDays, 2);
    expect(summary.sessions, 3);
  });

  test('workout history sorting is newest first', () {
    final now = DateTime(2026, 11, 25, 20);
    final a = session(DateTime(2026, 11, 23), [10]);
    final b = session(DateTime(2026, 11, 25), [20]);
    final summary = WorkoutProgressSummary.fromWorkouts(
      [a, b],
      now: now,
      period: ProgressPeriod.sevenDays,
    );
    expect(summary.workouts.first.totalReps, 20);
    expect(summary.workouts.last.totalReps, 10);
  });
}
