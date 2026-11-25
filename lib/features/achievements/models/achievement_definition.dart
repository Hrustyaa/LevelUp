import 'package:flutter/foundation.dart';

import 'achievement_category.dart';

/// Immutable definition of an achievement milestone in the LevelUp catalog.
///
/// Uses translation keys ([titleKey], [descriptionKey]) rather than hardcoded
/// UI copy so localization remains cleanly separated in the presentation layer.
@immutable
class AchievementDefinition {
  final String id;
  final AchievementCategory category;
  final int targetValue;
  final String titleKey;
  final String descriptionKey;
  final int sortOrder;

  const AchievementDefinition({
    required this.id,
    required this.category,
    required this.targetValue,
    required this.titleKey,
    required this.descriptionKey,
    required this.sortOrder,
  }) : assert(targetValue > 0, 'Achievement targetValue must be positive');
}
