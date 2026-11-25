import 'package:flutter/foundation.dart';

import 'achievement_progress.dart';
import 'achievement_unlock_record.dart';

/// Immutable snapshot of all achievements and unlock state for Module 11B.
@immutable
class AchievementState {
  final List<AchievementProgress> achievements;
  final List<AchievementUnlockRecord> recentlyUnlocked;
  final bool isLoading;
  final String? errorMessage;

  const AchievementState({
    this.achievements = const [],
    this.recentlyUnlocked = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  factory AchievementState.initial() => const AchievementState();

  List<AchievementProgress> get unlockedAchievements =>
      achievements.where((a) => a.isUnlocked).toList(growable: false);

  List<AchievementProgress> get lockedAchievements =>
      achievements.where((a) => !a.isUnlocked).toList(growable: false);

  int get unlockedCount => achievements.where((a) => a.isUnlocked).length;

  int get totalCount => achievements.length;

  bool get hasError => errorMessage != null;

  AchievementState copyWith({
    List<AchievementProgress>? achievements,
    List<AchievementUnlockRecord>? recentlyUnlocked,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AchievementState(
      achievements: achievements ?? this.achievements,
      recentlyUnlocked: recentlyUnlocked ?? this.recentlyUnlocked,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
