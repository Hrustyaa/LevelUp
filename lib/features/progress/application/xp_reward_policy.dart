import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../models/challenge_type.dart';
import '../../../models/exercise_type.dart';
import '../../../models/workout_result.dart';
import '../../challenge/application/push_up_verification.dart';

/// Result of evaluating a [WorkoutResult] against [XpRewardPolicy].
class XpRewardDecision {
  final bool eligible;
  final int xpAmount;
  final String? rejectionReason;

  const XpRewardDecision({
    required this.eligible,
    required this.xpAmount,
    this.rejectionReason,
  });
}

/// Centralized, configurable MVP policy governing XP eligibility.
///
/// Provisional product rules:
/// - 50 XP for a genuinely completed, verified 5-repetition workout.
/// - Both completed Unlock Challenges and completed Free Workouts earn XP.
/// - Only explicit trusted verification sources ([allowedSources], default `{'camera'}`)
///   are eligible; unknown, empty, simulated, preview-only, or mock sessions earn 0 XP.
/// - Incomplete workouts (< [minimumRepetitions]) earn 0 XP.
/// - XP is strictly motivational and never affects native app access grants.
class XpRewardPolicy {
  static const int defaultBaseWorkoutXp = 50;
  static const int defaultMinimumRepetitions = 5;
  static const Set<String> defaultAllowedSources = {'camera'};
  static const _unverifiedSources = {
    'simulated',
    'preview',
    'ui_only',
    'mock',
    PushUpVerification.experimentalSource,
  };

  final int baseWorkoutXp;
  final int minimumRepetitions;
  final Set<String> allowedSources;
  final bool _validatedPushUps;

  const XpRewardPolicy({
    this.baseWorkoutXp = defaultBaseWorkoutXp,
    this.minimumRepetitions = defaultMinimumRepetitions,
    this.allowedSources = defaultAllowedSources,
  }) : _validatedPushUps = PushUpVerification.physicallyValidated;

  /// Exercises the future policy in an isolated test reward ledger.
  @visibleForTesting
  const XpRewardPolicy.withValidatedPushUpsForTest()
    : baseWorkoutXp = defaultBaseWorkoutXp,
      minimumRepetitions = defaultMinimumRepetitions,
      allowedSources = defaultAllowedSources,
      _validatedPushUps = true;

  XpRewardDecision evaluate(WorkoutResult result) {
    if (result.sessionId.trim().isEmpty) {
      return const XpRewardDecision(
        eligible: false,
        xpAmount: 0,
        rejectionReason: 'Empty sessionId',
      );
    }

    if (result.completedRepetitions < minimumRepetitions) {
      return XpRewardDecision(
        eligible: false,
        xpAmount: 0,
        rejectionReason:
            'Incomplete workout: ${result.completedRepetitions} < $minimumRepetitions reps',
      );
    }

    final normalizedSource = result.source.trim().toLowerCase();
    final trusted = result.exerciseType == ExerciseType.pushUp
        ? _validatedPushUps &&
              normalizedSource == PushUpVerification.verifiedSource
        : normalizedSource.isNotEmpty &&
              !_unverifiedSources.contains(normalizedSource) &&
              allowedSources.contains(normalizedSource) &&
              normalizedSource != PushUpVerification.verifiedSource;
    if (!trusted) {
      return XpRewardDecision(
        eligible: false,
        xpAmount: 0,
        rejectionReason: 'Untrusted verification source: "${result.source}"',
      );
    }

    if (result.challengeContext != ChallengeType.unlockChallenge &&
        result.challengeContext != ChallengeType.freeWorkout) {
      return XpRewardDecision(
        eligible: false,
        xpAmount: 0,
        rejectionReason:
            'Unsupported challenge context: ${result.challengeContext}',
      );
    }

    return XpRewardDecision(eligible: true, xpAmount: baseWorkoutXp);
  }
}
