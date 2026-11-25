import 'package:flutter/foundation.dart';

import '../../../data/database/database_constants.dart';
import 'achievement_category.dart';

/// Immutable persisted record of a single unlocked achievement.
@immutable
class AchievementUnlockRecord {
  final String achievementId;
  final DateTime unlockedAt;
  final AchievementCategory category;
  final int targetValue;
  final int observedValue;

  const AchievementUnlockRecord({
    required this.achievementId,
    required this.unlockedAt,
    required this.category,
    required this.targetValue,
    required this.observedValue,
  });

  factory AchievementUnlockRecord.fromMap(Map<String, dynamic> map) {
    return AchievementUnlockRecord(
      achievementId: map[DatabaseConstants.colAchievementId] as String,
      unlockedAt: DateTime.fromMillisecondsSinceEpoch(
        map[DatabaseConstants.colUnlockedAt] as int,
        isUtc: true,
      ),
      category: AchievementCategory.values.byName(
        map[DatabaseConstants.colCategory] as String,
      ),
      targetValue: (map[DatabaseConstants.colTargetValue] as num).toInt(),
      observedValue: (map[DatabaseConstants.colObservedValue] as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        DatabaseConstants.colAchievementId: achievementId,
        DatabaseConstants.colUnlockedAt: unlockedAt.toUtc().millisecondsSinceEpoch,
        DatabaseConstants.colCategory: category.name,
        DatabaseConstants.colTargetValue: targetValue,
        DatabaseConstants.colObservedValue: observedValue,
      };
}
