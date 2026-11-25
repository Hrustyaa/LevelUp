import 'package:flutter/foundation.dart';

import 'achievement_definition.dart';

/// Immutable view combining an [AchievementDefinition] with its authoritative
/// current progress and unlock status.
@immutable
class AchievementProgress {
  final AchievementDefinition definition;
  final int currentValue;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const AchievementProgress({
    required this.definition,
    required this.currentValue,
    required this.isUnlocked,
    this.unlockedAt,
  });

  String get id => definition.id;
  int get targetValue => definition.targetValue;

  /// Current progress clamped to `[0, targetValue]` for deterministic UI display.
  int get clampedCurrentValue {
    if (isUnlocked) return targetValue;
    if (currentValue < 0) return 0;
    if (currentValue > targetValue) return targetValue;
    return currentValue;
  }

  /// Progress fraction in `[0.0, 1.0]`.
  double get fraction => clampedCurrentValue / targetValue;
}
