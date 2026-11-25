import 'package:flutter/foundation.dart';

import '../core/integration/pose_event_adapter.dart';
import '../features/challenge/application/push_up_verification.dart';
import 'challenge_type.dart';
import 'exercise_type.dart';
import 'workout_result.dart';
import 'workout_session_status.dart';

/// Immutable domain model representing a physical workout session and its lifecycle.
@immutable
class WorkoutSession {
  /// Unique session identifier.
  final String sessionId;

  /// Originating challenge request identifier.
  final String requestId;

  /// Target challenge definition identifier.
  final String challengeId;

  /// Operational context (unlockChallenge or freeWorkout).
  final ChallengeType challengeContext;

  /// Targeted application package (null for free workouts).
  final String? targetPackage;

  /// Physical movement being performed.
  final ExerciseType exerciseType;

  /// Required number of verified repetitions to complete the session.
  final int targetRepetitions;

  /// Current number of verified repetitions completed.
  final int verifiedRepetitions;

  /// Timestamp when active exercise started.
  final DateTime? startedAt;

  /// Timestamp when session reached a terminal state (completed, cancelled, or failed).
  final DateTime? completedAt;

  /// Current lifecycle state.
  final WorkoutSessionStatus status;

  /// Human-readable explanation if status is [WorkoutSessionStatus.failed].
  final String? failureReason;

  /// Screen-time access duration in seconds to grant upon completion (0 for free workouts).
  final int accessDurationSeconds;

  /// Experience points reward upon completion.
  final int xpReward;

  const WorkoutSession({
    required this.sessionId,
    required this.requestId,
    required this.challengeId,
    required this.challengeContext,
    this.targetPackage,
    required this.exerciseType,
    required this.targetRepetitions,
    this.verifiedRepetitions = 0,
    this.startedAt,
    this.completedAt,
    this.status = WorkoutSessionStatus.created,
    this.failureReason,
    this.accessDurationSeconds = 0,
    this.xpReward = 50,
  });

  /// True when the user has satisfied all required repetitions.
  bool get isRepetitionGoalAchieved => verifiedRepetitions >= targetRepetitions;

  /// Elapsed duration of the workout session.
  Duration get duration {
    if (startedAt == null) return Duration.zero;
    final end = completedAt ?? DateTime.now();
    final diff = end.difference(startedAt!);
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Converts a successfully completed session into a structured [WorkoutResult].
  ///
  /// Throws [StateError] if session is not in [WorkoutSessionStatus.completed] status.
  WorkoutResult toWorkoutResult({
    String? source,
    CameraWorkoutCompletion? cameraCompletion,
  }) {
    if (status != WorkoutSessionStatus.completed) {
      throw StateError(
        'Cannot convert session "$sessionId" to WorkoutResult: status is $status (expected completed).',
      );
    }

    final isUnlock = challengeContext == ChallengeType.unlockChallenge;
    final resolvedSource = source ??
        (exerciseType == ExerciseType.pushUp
            ? PushUpVerification.experimentalSource
            : 'camera');

    return WorkoutResult(
      sessionId: sessionId,
      requestId: requestId,
      challengeId: challengeId,
      challengeContext: challengeContext,
      exerciseType: exerciseType,
      targetPackage: isUnlock ? targetPackage : null,
      completedRepetitions: verifiedRepetitions,
      duration: duration,
      completedAt: completedAt ?? DateTime.now(),
      eligibleForAccess: isUnlock,
      accessDurationSeconds: isUnlock ? accessDurationSeconds : 0,
      earnedXp: resolvedSource == 'simulated' ||
              (exerciseType == ExerciseType.pushUp &&
                  (cameraCompletion == null ||
                      resolvedSource != PushUpVerification.verifiedSource))
          ? 0
          : xpReward,
      source: resolvedSource,
      cameraCompletion: cameraCompletion,
    );
  }

  /// Creates a copy of this session with the given fields replaced.
  WorkoutSession copyWith({
    int? verifiedRepetitions,
    DateTime? startedAt,
    DateTime? completedAt,
    WorkoutSessionStatus? status,
    String? failureReason,
  }) {
    return WorkoutSession(
      sessionId: sessionId,
      requestId: requestId,
      challengeId: challengeId,
      challengeContext: challengeContext,
      targetPackage: targetPackage,
      exerciseType: exerciseType,
      targetRepetitions: targetRepetitions,
      verifiedRepetitions: verifiedRepetitions ?? this.verifiedRepetitions,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      accessDurationSeconds: accessDurationSeconds,
      xpReward: xpReward,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'requestId': requestId,
      'challengeId': challengeId,
      'challengeContext': challengeContext.name,
      'targetPackage': targetPackage,
      'exerciseType': exerciseType.name,
      'targetRepetitions': targetRepetitions,
      'verifiedRepetitions': verifiedRepetitions,
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'status': status.name,
      'failureReason': failureReason,
      'accessDurationSeconds': accessDurationSeconds,
      'xpReward': xpReward,
      'durationMs': duration.inMilliseconds,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutSession &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          requestId == other.requestId &&
          challengeId == other.challengeId &&
          challengeContext == other.challengeContext &&
          targetPackage == other.targetPackage &&
          exerciseType == other.exerciseType &&
          targetRepetitions == other.targetRepetitions &&
          verifiedRepetitions == other.verifiedRepetitions &&
          startedAt == other.startedAt &&
          completedAt == other.completedAt &&
          status == other.status &&
          failureReason == other.failureReason &&
          accessDurationSeconds == other.accessDurationSeconds &&
          xpReward == other.xpReward;

  @override
  int get hashCode => Object.hash(
        sessionId,
        requestId,
        challengeId,
        challengeContext,
        exerciseType,
        targetRepetitions,
        verifiedRepetitions,
        startedAt,
        completedAt,
        status,
        failureReason,
        accessDurationSeconds,
        xpReward,
      );

  @override
  String toString() =>
      'WorkoutSession(id: $sessionId, status: $status, reps: $verifiedRepetitions/$targetRepetitions, context: $challengeContext)';
}
