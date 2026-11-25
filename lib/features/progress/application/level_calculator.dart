import 'dart:math' as math;

import '../models/level_info.dart';

/// Deterministic calculator for user levels and progress fractions.
///
/// Rules:
/// - Level 1 starts at 0 XP and requires [baseLevelStep] (100 XP) to reach Level 2.
/// - Each subsequent level requires [baseLevelStep] additional XP:
///   Level 1 -> 2: 100 XP (cumulative 100)
///   Level 2 -> 3: 200 XP (cumulative 300)
///   Level 3 -> 4: 300 XP (cumulative 600)
///   Cumulative floor for level L: 50 * (L - 1) * L
class LevelCalculator {
  static const int defaultStepXp = 100;

  final int stepXp;

  const LevelCalculator({this.stepXp = defaultStepXp});

  LevelInfo calculate(int rawTotalXp) {
    final totalXp = rawTotalXp < 0 ? 0 : rawTotalXp;
    if (stepXp <= 0) {
      return LevelInfo.initial();
    }

    // Closed-form initial estimate using quadratic formula on triangular numbers:
    // (stepXp / 2) * (L - 1) * L <= totalXp  =>  L^2 - L - (2 * totalXp / stepXp) <= 0
    final scaled = (2.0 * totalXp) / stepXp;
    var level = ((1.0 + math.sqrt(1.0 + 4.0 * scaled)) / 2.0).floor();
    if (level < 1) level = 1;

    // Exact integer adjustment to avoid any floating-point boundary drift.
    while (_cumulativeFloor(level + 1) <= totalXp) {
      level++;
    }
    while (level > 1 && _cumulativeFloor(level) > totalXp) {
      level--;
    }

    final floor = _cumulativeFloor(level);
    final requiredForNext = level * stepXp;
    final intoLevel = (totalXp - floor).clamp(0, requiredForNext);
    final fraction = requiredForNext > 0
        ? (intoLevel / requiredForNext).clamp(0.0, 1.0)
        : 0.0;

    return LevelInfo(
      totalXp: totalXp,
      level: level,
      xpIntoCurrentLevel: intoLevel,
      xpRequiredForNextLevel: requiredForNext,
      progressFraction: fraction,
    );
  }

  int _cumulativeFloor(int level) => (stepXp * (level - 1) * level) ~/ 2;
}
