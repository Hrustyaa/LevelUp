import '../free_workout/workout_session.dart';

/// Local calendar days, including today.
enum ProgressPeriod {
  sevenDays(7),
  thirtyDays(30);

  const ProgressPeriod(this.days);
  final int days;
}

DateTime localDay(DateTime timestamp) {
  final local = timestamp.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime _offsetDay(DateTime day, int offset) =>
    DateTime(day.year, day.month, day.day + offset);

List<WorkoutResult> completedWorkouts(
  Iterable<WorkoutResult> source, {
  required DateTime now,
}) => source.where((workout) {
  return workout.exercise.trim().isNotEmpty &&
      workout.sets.isNotEmpty &&
      workout.sets.every((count) => count > 0) &&
      !workout.endedAt.isBefore(workout.startedAt) &&
      !workout.endedAt.isAfter(now);
}).toList()..sort((a, b) => b.endedAt.compareTo(a.endedAt));

Map<DateTime, List<WorkoutResult>> groupWorkoutHistory(
  Iterable<WorkoutResult> workouts, {
  required DateTime now,
  String? exercise,
}) {
  final groups = <DateTime, List<WorkoutResult>>{};
  for (final workout in completedWorkouts(workouts, now: now)) {
    if (exercise != null && exercise != workout.exercise) continue;
    (groups[localDay(workout.endedAt)] ??= []).add(workout);
  }
  return groups;
}

class WorkoutProgressSummary {
  const WorkoutProgressSummary({
    required this.workouts,
    required this.repetitions,
    required this.sets,
    required this.activeDays,
    required this.dailyRepetitions,
  });

  final List<WorkoutResult> workouts;
  final int repetitions, sets, activeDays;
  final List<ProgressDayValue> dailyRepetitions;

  int get sessions => workouts.length;

  static WorkoutProgressSummary fromWorkouts(
    Iterable<WorkoutResult> source, {
    required DateTime now,
    required ProgressPeriod period,
  }) {
    final start = _offsetDay(localDay(now), 1 - period.days);
    final workouts = <WorkoutResult>[];
    final counts = <DateTime, int>{};
    var repetitions = 0;
    var sets = 0;
    for (final workout in completedWorkouts(source, now: now)) {
      final day = localDay(workout.endedAt);
      if (day.isBefore(start)) continue;
      final reps = workout.totalReps;
      workouts.add(workout);
      repetitions += reps;
      sets += workout.sets.length;
      counts.update(day, (value) => value + reps, ifAbsent: () => reps);
    }
    return WorkoutProgressSummary(
      workouts: List.unmodifiable(workouts),
      repetitions: repetitions,
      sets: sets,
      activeDays: counts.length,
      dailyRepetitions: List.unmodifiable([
        for (var offset = 0; offset < period.days; offset++)
          ProgressDayValue(
            date: _offsetDay(start, offset),
            value: counts[_offsetDay(start, offset)] ?? 0,
          ),
      ]),
    );
  }
}

class ProgressDayValue {
  const ProgressDayValue({required this.date, required this.value});
  final DateTime date;
  final int value;
}

class FocusUsageDay {
  const FocusUsageDay({required this.date, required this.milliseconds});
  final DateTime date;
  final int? milliseconds;
}

class FocusUsageSnapshot {
  const FocusUsageSnapshot({required this.days});

  final List<FocusUsageDay> days;

  int get observedDays => days.where((day) => day.milliseconds != null).length;
  int get totalMilliseconds =>
      days.fold(0, (sum, day) => sum + (day.milliseconds ?? 0));

  factory FocusUsageSnapshot.fromNative(
    Map<String, Object?> raw, {
    required DateTime now,
  }) {
    final today = localDay(now);
    final start = _offsetDay(today, -6);
    final first = start.millisecondsSinceEpoch;
    final end = _offsetDay(today, 1).millisecondsSinceEpoch;
    final parsed = <DateTime, int>{};
    if (raw['week'] case final List<Object?> entries) {
      for (final entry in entries) {
        if (entry case {
          'dateMs': final int stamp,
          'durationMs': final int duration,
        } when stamp >= first && stamp < end && duration >= 0) {
          parsed[localDay(DateTime.fromMillisecondsSinceEpoch(stamp))] =
              duration;
        }
      }
    }
    return FocusUsageSnapshot(
      days: List.unmodifiable([
        for (var offset = 0; offset < 7; offset++)
          FocusUsageDay(
            date: _offsetDay(start, offset),
            milliseconds: parsed[_offsetDay(start, offset)],
          ),
      ]),
    );
  }
}

String progressExerciseLabel(String exercise, String language) =>
    switch (exercise) {
      'squat' => switch (language) {
        'en' => 'Squats',
        'kk' => 'Отырып-тұру',
        _ => 'Приседания',
      },
      'push_up' => switch (language) {
        'en' => 'Push-ups',
        'kk' => 'Қолды бүгіп-жазу',
        _ => 'Отжимания',
      },
      _ => exercise,
    };
