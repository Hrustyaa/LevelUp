import '../models/achievement_category.dart';
import '../models/achievement_definition.dart';

/// Centralized, immutable MVP achievement catalog.
///
/// Future achievements can be appended here with stable unique [id]s without
/// altering persistence or evaluation logic.
abstract final class AchievementCatalog {
  static const String firstWorkoutId = 'first_workout';
  static const String fiveWorkoutsId = 'five_workouts';
  static const String twentyFiveSquatsId = 'twenty_five_squats';
  static const String firstUnlockId = 'first_unlock';
  static const String threeDayStreakId = 'three_day_streak';
  static const String reachLevelTwoId = 'reach_level_two';

  static const List<AchievementDefinition> definitions = [
    AchievementDefinition(
      id: firstWorkoutId,
      category: AchievementCategory.workouts,
      targetValue: 1,
      titleKey: 'achievement.first_workout.title',
      descriptionKey: 'achievement.first_workout.description',
      sortOrder: 1,
    ),
    AchievementDefinition(
      id: fiveWorkoutsId,
      category: AchievementCategory.workouts,
      targetValue: 5,
      titleKey: 'achievement.five_workouts.title',
      descriptionKey: 'achievement.five_workouts.description',
      sortOrder: 2,
    ),
    AchievementDefinition(
      id: twentyFiveSquatsId,
      category: AchievementCategory.repetitions,
      targetValue: 25,
      titleKey: 'achievement.twenty_five_squats.title',
      descriptionKey: 'achievement.twenty_five_squats.description',
      sortOrder: 3,
    ),
    AchievementDefinition(
      id: firstUnlockId,
      category: AchievementCategory.unlocks,
      targetValue: 1,
      titleKey: 'achievement.first_unlock.title',
      descriptionKey: 'achievement.first_unlock.description',
      sortOrder: 4,
    ),
    AchievementDefinition(
      id: threeDayStreakId,
      category: AchievementCategory.streaks,
      targetValue: 3,
      titleKey: 'achievement.three_day_streak.title',
      descriptionKey: 'achievement.three_day_streak.description',
      sortOrder: 5,
    ),
    AchievementDefinition(
      id: reachLevelTwoId,
      category: AchievementCategory.levels,
      targetValue: 2,
      titleKey: 'achievement.reach_level_two.title',
      descriptionKey: 'achievement.reach_level_two.description',
      sortOrder: 6,
    ),
  ];
}
