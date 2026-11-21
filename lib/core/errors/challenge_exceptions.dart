/// Base exception for Challenge Engine domain and validation failures.
class ChallengeEngineException implements Exception {
  final String message;
  final String? code;
  final Object? cause;

  const ChallengeEngineException({
    required this.message,
    this.code,
    this.cause,
  });

  @override
  String toString() {
    if (code != null) {
      return 'ChallengeEngineException[$code]: $message';
    }
    return 'ChallengeEngineException: $message';
  }
}

/// Thrown when a challenge definition configuration is invalid (e.g. non-positive reps).
class InvalidChallengeDefinitionException extends ChallengeEngineException {
  const InvalidChallengeDefinitionException(
    String message, {
    super.cause,
  }) : super(
          code: 'INVALID_DEFINITION',
          message: message,
        );
}

/// Thrown when a challenge request violates context, target, or configuration rules.
class InvalidChallengeRequestException extends ChallengeEngineException {
  const InvalidChallengeRequestException(
    String message, {
    super.cause,
  }) : super(
          code: 'INVALID_REQUEST',
          message: message,
        );
}

/// Thrown when a requested challenge definition identifier is not found in the catalog.
class UnknownChallengeException extends ChallengeEngineException {
  final String challengeId;

  const UnknownChallengeException(
    this.challengeId, {
    super.cause,
  }) : super(
          code: 'UNKNOWN_CHALLENGE',
          message: 'Challenge definition with id "$challengeId" was not found in catalog.',
        );
}

/// Thrown when a target package is unsupported or not in allowed list for unlock challenges.
class UnsupportedChallengeTargetException extends ChallengeEngineException {
  final String targetPackage;

  const UnsupportedChallengeTargetException(
    this.targetPackage, {
    super.cause,
  }) : super(
          code: 'UNSUPPORTED_TARGET',
          message: 'Target package "$targetPackage" is not supported for unlock challenges.',
        );
}
