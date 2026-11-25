import 'package:flutter/foundation.dart';

/// Immutable aggregate workout statistics derived from persisted `workout_sessions`.
@immutable
class WorkoutStatistics {
  /// Total completed workouts across all time (distinct `session_id`).
  final int allTimeCompleted;

  /// Completed workouts in the current local calendar day.
  final int todayCompleted;

  /// Completed workouts in the current local calendar week (Monday–Sunday).
  final int thisWeekCompleted;

  /// Total verified squat repetitions across all completed workouts.
  final int totalVerifiedRepetitions;

  /// Completed `unlockChallenge` workouts across all time.
  final int unlockChallengesCompleted;

  /// Completed `freeWorkout` workouts across all time.
  final int freeWorkoutsCompleted;

  const WorkoutStatistics({
    this.allTimeCompleted = 0,
    this.todayCompleted = 0,
    this.thisWeekCompleted = 0,
    this.totalVerifiedRepetitions = 0,
    this.unlockChallengesCompleted = 0,
    this.freeWorkoutsCompleted = 0,
  });

  /// Alias for [allTimeCompleted] for consumer convenience.
  int get totalCompleted => allTimeCompleted;

  static const empty = WorkoutStatistics();
}
