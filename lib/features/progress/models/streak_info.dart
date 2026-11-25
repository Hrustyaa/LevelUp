import 'package:flutter/foundation.dart';

/// Deterministic daily workout streak snapshot in the user's local calendar.
@immutable
class StreakInfo {
  final int currentStreak;
  final int longestStreak;
  final String? lastWorkoutLocalDate;
  final bool completedToday;

  const StreakInfo({
    required this.currentStreak,
    required this.longestStreak,
    this.lastWorkoutLocalDate,
    this.completedToday = false,
  });

  factory StreakInfo.empty() => const StreakInfo(
        currentStreak: 0,
        longestStreak: 0,
        lastWorkoutLocalDate: null,
        completedToday: false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreakInfo &&
          runtimeType == other.runtimeType &&
          currentStreak == other.currentStreak &&
          longestStreak == other.longestStreak &&
          lastWorkoutLocalDate == other.lastWorkoutLocalDate &&
          completedToday == other.completedToday;

  @override
  int get hashCode => Object.hash(
        currentStreak,
        longestStreak,
        lastWorkoutLocalDate,
        completedToday,
      );
}
