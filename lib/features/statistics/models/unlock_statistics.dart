import 'package:flutter/foundation.dart';

/// Immutable aggregate unlock statistics derived from confirmed `access_attempts`.
///
/// Only `AccessAttemptState.confirmed` records are counted; `prepared`,
/// `uncertain`, and `definitivelyRejected` attempts and `freeWorkout`
/// sessions are strictly excluded.
@immutable
class UnlockStatistics {
  /// Confirmed unlocks in the current local calendar day.
  final int todayConfirmed;

  /// Confirmed unlocks in the current local calendar week (Monday–Sunday).
  final int thisWeekConfirmed;

  /// Confirmed unlocks across all time (distinct `session_id`).
  final int allTimeConfirmed;

  const UnlockStatistics({
    this.todayConfirmed = 0,
    this.thisWeekConfirmed = 0,
    this.allTimeConfirmed = 0,
  });

  static const empty = UnlockStatistics();
}
