import 'dart:async';

import '../../../core/errors/workout_exceptions.dart';
import '../../../models/workout_result.dart';
import '../../../models/workout_session.dart';
import '../../../models/workout_session_status.dart';
import 'challenge_service.dart';

export '../../../core/errors/workout_exceptions.dart';
export '../../../models/workout_result.dart';
export '../../../models/workout_session.dart';
export '../../../models/workout_session_status.dart';

/// Contract for orchestrating the lifecycle and repetition progress of workout sessions.
abstract class IWorkoutSessionManager {
  /// The active or most recently managed workout session, or null if uninitialized.
  WorkoutSession? get currentSession;

  /// Reactive broadcast stream of [WorkoutSession] state changes.
  Stream<WorkoutSession> get sessionStream;

  /// Creates a new workout session from a validated [ChallengeRequest].
  ///
  /// Throws [SessionAlreadyActiveException] if an unfinished session is already running.
  WorkoutSession createSession(ChallengeRequest request);

  /// Transitions session to preparing state (e.g. countdown / user positioning).
  ///
  /// Throws [UnknownSessionException] if session is not found.
  /// Throws [InvalidSessionTransitionException] if transition is not allowed.
  WorkoutSession prepareSession(String sessionId);

  /// Transitions session to active tracking state.
  ///
  /// Sets `startedAt` timestamp.
  /// Throws [UnknownSessionException] if session is not found.
  /// Throws [InvalidSessionTransitionException] if transition is not allowed.
  WorkoutSession startSession(String sessionId);

  /// Updates verified repetition progress from SquatCounter.
  ///
  /// Automatically completes the session when target repetitions are achieved.
  /// Throws [UnknownSessionException] if session is not found.
  /// Throws [SessionTerminatedException] if session was cancelled or failed.
  /// Throws [InvalidProgressException] if cumulative repetitions are negative.
  WorkoutSession updateVerifiedProgress(
    String sessionId, {
    required int cumulativeReps,
    String? eventId,
  });

  /// Explicitly completes an active session after target repetitions have been satisfied.
  ///
  /// Returns a structured [WorkoutResult].
  /// Idempotent: returns existing result if already completed.
  /// Throws [IncompleteWorkoutException] if repetitions < target.
  WorkoutResult completeSession(String sessionId);

  /// Voluntarily cancels a session before completion (safe exit).
  ///
  /// Throws [UnknownSessionException] if session is not found.
  /// Throws [InvalidSessionTransitionException] if session was already completed.
  WorkoutSession cancelSession(String sessionId, {String? reason});

  /// Terminates a session due to camera failure or unrecoverable error.
  ///
  /// Throws [UnknownSessionException] if session is not found.
  /// Throws [InvalidSessionTransitionException] if session was already completed.
  WorkoutSession failSession(String sessionId, {required String reason});

  /// Returns current active session or null.
  WorkoutSession? getCurrentSession();

  /// Clears the current session reference after it has reached a terminal state.
  ///
  /// Throws [SessionAlreadyActiveException] if the session is still active.
  void releaseCurrentSession();

  /// Disposes internal broadcast stream controller.
  void dispose();
}

/// Production implementation of [IWorkoutSessionManager].
class WorkoutSessionManager implements IWorkoutSessionManager {
  final IChallengeService _challengeService;
  final String Function() _idGenerator;
  final DateTime Function() _clock;
  final StreamController<WorkoutSession> _sessionController =
      StreamController<WorkoutSession>.broadcast();
  final Set<String> _processedEventIds = <String>{};

  WorkoutSession? _currentSession;
  static int _sequence = 0;

  /// Creates a [WorkoutSessionManager].
  ///
  /// Allows dependency injection of [IChallengeService], id generator, and clock for testing.
  WorkoutSessionManager({
    IChallengeService? challengeService,
    String Function()? idGenerator,
    DateTime Function()? clock,
  })  : _challengeService = challengeService ?? ChallengeService(),
        _idGenerator = idGenerator ?? _defaultIdGenerator,
        _clock = clock ?? DateTime.now;

  static String _defaultIdGenerator() {
    _sequence++;
    return 'session_${DateTime.now().microsecondsSinceEpoch}_$_sequence';
  }

  @override
  WorkoutSession? get currentSession => _currentSession;

  @override
  Stream<WorkoutSession> get sessionStream => _sessionController.stream;

  @override
  WorkoutSession? getCurrentSession() => _currentSession;

  @override
  WorkoutSession createSession(ChallengeRequest request) {
    if (_currentSession != null && !_currentSession!.status.isTerminal) {
      throw SessionAlreadyActiveException(_currentSession!.sessionId);
    }

    final definition = _challengeService.getChallengeDefinition(request.challengeId);
    _challengeService.validateChallengeRequest(request);

    final sessionId = _idGenerator();
    final session = WorkoutSession(
      sessionId: sessionId,
      requestId: request.requestId,
      challengeId: request.challengeId,
      challengeContext: request.context,
      targetPackage: request.targetPackage,
      exerciseType: definition.exerciseType,
      targetRepetitions: definition.targetRepetitions,
      verifiedRepetitions: 0,
      status: WorkoutSessionStatus.created,
      accessDurationSeconds: definition.accessDurationSeconds,
      xpReward: definition.optionalXpReward ?? 50,
    );

    _processedEventIds.clear();
    _updateSession(session);
    return session;
  }

