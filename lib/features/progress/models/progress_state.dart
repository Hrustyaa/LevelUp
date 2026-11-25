import 'package:flutter/foundation.dart';

import 'level_info.dart';
import 'streak_info.dart';
import 'xp_reward_record.dart';

/// Immutable state snapshot exposed by [IProgressService] for Module 09B UI binding.
@immutable
class ProgressState {
  final LevelInfo levelInfo;
  final StreakInfo streakInfo;
  final List<XpRewardRecord> recentRewards;
  final int completedWorkoutCount;
  final bool isLoading;
  final String? errorMessage;

  const ProgressState({
    required this.levelInfo,
    required this.streakInfo,
    this.recentRewards = const [],
    this.completedWorkoutCount = 0,
    this.isLoading = false,
    this.errorMessage,
  });

  int get totalXp => levelInfo.totalXp;
  int get level => levelInfo.level;
  int get currentStreak => streakInfo.currentStreak;
  int get longestStreak => streakInfo.longestStreak;

  factory ProgressState.initial() => ProgressState(
        levelInfo: LevelInfo.initial(),
        streakInfo: StreakInfo.empty(),
      );

  ProgressState copyWith({
    LevelInfo? levelInfo,
    StreakInfo? streakInfo,
    List<XpRewardRecord>? recentRewards,
    int? completedWorkoutCount,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProgressState(
      levelInfo: levelInfo ?? this.levelInfo,
      streakInfo: streakInfo ?? this.streakInfo,
      recentRewards: recentRewards ?? this.recentRewards,
      completedWorkoutCount: completedWorkoutCount ?? this.completedWorkoutCount,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
