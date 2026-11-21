import 'package:flutter/foundation.dart';

import '../core/errors/challenge_exceptions.dart';
import 'challenge_reward.dart';
import 'exercise_type.dart';

/// Immutable definition of a physical challenge configuration.
@immutable
class ChallengeDefinition {
  /// Unique identifier of the challenge (e.g. 'squats_unlock_5', 'squats_free_5').
  final String challengeId;

  /// Type of exercise required (e.g. squats).
  final ExerciseType exerciseType;

  /// Human-readable title (e.g. '5 Squats Unlock').
  final String title;

  /// Detailed instructions and description for the user.
  final String description;

  /// Number of verified repetitions required to successfully complete the challenge.
  final int targetRepetitions;

  /// Duration of screen-time access in seconds if completed as an unlock challenge.
  /// (0 for free workouts).
  final int accessDurationSeconds;

  /// Optional experience points reward metadata.
  final int? optionalXpReward;

  const ChallengeDefinition({
    required this.challengeId,
    required this.exerciseType,
    required this.title,
    required this.description,
    required this.targetRepetitions,
    this.accessDurationSeconds = 0,
    this.optionalXpReward,
  });

  /// Validates definition fields and throws [InvalidChallengeDefinitionException] on violations.
  void validate() {
    if (challengeId.trim().isEmpty) {
      throw const InvalidChallengeDefinitionException('challengeId must not be empty.');
    }
    if (title.trim().isEmpty) {
      throw const InvalidChallengeDefinitionException('title must not be empty.');
    }
    if (targetRepetitions <= 0) {
      throw InvalidChallengeDefinitionException(
        'targetRepetitions must be positive, but was $targetRepetitions.',
      );
    }
    if (accessDurationSeconds < 0) {
      throw InvalidChallengeDefinitionException(
        'accessDurationSeconds must be non-negative, but was $accessDurationSeconds.',
      );
    }
    if (optionalXpReward != null && optionalXpReward! < 0) {
      throw InvalidChallengeDefinitionException(
        'optionalXpReward must be non-negative, but was $optionalXpReward.',
      );
    }
  }

  /// Returns [ChallengeReward] metadata descriptor for this definition.
  ChallengeReward toReward({required bool isUnlockContext}) {
    if (isUnlockContext && accessDurationSeconds > 0) {
      return ChallengeReward.unlock(
        accessDurationSeconds: accessDurationSeconds,
        xpAmount: optionalXpReward ?? 50,
      );
    }
    return ChallengeReward.freeWorkout(
      xpAmount: optionalXpReward ?? 50,
    );
  }

  /// Access duration represented as [Duration].
  Duration get accessDuration => Duration(seconds: accessDurationSeconds);

  Map<String, dynamic> toMap() {
    return {
      'challengeId': challengeId,
      'exerciseType': exerciseType.name,
      'title': title,
      'description': description,
      'targetRepetitions': targetRepetitions,
      'accessDurationSeconds': accessDurationSeconds,
      'optionalXpReward': optionalXpReward,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeDefinition &&
          runtimeType == other.runtimeType &&
          challengeId == other.challengeId &&
          exerciseType == other.exerciseType &&
          title == other.title &&
          description == other.description &&
          targetRepetitions == other.targetRepetitions &&
          accessDurationSeconds == other.accessDurationSeconds &&
          optionalXpReward == other.optionalXpReward;

  @override
  int get hashCode => Object.hash(
        challengeId,
        exerciseType,
        title,
        description,
        targetRepetitions,
        accessDurationSeconds,
        optionalXpReward,
      );

  @override
  String toString() =>
      'ChallengeDefinition(id: $challengeId, type: $exerciseType, reps: $targetRepetitions, accessSec: $accessDurationSeconds)';
}