  @override
  WorkoutSession prepareSession(String sessionId) {
    final session = _requireSession(sessionId);

    if (session.status == WorkoutSessionStatus.preparing) {
      return session; // Idempotent
    }

    if (session.status != WorkoutSessionStatus.created) {
      throw InvalidSessionTransitionException(
        'Cannot transition to preparing from "${session.status.name}" (must be created).',
      );
    }

    final updated = session.copyWith(
      status: WorkoutSessionStatus.preparing,
    );
    _updateSession(updated);
    return updated;
  }

  @override
  WorkoutSession startSession(String sessionId) {
    final session = _requireSession(sessionId);

    if (session.status == WorkoutSessionStatus.active) {
      return session; // Idempotent
    }

    if (session.status != WorkoutSessionStatus.created &&
        session.status != WorkoutSessionStatus.preparing) {
      throw InvalidSessionTransitionException(
        'Cannot transition to active from "${session.status.name}" (must be created or preparing).',
      );
    }

    final updated = session.copyWith(
      status: WorkoutSessionStatus.active,
      startedAt: session.startedAt ?? _clock(),
    );
    _updateSession(updated);
    return updated;
  }

  @override
  WorkoutSession updateVerifiedProgress(
    String sessionId, {
    required int cumulativeReps,
    String? eventId,
  }) {
    final session = _requireSession(sessionId);

    if (cumulativeReps < 0) {
      throw InvalidProgressException(
        'cumulativeReps must not be negative: $cumulativeReps',
      );
    }

    // Terminal state handling
    if (session.status.isTerminal) {
      if (session.status == WorkoutSessionStatus.completed) {
        return session; // Idempotent return for already-completed session
      }
      throw SessionTerminatedException(session.status.name);
    }

    if (session.status != WorkoutSessionStatus.active) {
      throw InvalidSessionTransitionException(
        'Cannot accept progress when session status is "${session.status.name}" (must be active).',
      );
    }

    // Event deduplication check
    if (eventId != null) {
      if (_processedEventIds.contains(eventId)) {
        return session; // Duplicate event ignored
      }
      _processedEventIds.add(eventId);
    }

    // Monotonicity check: ignore non-increasing cumulative reps
    if (cumulativeReps <= session.verifiedRepetitions) {
      return session;
    }

    final isAchieved = cumulativeReps >= session.targetRepetitions;
    final now = _clock();

    final updated = session.copyWith(
      verifiedRepetitions: cumulativeReps,
      status: isAchieved ? WorkoutSessionStatus.completed : session.status,
      completedAt: isAchieved ? now : session.completedAt,
    );

    _updateSession(updated);
    return updated;
  }

  @override
  WorkoutResult completeSession(String sessionId) {
    final session = _requireSession(sessionId);

    if (session.status == WorkoutSessionStatus.completed) {
      return session.toWorkoutResult();
    }

    if (session.status == WorkoutSessionStatus.cancelled ||
        session.status == WorkoutSessionStatus.failed) {
      throw SessionTerminatedException(session.status.name);
    }

    if (session.status != WorkoutSessionStatus.active) {
      throw InvalidSessionTransitionException(
        'Cannot complete session from status "${session.status.name}" (must be active).',
      );
    }

    if (session.verifiedRepetitions < session.targetRepetitions) {
      throw IncompleteWorkoutException(
        session.verifiedRepetitions,
        session.targetRepetitions,
      );
    }

    final updated = session.copyWith(
      status: WorkoutSessionStatus.completed,
      completedAt: session.completedAt ?? _clock(),
    );

    _updateSession(updated);
    return updated.toWorkoutResult();
  }

  @override
  WorkoutSession cancelSession(String sessionId, {String? reason}) {
    final session = _requireSession(sessionId);

    if (session.status == WorkoutSessionStatus.cancelled) {
      return session; // Idempotent
    }

    if (session.status == WorkoutSessionStatus.completed) {
      throw const InvalidSessionTransitionException(
        'Cannot cancel an already completed workout session.',
      );
    }

    if (session.status == WorkoutSessionStatus.failed) {
      throw const InvalidSessionTransitionException(
        'Cannot cancel an already failed workout session.',
      );
    }

    final updated = session.copyWith(
      status: WorkoutSessionStatus.cancelled,
      completedAt: _clock(),
    );

    _updateSession(updated);
    return updated;
  }

  @override
  WorkoutSession failSession(String sessionId, {required String reason}) {
    final session = _requireSession(sessionId);

    if (session.status == WorkoutSessionStatus.failed) {
      return session; // Idempotent
    }

    if (session.status == WorkoutSessionStatus.completed) {
      throw const InvalidSessionTransitionException(
        'Cannot fail an already completed workout session.',
      );
    }

    if (session.status == WorkoutSessionStatus.cancelled) {
      throw const InvalidSessionTransitionException(
        'Cannot fail an already cancelled workout session.',
      );
    }

    final updated = session.copyWith(
      status: WorkoutSessionStatus.failed,
      failureReason: reason,
      completedAt: _clock(),
    );

    _updateSession(updated);
    return updated;
  }

  @override
  void releaseCurrentSession() {
    if (_currentSession != null && !_currentSession!.status.isTerminal) {
      throw SessionAlreadyActiveException(_currentSession!.sessionId);
    }
    _currentSession = null;
    _processedEventIds.clear();
  }

  @override
  void dispose() {
    _sessionController.close();
  }

  WorkoutSession _requireSession(String sessionId) {
    if (_currentSession == null || _currentSession!.sessionId != sessionId) {
      throw UnknownSessionException(sessionId);
    }
    return _currentSession!;
  }

  void _updateSession(WorkoutSession session) {
    _currentSession = session;
    if (!_sessionController.isClosed) {
      _sessionController.add(session);
    }
  }
}
