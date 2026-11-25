import '../../../models/challenge_definition.dart';
import '../../../models/exercise_type.dart';
import '../application/push_up_verification.dart';

/// Centralized catalog containing all valid challenge definitions in LevelUp.
///
/// Ensures challenge parameters (reps, access duration) are defined deterministically
/// in one place rather than scattered across Flutter UI widgets.
abstract final class ChallengeCatalog {
  /// Challenge ID for the standard 5-squat app unlock challenge.
  static const String squatUnlockId = 'squats_unlock_5';

  /// Challenge ID for the standard 5-squat voluntary free workout.
  static const String squatFreeWorkoutId = 'squats_free_5';

  /// Challenge ID for the standard 5-push-up voluntary free workout.
  static const String pushUpFreeWorkoutId = 'pushup_free_5';

  static const String pushUpUnlockId = 'pushup_unlock_5';

  static const ChallengeDefinition pushUpUnlockChallenge = ChallengeDefinition(
    challengeId: pushUpUnlockId,
    exerciseType: ExerciseType.pushUp,
    title: '5 Push-ups Unlock',
    description: 'Complete 5 front-facing push-ups for 5 minutes of access.',
    targetRepetitions: 5,
    accessDurationSeconds: 300,
    optionalXpReward: 50,
  );

  /// Default 5-squat unlock challenge granting 5 calendar minutes of access.
  static const ChallengeDefinition squatUnlockChallenge = ChallengeDefinition(
    challengeId: squatUnlockId,
    exerciseType: ExerciseType.squats,
    title: '5 Squats Unlock',
    description:
        'Complete 5 full bodyweight squats in front of the camera to unlock 5 minutes of screen time.',
    targetRepetitions: 5,
    accessDurationSeconds: 300, // 5 minutes * 60 seconds
    optionalXpReward: 50,
  );

  /// Default 5-squat free workout without an app-unlock grant.
  static const ChallengeDefinition squatFreeWorkout = ChallengeDefinition(
    challengeId: squatFreeWorkoutId,
    exerciseType: ExerciseType.squats,
    title: '5 Squats Quick Set',
    description:
        'Complete 5 full bodyweight squats for daily exercise and habit progression.',
    targetRepetitions: 5,
    accessDurationSeconds: 0,
    optionalXpReward: 50,
  );

  /// Default 5-push-up free workout without an app-unlock grant.
  static const ChallengeDefinition pushUpFreeWorkout = ChallengeDefinition(
    challengeId: pushUpFreeWorkoutId,
    exerciseType: ExerciseType.pushUp,
    title: '5 Push-ups Quick Set',
    description:
        'Complete 5 front-facing push-ups for daily exercise and habit progression.',
    targetRepetitions: 5,
    accessDurationSeconds: 0,
    optionalXpReward: 50,
  );

  /// All supported challenge definitions for the competition MVP.
  static const List<ChallengeDefinition> all = [
    squatUnlockChallenge,
    squatFreeWorkout,
    pushUpFreeWorkout,
    if (PushUpVerification.unlockEnabled) pushUpUnlockChallenge,
  ];

  /// Fast lookup map by challengeId.
  static final Map<String, ChallengeDefinition> byId = {
    for (final def in all) def.challengeId: def,
  };
}
