import 'package:flutter/foundation.dart';

/// Immutable statistics describing **authorized temporary access duration**
/// granted by confirmed unlocks.
///
/// IMPORTANT: Authorized duration is the time window granted by the native
/// gate (e.g. 300 seconds per confirmed unlock). It is **not** actual
/// foreground app usage or screen time saved, because Android `UsageStatsManager`
/// is not implemented.
@immutable
class AccessDurationStatistics {
  /// Sum of `duration_seconds` across all confirmed unlocks.
  final Duration totalAuthorizedDuration;

  /// Sum of `duration_seconds` across confirmed unlocks today (local calendar).
  final Duration todayAuthorizedDuration;

  /// Mean authorized duration per confirmed unlock, or `null` when there are
  /// zero confirmed unlocks (distinguishing unavailable from zero).
  final Duration? averageAuthorizedDuration;

  const AccessDurationStatistics({
    this.totalAuthorizedDuration = Duration.zero,
    this.todayAuthorizedDuration = Duration.zero,
    this.averageAuthorizedDuration,
  });

  static const empty = AccessDurationStatistics();
}
