/// Base exception for Access Engine domain and validation failures.
class AccessEngineException implements Exception {
  final String message;
  final String? code;
  final Object? cause;

  const AccessEngineException({
    required this.message,
    this.code,
    this.cause,
  });

  @override
  String toString() {
    if (code != null) {
      return 'AccessEngineException[$code]: $message';
    }
    return 'AccessEngineException: $message';
  }
}

/// Thrown when a free workout is supplied to authorize an app access grant.
class IneligibleWorkoutContextException extends AccessEngineException {
  const IneligibleWorkoutContextException({
    super.message =
        'Free workouts are voluntary exercises and are not eligible for app access grants.',
    super.cause,
  }) : super(code: 'INELIGIBLE_CONTEXT');
}

/// Thrown when a workout result is incomplete or has not reached target repetitions.
class IncompleteWorkoutResultException extends AccessEngineException {
  final int completedReps;
  final int? targetReps;

  const IncompleteWorkoutResultException(
    this.completedReps, {
    this.targetReps,
    super.message = 'Cannot grant access for an incomplete workout result.',
    super.cause,
  }) : super(code: 'INCOMPLETE_RESULT');

  @override
  String toString() {
    if (targetReps != null) {
      return 'IncompleteWorkoutResultException[INCOMPLETE_RESULT]: completed $completedReps of $targetReps required repetitions.';
    }
    return super.toString();
  }
}

/// Thrown when an access grant is attempted for an unsupported Android target package.
class UnsupportedAccessTargetException extends AccessEngineException {
  final String? targetPackage;

  const UnsupportedAccessTargetException(
    this.targetPackage, {
    super.cause,
  }) : super(
          code: 'UNSUPPORTED_TARGET',
          message:
              'Target package "$targetPackage" is not in the supported applications list.',
        );
}

/// Thrown when the requested access duration is zero or negative.
class InvalidAccessDurationException extends AccessEngineException {
  final int durationSeconds;

  const InvalidAccessDurationException(
    this.durationSeconds, {
    super.cause,
  }) : super(
          code: 'INVALID_DURATION',
          message:
              'Access duration must be positive, but was $durationSeconds seconds.',
        );
}

/// Thrown when attempting to grant access while Android Accessibility permission is missing.
class MissingAccessibilityPermissionException extends AccessEngineException {
  const MissingAccessibilityPermissionException({
    super.message =
        'Cannot grant access: Android Accessibility Service permission is not granted.',
    super.cause,
  }) : super(code: 'PERMISSION_MISSING');
}

/// Thrown when attempting to grant access while voluntary Focus restriction is disabled.
class FocusDisabledException extends AccessEngineException {
  const FocusDisabledException({
    super.message =
        'Cannot grant access: voluntary Focus restriction is currently disabled.',
    super.cause,
  }) : super(code: 'FOCUS_DISABLED');
}

/// Thrown when the target package of the workout does not match the active native target.
class TargetPackageMismatchException extends AccessEngineException {
  final String workoutTarget;
  final String nativeTarget;

  const TargetPackageMismatchException({
    required this.workoutTarget,
    required this.nativeTarget,
    super.cause,
  }) : super(
          code: 'TARGET_MISMATCH',
          message:
              'Workout target "$workoutTarget" does not match currently active native target "$nativeTarget".',
        );
}

/// Thrown when a grant request for the same session ID is already actively in-flight.
class ConcurrentGrantException extends AccessEngineException {
  final String sessionId;

  const ConcurrentGrantException(
    this.sessionId, {
    super.cause,
  }) : super(
          code: 'CONCURRENT_GRANT',
          message:
              'An access grant request for session "$sessionId" is already in progress.',
        );
}

/// Thrown when a platform channel error occurs during grantAccess.
class AccessEnginePlatformException extends AccessEngineException {
  const AccessEnginePlatformException({
    required super.message,
    super.code = 'PLATFORM_ERROR',
    super.cause,
  });
}
