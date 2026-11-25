import 'package:flutter/foundation.dart';

import '../core/integration/pose_event_adapter.dart';
import '../features/challenge/application/push_up_verification.dart';
import 'challenge_type.dart';
import 'exercise_type.dart';

/// Structured outcome record of a successfully completed physical workout session.
///
/// Designed to be consumed downstream by Access Engine (for unlocking apps)
/// and Progress Engine (for recording streaks and awarding XP).
@immutable
final class WorkoutResult {
  /// Unique identifier of the session.
  final String sessionId;

  /// Originating challenge request identifier.
  final String requestId;

  /// Associated challenge definition identifier.
  final String challengeId;

  /// Operational context (unlockChallenge or freeWorkout).
  final ChallengeType challengeContext;

  /// Physical movement performed.
  final ExerciseType exerciseType;

  /// Targeted application package (null for free workouts).
  final String? targetPackage;

  /// Number of verified completed repetitions.
  final int completedRepetitions;

  /// Elapsed duration of active exercise.
  final Duration duration;

  /// Timestamp of session completion.
  final DateTime completedAt;

  /// Whether this completion authorizes an Android app access grant.
  /// Strictly false for [ChallengeType.freeWorkout].
  final bool eligibleForAccess;

  /// Screen-time access duration in seconds earned (0 for free workouts).
  final int accessDurationSeconds;

  /// Base experience points earned for completing the workout.
  final int earnedXp;

  /// Biomechanical verification source (e.g. 'camera', 'test').
  final String source;
  final CameraWorkoutCompletion? cameraCompletion;

  bool get hasVerifiedPushUpCompletion =>
      exerciseType == ExerciseType.pushUp && hasVerifiedCameraCompletion;

  bool get hasVerifiedCameraCompletion =>
      source == (exerciseType == ExerciseType.pushUp
          ? PushUpVerification.verifiedSource
          : 'camera') &&
      cameraCompletion?.identity == (
        sessionId: sessionId,
        requestId: requestId,
        challengeId: challengeId,
        exerciseType: exerciseType,
        targetPackage: targetPackage,
        repetitions: completedRepetitions,
      );

  WorkoutResult({
    required this.sessionId,
    required this.requestId,
    required this.challengeId,
    required this.challengeContext,
    required this.exerciseType,
    this.targetPackage,
    required this.completedRepetitions,
    required this.duration,
    required this.completedAt,
    required this.eligibleForAccess,
    required this.accessDurationSeconds,
    this.earnedXp = 50,
    this.source = 'camera',
    CameraWorkoutCompletion? cameraCompletion,
    PushUpCompletion? pushUpCompletion,
  })  : cameraCompletion = cameraCompletion ?? pushUpCompletion,
        assert(
          challengeContext != ChallengeType.freeWorkout ||
              (!eligibleForAccess && accessDurationSeconds == 0 && targetPackage == null),
          'Free workout must never produce an access grant or have a target package',
        ),
        assert(
          challengeContext != ChallengeType.unlockChallenge ||
              (eligibleForAccess && targetPackage != null && targetPackage.isNotEmpty),
          'Unlock challenge must have an eligible target package',
        ) {
    // Runtime checks ensuring release builds enforce the same invariants
    if (challengeContext == ChallengeType.freeWorkout &&
        (eligibleForAccess || accessDurationSeconds != 0 || targetPackage != null)) {
      throw ArgumentError(
        'Free workout must never produce an access grant or have a target package.',
      );
    }
    if (challengeContext == ChallengeType.unlockChallenge &&
        (!eligibleForAccess || targetPackage == null || targetPackage!.isEmpty)) {
      throw ArgumentError(
        'Unlock challenge must have an eligible target package and authorization flag.',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'requestId': requestId,
      'challengeId': challengeId,
      'challengeContext': challengeContext.name,
      'exerciseType': exerciseType.name,
      'targetPackage': targetPackage,
      'completedRepetitions': completedRepetitions,
      'durationMs': duration.inMilliseconds,
      'completedAt': completedAt.toIso8601String(),
      'eligibleForAccess': eligibleForAccess,
      'accessDurationSeconds': accessDurationSeconds,
      'earnedXp': earnedXp,
      'source': source,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutResult &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          requestId == other.requestId &&
          challengeId == other.challengeId &&
          challengeContext == other.challengeContext &&
          exerciseType == other.exerciseType &&
          targetPackage == other.targetPackage &&
          completedRepetitions == other.completedRepetitions &&
          duration == other.duration &&
          completedAt == other.completedAt &&
          eligibleForAccess == other.eligibleForAccess &&
          accessDurationSeconds == other.accessDurationSeconds &&
          earnedXp == other.earnedXp &&
          source == other.source;

  @override
  int get hashCode => Object.hash(
        sessionId,
        requestId,
        challengeId,
        challengeContext,
        exerciseType,
        targetPackage,
        completedRepetitions,
        duration,
        completedAt,
        eligibleForAccess,
        accessDurationSeconds,
        earnedXp,
      );

  @override
  String toString() =>
      'WorkoutResult(session: $sessionId, exercise: $exerciseType, reps: $completedRepetitions, access: $eligibleForAccess, duration: $duration)';
}
