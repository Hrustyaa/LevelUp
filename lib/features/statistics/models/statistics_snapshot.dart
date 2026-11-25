import 'package:flutter/foundation.dart';

import '../../focus/application/focus_service.dart';
import '../../progress/models/level_info.dart';
import '../../progress/models/progress_state.dart';
import '../../progress/models/streak_info.dart';
import 'access_duration_statistics.dart';
import 'daily_activity_stats.dart';
import 'unlock_statistics.dart';
import 'workout_statistics.dart';

/// Authoritative, immutable snapshot of all LevelUp user activity statistics.
///
/// Screen time / UsageStats metrics remain explicitly unsupported (`null`)
/// until Android `UsageStatsManager` is implemented.
@immutable
class StatisticsSnapshot {
  /// Timestamp when this snapshot was generated (local time).
  final DateTime generatedAt;

  /// Aggregated workout counts and verified repetitions.
  final WorkoutStatistics workouts;

  /// Aggregated confirmed unlock counts.
  final UnlockStatistics unlocks;

  /// Aggregated authorized access duration (never foreground screen time).
  final AccessDurationStatistics accessDuration;

  /// Ordered 7-day rolling local-calendar activity (oldest → newest).
  final List<DailyActivityStats> weeklyActivity;

  /// Authoritative XP, level, and streak state from Module 09 Progress Engine.
  final ProgressState progress;

  /// Current Focus state from [IFocusService], if available.
  final FocusState? focus;

  /// True while a refresh is in progress.
  final bool isLoading;

  /// Non-null when loading statistics failed; callers must not treat a failed
  /// snapshot as valid zero statistics.
  final String? errorMessage;

  /// Explicitly unsupported: Android foreground usage minutes are unavailable
  /// without `UsageStatsManager`.
  int? get foregroundUsageMinutes => null;

  /// Explicitly unsupported: screen time saved cannot be computed without
  /// `UsageStatsManager`.
  Duration? get screenTimeSaved => null;

  int get totalXp => progress.totalXp;
  LevelInfo get levelInfo => progress.levelInfo;
  StreakInfo get streakInfo => progress.streakInfo;
  int get currentLevel => progress.level;
  int get currentStreak => progress.currentStreak;
  int get longestStreak => progress.longestStreak;

  bool get hasError => errorMessage != null;

  const StatisticsSnapshot({
    required this.generatedAt,
    required this.workouts,
    required this.unlocks,
    required this.accessDuration,
    required this.weeklyActivity,
    required this.progress,
    this.focus,
    this.isLoading = false,
    this.errorMessage,
  });

  factory StatisticsSnapshot.initial({DateTime? now}) => StatisticsSnapshot(
        generatedAt: now ?? DateTime.fromMillisecondsSinceEpoch(0),
        workouts: WorkoutStatistics.empty,
        unlocks: UnlockStatistics.empty,
        accessDuration: AccessDurationStatistics.empty,
        weeklyActivity: const [],
        progress: ProgressState.initial(),
        focus: null,
        isLoading: false,
        errorMessage: null,
      );

  StatisticsSnapshot copyWith({
    DateTime? generatedAt,
    WorkoutStatistics? workouts,
    UnlockStatistics? unlocks,
    AccessDurationStatistics? accessDuration,
    List<DailyActivityStats>? weeklyActivity,
    ProgressState? progress,
    FocusState? focus,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return StatisticsSnapshot(
      generatedAt: generatedAt ?? this.generatedAt,
      workouts: workouts ?? this.workouts,
      unlocks: unlocks ?? this.unlocks,
      accessDuration: accessDuration ?? this.accessDuration,
      weeklyActivity: weeklyActivity ?? this.weeklyActivity,
      progress: progress ?? this.progress,
      focus: focus ?? this.focus,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
