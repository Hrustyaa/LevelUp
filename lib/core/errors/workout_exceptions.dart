/// Base exception for workout session lifecycle and progression errors.
class WorkoutSessionException implements Exception {
  final String message;
  final String? code;
  final Object? cause;

  const WorkoutSessionException({
    required this.message,
    this.code,
    this.cause,
  });

  @override
  String toString() {
    if (code != null) {
      return 'WorkoutSessionException[$code]: $message';
    }
    return 'WorkoutSessionException: $message';
  }
}

/// Thrown when an illegal state transition is attempted (e.g. completed -> active).
class InvalidSessionTransitionException extends WorkoutSessionException {
  const InvalidSessionTransitionException(
    String message, {
    super.cause,
  }) : super(
          code: 'INVALID_TRANSITION',
          message: message,
        );
}

/// Thrown when an operation targets a session ID that is unknown or does not match active session.
class UnknownSessionException extends WorkoutSessionException {
  final String sessionId;

  const UnknownSessionException(
    this.sessionId, {
    super.cause,
  }) : super(
          code: 'UNKNOWN_SESSION',
          message: 'Workout session "$sessionId" does not exist or is not loaded.',
        );
}

/// Thrown when attempting to create a new session while an active workout is already in progress.
class SessionAlreadyActiveException extends WorkoutSessionException {
  final String activeSessionId;

  const SessionAlreadyActiveException(
    this.activeSessionId, {
    super.cause,
  }) : super(
          code: 'SESSION_ALREADY_ACTIVE',
          message:
              'A workout session is already in progress ("$activeSessionId"). Complete or cancel it first.',
        );
}

/// Thrown when attempting to complete a session before verified repetitions reach target goal.
class IncompleteWorkoutException extends WorkoutSessionException {
  final int verified;
  final int target;

  const IncompleteWorkoutException(
    this.verified,
    this.target, {
    super.cause,
  }) : super(
          code: 'INCOMPLETE_WORKOUT',
          message:
              'Cannot complete session: verified repetitions ($verified) have not reached target ($target).',
        );
}

/// Thrown when an operation is attempted on a session that has already been cancelled or failed.
class SessionTerminatedException extends WorkoutSessionException {
  final String statusName;

  const SessionTerminatedException(
    this.statusName, {
    super.cause,
  }) : super(
          code: 'SESSION_TERMINATED',
          message:
              'Cannot update or complete session: session has already terminated with status "$statusName".',
        );
}

/// Thrown when progress values are invalid (e.g. negative repetitions).
class InvalidProgressException extends WorkoutSessionException {
  const InvalidProgressException(
    String message, {
    super.cause,
  }) : super(
          code: 'INVALID_PROGRESS',
          message: message,
        );
}
