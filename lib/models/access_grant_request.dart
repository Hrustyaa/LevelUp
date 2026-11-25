import 'package:flutter/foundation.dart';

import '../core/constants/channel_constants.dart';
import '../core/errors/access_exceptions.dart';
import '../features/challenge/data/challenge_catalog.dart';
import '../features/challenge/application/push_up_verification.dart';
import 'exercise_type.dart';
import 'challenge_type.dart';
import 'workout_result.dart';

/// Request model representing an intent to authorize temporary application access.
@immutable
class AccessGrantRequest {
  /// Session identifier of the completed workout.
  final String sessionId;

  /// Associated challenge definition identifier.
  final String challengeId;

  /// Target application package to unlock.
  final String targetPackage;

  /// Requested access duration in minutes (coerced to 1..15 by native contract).
  final int durationMinutes;

  /// Operational context of the completed workout.
  final ChallengeType challengeContext;

  /// Completion timestamp of the workout.
  final DateTime completedAt;

  AccessGrantRequest({
    required this.sessionId,
    required this.challengeId,
    required this.targetPackage,
    required this.durationMinutes,
    required this.challengeContext,
    required this.completedAt,
  }) {
    if (sessionId.trim().isEmpty) {
      throw const AccessEngineException(
        code: 'INVALID_SESSION_ID',
        message: 'sessionId must not be empty.',
      );
    }
    if (challengeContext != ChallengeType.unlockChallenge) {
      throw const IneligibleWorkoutContextException();
    }
    if (!ChannelConstants.allowedTargets.contains(targetPackage)) {
      throw UnsupportedAccessTargetException(targetPackage);
    }
    if (durationMinutes < 1 || durationMinutes > 15) {
      throw InvalidAccessDurationException(durationMinutes * 60);
    }
  }

  /// Factory constructor that builds and validates an [AccessGrantRequest]
  /// directly from an authoritative completed [WorkoutResult].
  ///
  /// Throws [IneligibleWorkoutContextException], [IncompleteWorkoutResultException],
  /// [UnsupportedAccessTargetException], or [InvalidAccessDurationException].
  factory AccessGrantRequest.fromWorkoutResult(WorkoutResult result) {
    if (result.challengeContext != ChallengeType.unlockChallenge ||
        !result.eligibleForAccess) {
      throw const IneligibleWorkoutContextException();
    }

    // Resolve authoritative definition from ChallengeCatalog
    final definition = ChallengeCatalog.byId[result.challengeId];
    if (definition == null) {
      throw IneligibleWorkoutContextException(
        message: 'Unknown challenge ID: "${result.challengeId}".',
      );
    }

    // Verify definition specifies app access
    if (definition.accessDurationSeconds <= 0) {
      throw IneligibleWorkoutContextException(
        message: 'Challenge "${result.challengeId}" does not grant access.',
      );
    }

    // Verify exercise type matches the authoritative definition
    if (result.exerciseType != definition.exerciseType) {
      throw IneligibleWorkoutContextException(
        message:
            'Exercise type "${result.exerciseType.name}" does not match definition "${definition.exerciseType.name}".',
      );
    }

    if (result.exerciseType == ExerciseType.pushUp &&
        !PushUpVerification.canGrantAccess(result.source)) {
      throw const IneligibleWorkoutContextException(
        message: 'Push-up verification is ineligible for app access.',
      );
    }

    // Strict repetition verification: verified reps must satisfy definition target
    if (result.completedRepetitions < definition.targetRepetitions) {
      throw IncompleteWorkoutResultException(
        result.completedRepetitions,
        targetReps: definition.targetRepetitions,
      );
    }

    final target = result.targetPackage;
    if (target == null || !ChannelConstants.allowedTargets.contains(target)) {
      throw UnsupportedAccessTargetException(target);
    }

    if (result.accessDurationSeconds != definition.accessDurationSeconds) {
      throw InvalidAccessDurationException(result.accessDurationSeconds);
    }

    final minutes = (result.accessDurationSeconds / 60).round().clamp(1, 15);

    return AccessGrantRequest(
      sessionId: result.sessionId,
      challengeId: result.challengeId,
      targetPackage: target,
      durationMinutes: minutes,
      challengeContext: result.challengeContext,
      completedAt: result.completedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'challengeId': challengeId,
      'targetPackage': targetPackage,
      'durationMinutes': durationMinutes,
      'challengeContext': challengeContext.name,
      'completedAt': completedAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccessGrantRequest &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          challengeId == other.challengeId &&
          targetPackage == other.targetPackage &&
          durationMinutes == other.durationMinutes &&
          challengeContext == other.challengeContext &&
          completedAt == other.completedAt;

  @override
  int get hashCode => Object.hash(
        sessionId,
        challengeId,
        targetPackage,
        durationMinutes,
        challengeContext,
        completedAt,
      );

  @override
  String toString() =>
      'AccessGrantRequest(session: $sessionId, target: $targetPackage, minutes: $durationMinutes)';
}
