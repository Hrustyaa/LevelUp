import '../../models/access_attempt_state.dart';

/// Base exception for all LevelUp local database and persistence failures.
class PersistenceException implements Exception {
  final String message;
  final String? code;
  final Object? cause;

  const PersistenceException({
    required this.message,
    this.code,
    this.cause,
  });

  @override
  String toString() {
    if (code != null) {
      return 'PersistenceException[$code]: $message';
    }
    return 'PersistenceException: $message';
  }
}

/// Thrown when attempting to save a workout or access attempt whose ID already exists.
class DuplicateSessionException extends PersistenceException {
  final String sessionId;

  const DuplicateSessionException(
    this.sessionId, {
    super.message = 'A record with this session ID already exists.',
    super.cause,
  }) : super(code: 'DUPLICATE_SESSION');
}

/// Thrown when attempting to overwrite an existing session record with conflicting data.
class ConflictingWorkoutRecordException extends PersistenceException {
  final String sessionId;

  const ConflictingWorkoutRecordException(
    this.sessionId, {
    super.message =
        'Cannot overwrite existing workout session with conflicting payload.',
    super.cause,
  }) : super(code: 'CONFLICTING_RECORD');
}

/// Thrown when attempting to create an access attempt with a conflicting payload for an existing session.
class ConflictingAccessAttemptException extends PersistenceException {
  final String sessionId;

  const ConflictingAccessAttemptException(
    this.sessionId, {
    super.message =
        'Cannot create access attempt with conflicting payload for existing session.',
    super.cause,
  }) : super(code: 'CONFLICTING_ACCESS_ATTEMPT');
}

/// Thrown when an illegal state transition is attempted on an access attempt.
class InvalidStateTransitionException extends PersistenceException {
  final String sessionId;
  final AccessAttemptState from;
  final AccessAttemptState to;

  const InvalidStateTransitionException({
    required this.sessionId,
    required this.from,
    required this.to,
    required super.message,
    super.cause,
  }) : super(code: 'INVALID_STATE_TRANSITION');
}

/// Thrown when a requested persistence record is not found.
class RecordNotFoundException extends PersistenceException {
  final String id;

  const RecordNotFoundException(
    this.id, {
    super.message = 'Record was not found.',
    super.cause,
  }) : super(code: 'NOT_FOUND');
}

/// Thrown when data to be persisted violates domain constraints or schema invariants.
class InvalidWorkoutDataException extends PersistenceException {
  const InvalidWorkoutDataException(
    String message, {
    super.cause,
  }) : super(
          message: message,
          code: 'INVALID_DATA',
        );
}

/// Thrown when a database schema migration fails.
class DatabaseMigrationException extends PersistenceException {
  final int fromVersion;
  final int toVersion;

  const DatabaseMigrationException({
    required this.fromVersion,
    required this.toVersion,
    required super.message,
    super.cause,
  }) : super(code: 'MIGRATION_ERROR');
}
