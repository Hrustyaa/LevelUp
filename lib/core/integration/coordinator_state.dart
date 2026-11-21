import 'package:flutter/foundation.dart';

import '../../models/access_attempt_state.dart';
import '../../models/access_grant_status.dart';
import '../../models/challenge_definition.dart';
import '../../models/challenge_type.dart';
import '../../models/native_permission_status.dart';
import '../../models/workout_session.dart';
import '../../models/workout_session_status.dart';

/// Immutable snapshot representing the full application-level workflow state
/// of the Core Integration Coordinator.
@immutable
class CoordinatorState {
  /// The active or most recent challenge definition.
  final ChallengeDefinition? challenge;

  /// The operational context (unlockChallenge vs freeWorkout).
  final ChallengeType? challengeContext;

  /// Unique identifier of the current workout session.
  final String? sessionId;

  /// Current lifecycle status of the workout session.
  final WorkoutSessionStatus sessionStatus;

  /// Current verified physical repetitions completed.
  final int verifiedRepetitions;

  /// Target repetitions required to complete the challenge.
  final int targetRepetitions;

  /// Current Android Accessibility service permission status.
  final NativePermissionStatus permissionStatus;

  /// Currently selected target application package to restrict/unlock.
  final String? selectedTarget;

  /// Whether the voluntary Focus restriction gate is active.
  final bool isFocusEnabled;

  /// Current temporary access grant authorization status.
  final AccessGrantStatus? accessGrantStatus;

  /// Authoritative expiration timestamp of active temporary access.
  final DateTime? unlockUntil;

  /// Whether the completed workout result has been saved to SQLite history.
  final bool isWorkoutPersisted;

  /// Current state of the access attempt audit record in SQLite.
  final AccessAttemptState? accessAttemptState;

  /// Real-time posture feedback message for the user.
  final String? feedbackMessage;

  /// Latest knee angle detected by pose tracking.
  final double? lastKneeAngle;

  /// Human-readable error message if an operation failed.
  final String? errorMessage;

  const CoordinatorState({
    this.challenge,
    this.challengeContext,
    this.sessionId,
    this.sessionStatus = WorkoutSessionStatus.created,
    this.verifiedRepetitions = 0,
    this.targetRepetitions = 5,
    this.permissionStatus = const NativePermissionStatus(isAccessibilityGranted: false),
    this.selectedTarget,
    this.isFocusEnabled = false,
    this.accessGrantStatus,
    this.unlockUntil,
    this.isWorkoutPersisted = false,
    this.accessAttemptState,
    this.feedbackMessage,
    this.lastKneeAngle,
    this.errorMessage,
  });

  /// True when Android Accessibility permission is granted.
  bool get isAccessibilityGranted => permissionStatus.isAccessibilityGranted;

  /// Initial idle state before any challenge is launched.
  factory CoordinatorState.initial() => const CoordinatorState();

  /// Creates a state updated from a live [WorkoutSession].
  CoordinatorState copyWithSession(
    WorkoutSession session, {
    ChallengeDefinition? challenge,
    String? feedbackMessage,
    double? lastKneeAngle,
    String? errorMessage,
  }) {
    return copyWith(
      challenge: challenge ?? this.challenge,
      challengeContext: session.challengeContext,
      sessionId: session.sessionId,
      sessionStatus: session.status,
      verifiedRepetitions: session.verifiedRepetitions,
      targetRepetitions: session.targetRepetitions,
      selectedTarget: session.targetPackage ?? selectedTarget,
      feedbackMessage: feedbackMessage ?? this.feedbackMessage,
      lastKneeAngle: lastKneeAngle ?? this.lastKneeAngle,
      errorMessage: errorMessage,
    );
  }

  /// Copies this state with specified fields replaced.
  CoordinatorState copyWith({
    ChallengeDefinition? challenge,
    ChallengeType? challengeContext,
    String? sessionId,
    WorkoutSessionStatus? sessionStatus,
    int? verifiedRepetitions,
    int? targetRepetitions,
    NativePermissionStatus? permissionStatus,
    String? selectedTarget,
    bool? isFocusEnabled,
    AccessGrantStatus? accessGrantStatus,
    DateTime? unlockUntil,
    bool? isWorkoutPersisted,
    AccessAttemptState? accessAttemptState,
    String? feedbackMessage,
    double? lastKneeAngle,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CoordinatorState(
      challenge: challenge ?? this.challenge,
      challengeContext: challengeContext ?? this.challengeContext,
      sessionId: sessionId ?? this.sessionId,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      verifiedRepetitions: verifiedRepetitions ?? this.verifiedRepetitions,
      targetRepetitions: targetRepetitions ?? this.targetRepetitions,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      selectedTarget: selectedTarget ?? this.selectedTarget,
      isFocusEnabled: isFocusEnabled ?? this.isFocusEnabled,
      accessGrantStatus: accessGrantStatus ?? this.accessGrantStatus,
      unlockUntil: unlockUntil ?? this.unlockUntil,
      isWorkoutPersisted: isWorkoutPersisted ?? this.isWorkoutPersisted,
      accessAttemptState: accessAttemptState ?? this.accessAttemptState,
      feedbackMessage: feedbackMessage ?? this.feedbackMessage,
      lastKneeAngle: lastKneeAngle ?? this.lastKneeAngle,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoordinatorState &&
          runtimeType == other.runtimeType &&
          challenge == other.challenge &&
          challengeContext == other.challengeContext &&
          sessionId == other.sessionId &&
          sessionStatus == other.sessionStatus &&
          verifiedRepetitions == other.verifiedRepetitions &&
          targetRepetitions == other.targetRepetitions &&
          permissionStatus == other.permissionStatus &&
          selectedTarget == other.selectedTarget &&
          isFocusEnabled == other.isFocusEnabled &&
          accessGrantStatus == other.accessGrantStatus &&
          unlockUntil == other.unlockUntil &&
          isWorkoutPersisted == other.isWorkoutPersisted &&
          accessAttemptState == other.accessAttemptState &&
          feedbackMessage == other.feedbackMessage &&
          lastKneeAngle == other.lastKneeAngle &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        challenge,
        challengeContext,
        sessionId,
        sessionStatus,
        verifiedRepetitions,
        targetRepetitions,
        permissionStatus,
        selectedTarget,
        isFocusEnabled,
        accessGrantStatus,
        unlockUntil,
        isWorkoutPersisted,
        accessAttemptState,
        feedbackMessage,
        lastKneeAngle,
        errorMessage,
      );

  @override
  String toString() =>
      'CoordinatorState(session: $sessionId, status: $sessionStatus, reps: $verifiedRepetitions/$targetRepetitions, focus: $isFocusEnabled, access: $accessGrantStatus)';
}
