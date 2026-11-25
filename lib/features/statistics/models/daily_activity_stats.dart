import 'package:flutter/foundation.dart';

/// Immutable activity summary for a single local calendar day.
@immutable
class DailyActivityStats {
  /// Local midnight `DateTime` representing this calendar day.
  final DateTime localDate;

  /// Canonical `'YYYY-MM-DD'` local date string.
  final String dateKey;

  /// Distinct completed workouts on this local calendar day.
  final int completedWorkouts;

  /// Distinct confirmed unlocks on this local calendar day.
  final int confirmedUnlocks;

  /// Total verified squat repetitions across completed workouts on this day.
  final int verifiedRepetitions;

  const DailyActivityStats({
    required this.localDate,
    required this.dateKey,
    this.completedWorkouts = 0,
    this.confirmedUnlocks = 0,
    this.verifiedRepetitions = 0,
  });
}
