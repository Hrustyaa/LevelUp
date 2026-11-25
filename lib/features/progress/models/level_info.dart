import 'package:flutter/foundation.dart';

/// Deterministic user level snapshot derived from cumulative XP.
@immutable
class LevelInfo {
  final int totalXp;
  final int level;
  final int xpIntoCurrentLevel;
  final int xpRequiredForNextLevel;
  final double progressFraction;

  const LevelInfo({
    required this.totalXp,
    required this.level,
    required this.xpIntoCurrentLevel,
    required this.xpRequiredForNextLevel,
    required this.progressFraction,
  });

  factory LevelInfo.initial() => const LevelInfo(
        totalXp: 0,
        level: 1,
        xpIntoCurrentLevel: 0,
        xpRequiredForNextLevel: 100,
        progressFraction: 0.0,
      );

  int get xpRemainingToNextLevel =>
      (xpRequiredForNextLevel - xpIntoCurrentLevel).clamp(0, xpRequiredForNextLevel);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LevelInfo &&
          runtimeType == other.runtimeType &&
          totalXp == other.totalXp &&
          level == other.level &&
          xpIntoCurrentLevel == other.xpIntoCurrentLevel &&
          xpRequiredForNextLevel == other.xpRequiredForNextLevel &&
          progressFraction == other.progressFraction;

  @override
  int get hashCode => Object.hash(
        totalXp,
        level,
        xpIntoCurrentLevel,
        xpRequiredForNextLevel,
        progressFraction,
      );
}
