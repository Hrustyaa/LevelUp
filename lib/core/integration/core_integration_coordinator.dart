import 'dart:async';

import '../../core/constants/channel_constants.dart';
import '../../data/repositories/access_attempt_repository.dart';
import '../../data/repositories/workout_history_repository.dart';
import '../../features/challenge/application/challenge_service.dart';
import '../../features/challenge/application/workout_session_manager.dart';
import '../../features/focus/application/focus_service.dart';
import '../../features/pose_detection/application/squat_counter.dart';
import '../../models/access_attempt_state.dart';
import '../../models/native_permission_status.dart';
import '../../services/access_service.dart';
import '../../services/native_bridge.dart';
import 'coordinator_state.dart';
import 'pose_event_adapter.dart';

/// Contract for the high-level application integration coordinator.
///
/// Orchestrates Focus, Challenge, Pose, Session, Access, and Persistence engines
/// into a unified, headless, testable workflow ready for UI attachment in Phase B.
abstract class ICoreIntegrationCoordinator {
  /// The latest immutable state snapshot.
  CoordinatorState get currentState;

  /// Reactive broadcast stream of [CoordinatorState] updates.
  Stream<CoordinatorState> get stateStream;

  /// Initializes the coordinator, syncing initial live focus state.
  Future<void> initialize();

  /// Launches an Unlock Challenge session mapped to the currently restricted target app.
  ///
  /// Consumes the native challenge-request flag and enforces:
  /// - Android Accessibility permission is granted.
  /// - Voluntary Focus restriction is active.
  /// - Target package is in [ChannelConstants.allowedTargets].
  Future<WorkoutSession> launchUnlockChallenge({bool requirePendingRequest = false});

  /// Launches a voluntary Free Workout session.
  ///
  /// Bypasses gate/target restrictions and guarantees no native access is ever granted.
  Future<WorkoutSession> launchFreeWorkout();

  /// Connects an [IPoseEventSource] to stream verified pose repetitions to the active session.
  void attachPoseEventSource(IPoseEventSource source);

  /// Detaches the currently connected pose event source, if any.
  void detachPoseEventSource();

  /// Directly processes a [SquatCounterResult] snapshot from the Pose Engine.
  ///
  /// Forwards valid repetitions to [WorkoutSessionManager], ignores invalid tracking frames,
  /// and automatically triggers completion and persistence upon reaching the goal.
  Future<WorkoutSession?> handlePoseResult(SquatCounterResult result, {String? eventId});

  /// Voluntarily cancels the active workout session before completion.
  Future<WorkoutSession> cancelCurrentSession({String? reason});

  /// Terminates the active workout session due to camera/tracking error.
  Future<WorkoutSession> failCurrentSession({required String reason});

  /// Explicitly processes session completion and coordinates persistence and access grant.
  Future<void> completeCurrentSession();

  /// Awaits completion of the asynchronous background persistence and access grant workflow.
  Future<void> waitForCompletion([Duration timeout = const Duration(seconds: 5)]);

  /// Releases a completed, cancelled, or failed workout session and resets coordinator state.
  void releaseTerminalSession();

  /// Disposes coordinator resources, event subscriptions, and controllers.
  void dispose();
}

/// Production implementation of [ICoreIntegrationCoordinator].
class CoreIntegrationCoordinator implements ICoreIntegrationCoordinator {
  final INativeBridge _nativeBridge;
  final IFocusService _focusService;
  final IChallengeService _challengeService;
  final IWorkoutSessionManager _sessionManager;
  final IAccessService _accessService;
  final IWorkoutHistoryRepository _workoutHistoryRepository;
  final IAccessAttemptRepository _accessAttemptRepository;
  final DateTime Function() _clock;

  final StreamController<CoordinatorState> _stateController =
      StreamController<CoordinatorState>.broadcast();

  CoordinatorState _currentState = CoordinatorState.initial();
  StreamSubscription<SquatCounterResult>? _poseSubscription;

  final Set<String> _completingSessionIds = <String>{};
  Completer<void>? _completionCompleter;

  CoreIntegrationCoordinator({
    required INativeBridge nativeBridge,
    required IFocusService focusService,
    required IChallengeService challengeService,
    required IWorkoutSessionManager sessionManager,
    required IAccessService accessService,
    required IWorkoutHistoryRepository workoutHistoryRepository,
    required IAccessAttemptRepository accessAttemptRepository,
    DateTime Function()? clock,
  })  : _nativeBridge = nativeBridge,
        _focusService = focusService,
        _challengeService = challengeService,
        _sessionManager = sessionManager,
        _accessService = accessService,
        _workoutHistoryRepository = workoutHistoryRepository,
        _accessAttemptRepository = accessAttemptRepository,
        _clock = clock ?? DateTime.now;

  @override
  CoordinatorState get currentState => _currentState;

  @override
  Stream<CoordinatorState> get stateStream => _stateController.stream;

  @override
  Future<void> initialize() async {
    try {
      final focusState = await _focusService.getFocusStatus();
      _emitState(_currentState.copyWith(
        permissionStatus: NativePermissionStatus(
          isAccessibilityGranted: focusState.isAccessibilityGranted,
        ),
        selectedTarget: focusState.selectedTarget,
        isFocusEnabled: focusState.isUserEnabled,
        unlockUntil: focusState.unlockUntil,
        clearError: true,
      ));
    } catch (e) {
      _emitState(_currentState.copyWith(
        errorMessage: 'Failed to initialize coordinator state: $e',
      ));
    }
  }

  @override
  Future<WorkoutSession> launchUnlockChallenge({bool requirePendingRequest = false}) async {
    // 0. Ensure no workout session is already active or in-flight before consuming native request
    if (_currentState.sessionStatus == WorkoutSessionStatus.active ||
        _currentState.sessionStatus == WorkoutSessionStatus.preparing) {
      final error = SessionAlreadyActiveException(
        _currentState.sessionId ?? 'active_session',
      );
      _emitState(_currentState.copyWith(errorMessage: error.message));
      throw error;
    }

    // Release any previous terminal session to ensure a clean lifecycle
    final prevSession = _sessionManager.currentSession;
    if (prevSession != null && prevSession.status.isTerminal) {
      _sessionManager.releaseCurrentSession();
    }

    // 1. Query and validate live Focus state
    final focusState = await _focusService.getFocusStatus();

    if (!focusState.isAccessibilityGranted) {
      const error = MissingAccessibilityPermissionException();
      _emitState(_currentState.copyWith(errorMessage: error.message));
      throw error;
    }

    if (!focusState.isUserEnabled) {
      const error = FocusDisabledException();
      _emitState(_currentState.copyWith(errorMessage: error.message));
      throw error;
    }

    final target = focusState.selectedTarget;
    if (!ChannelConstants.allowedTargets.contains(target)) {
      final error = UnsupportedTargetException(target);
      _emitState(_currentState.copyWith(errorMessage: error.message));
      throw error;
    }

    // 2. Consume native challenge request flag safely
    // NOTE: Native consumeChallengeRequest returns only a boolean flag indicating
    // the user clicked the overlay. It does NOT carry authenticated target package
    // or session token attribution.
    final hasNativeRequest = await _nativeBridge.consumeChallengeRequest();
    if (requirePendingRequest && !hasNativeRequest) {
      const error = InvalidChallengeRequestException(
        'Cannot launch unlock challenge: no pending native challenge request flag found.',
      );
      _emitState(_currentState.copyWith(errorMessage: error.message));
      throw error;
    }

    // 3. Create challenge request from ChallengeService
    final challengeRequest = _challengeService.createUnlockChallengeRequest(target);
    final challengeDef = _challengeService.getChallengeDefinition(challengeRequest.challengeId);

    // 4. Create and start WorkoutSession via WorkoutSessionManager
    _completionCompleter = null;
    final session = _sessionManager.createSession(challengeRequest);
    final startedSession = _sessionManager.startSession(session.sessionId);

    _emitState(_currentState.copyWith(
      challenge: challengeDef,
      challengeContext: ChallengeType.unlockChallenge,
      sessionId: startedSession.sessionId,
      sessionStatus: startedSession.status,
      verifiedRepetitions: startedSession.verifiedRepetitions,
      targetRepetitions: startedSession.targetRepetitions,
      selectedTarget: target,
      permissionStatus: NativePermissionStatus(
        isAccessibilityGranted: focusState.isAccessibilityGranted,
      ),
      isFocusEnabled: focusState.isUserEnabled,
      accessGrantStatus: null,
      unlockUntil: null,
      isWorkoutPersisted: false,
      accessAttemptState: null,
      feedbackMessage: 'Встань так, чтобы камера видела ноги и корпус',
      clearError: true,
    ));

    return startedSession;
  }

  @override
  Future<WorkoutSession> launchFreeWorkout() async {
    // 0. Ensure no workout session is already active or in-flight
    if (_currentState.sessionStatus == WorkoutSessionStatus.active ||
        _currentState.sessionStatus == WorkoutSessionStatus.preparing) {
      final error = SessionAlreadyActiveException(
        _currentState.sessionId ?? 'active_session',
      );
      _emitState(_currentState.copyWith(errorMessage: error.message));
      throw error;
    }

    // Release any previous terminal session to ensure a clean lifecycle
    final prevSession = _sessionManager.currentSession;
    if (prevSession != null && prevSession.status.isTerminal) {
      _sessionManager.releaseCurrentSession();
    }

    // 1. Create Free Workout request
    final challengeRequest = _challengeService.createFreeWorkoutRequest();
    final challengeDef = _challengeService.getChallengeDefinition(challengeRequest.challengeId);

    // 2. Create and start WorkoutSession without targetPackage
    _completionCompleter = null;
    final session = _sessionManager.createSession(challengeRequest);
    final startedSession = _sessionManager.startSession(session.sessionId);

    _emitState(_currentState.copyWith(
      challenge: challengeDef,
      challengeContext: ChallengeType.freeWorkout,
      sessionId: startedSession.sessionId,
      sessionStatus: startedSession.status,
      verifiedRepetitions: startedSession.verifiedRepetitions,
      targetRepetitions: startedSession.targetRepetitions,
      selectedTarget: null,
      accessGrantStatus: null,
      isWorkoutPersisted: false,
      accessAttemptState: null,
      feedbackMessage: 'Встань так, чтобы камера видела ноги и корпус',
      clearError: true,
    ));

    return startedSession;
  }

  @override
  void attachPoseEventSource(IPoseEventSource source) {
    detachPoseEventSource();

    if (_nativeBridge is NativeBridge && source.isSimulated) {
      throw StateError(
        'Security Violation: Simulated pose event source cannot be attached when operating with real native platform bridge.',
      );
    }

    _poseSubscription = source.poseStream.listen((result) async {
      try {
        await handlePoseResult(result);
      } catch (_) {
        // Exception state is preserved in currentState.errorMessage and SQLite journal
      }
    });
  }

  @override
  void detachPoseEventSource() {
    _poseSubscription?.cancel();
    _poseSubscription = null;
  }

  @override
  Future<WorkoutSession?> handlePoseResult(
    SquatCounterResult result, {
    String? eventId,
  }) async {
    if (_nativeBridge is NativeBridge && result.isSimulated) {
      throw StateError(
        'Security Violation: Simulated pose result cannot be evaluated when operating with real native platform bridge.',
      );
    }

    final activeSession = _sessionManager.currentSession;
    if (activeSession == null) return null;

    // Do not process repetitions if session has reached a terminal status
    if (activeSession.status.isTerminal) {
      return activeSession;
    }

    // Ignore frames where tracking is invalid
    if (!result.isValidTracking) {
      _emitState(_currentState.copyWith(
        feedbackMessage: result.feedbackMessage,
        lastKneeAngle: result.kneeAngle,
      ));
      return activeSession;
    }

    // If session is not active (e.g. still preparing), update posture only
    if (activeSession.status != WorkoutSessionStatus.active) {
      _emitState(_currentState.copyWith(
        feedbackMessage: result.feedbackMessage,
        lastKneeAngle: result.kneeAngle,
      ));
      return activeSession;
    }

    // Only update progress when cumulative count increases monotonically
    if (result.repetitionCount > activeSession.verifiedRepetitions) {
      final updated = _sessionManager.updateVerifiedProgress(
        activeSession.sessionId,
        cumulativeReps: result.repetitionCount,
        eventId: eventId,
      );

      _emitState(_currentState.copyWith(
        verifiedRepetitions: updated.verifiedRepetitions,
        sessionStatus: updated.status,
        feedbackMessage: result.feedbackMessage,
        lastKneeAngle: result.kneeAngle,
      ));

      // Trigger completion workflow when target repetitions achieved
      if (updated.status == WorkoutSessionStatus.completed) {
        _completionCompleter ??= Completer<void>();
        await _executeCompletionWorkflow(updated);
      }

      return updated;
    } else {
      // Just update feedback / angle
      _emitState(_currentState.copyWith(
        feedbackMessage: result.feedbackMessage,
        lastKneeAngle: result.kneeAngle,
      ));
      return activeSession;
    }
  }

  @override
  Future<WorkoutSession> cancelCurrentSession({String? reason}) async {
    final session = _sessionManager.currentSession;
    if (session == null) {
      throw const UnknownSessionException('No active workout session to cancel.');
    }

    final cancelled = _sessionManager.cancelSession(session.sessionId, reason: reason);
    _emitState(_currentState.copyWith(
      sessionStatus: cancelled.status,
      feedbackMessage: 'Тренировка отменена',
    ));
    return cancelled;
  }

  @override
  Future<WorkoutSession> failCurrentSession({required String reason}) async {
    final session = _sessionManager.currentSession;
    if (session == null) {
      throw const UnknownSessionException('No active workout session to fail.');
    }

    final failed = _sessionManager.failSession(session.sessionId, reason: reason);
    _emitState(_currentState.copyWith(
      sessionStatus: failed.status,
      errorMessage: reason,
      feedbackMessage: 'Ошибка тренировки',
    ));
    return failed;
  }

  @override
  Future<void> completeCurrentSession() async {
    final session = _sessionManager.currentSession;
    if (session == null) {
      throw const UnknownSessionException('No active workout session to complete.');
    }

    if (session.status != WorkoutSessionStatus.completed) {
      _sessionManager.completeSession(session.sessionId);
    }

    final completedSession = _sessionManager.currentSession!;
    _emitState(_currentState.copyWith(
      sessionStatus: completedSession.status,
      verifiedRepetitions: completedSession.verifiedRepetitions,
    ));
    _completionCompleter ??= Completer<void>();
    await _executeCompletionWorkflow(completedSession);
  }

  @override
  Future<void> waitForCompletion([Duration timeout = const Duration(seconds: 5)]) async {
    final completer = _completionCompleter;
    if (completer != null && !completer.isCompleted) {
      await completer.future.timeout(timeout);
    }
  }

  @override
  void releaseTerminalSession() {
    final session = _sessionManager.currentSession;
    if (session != null && session.status.isTerminal) {
      _sessionManager.releaseCurrentSession();
    }
    _emitState(_currentState.copyWith(
      sessionId: null,
      sessionStatus: WorkoutSessionStatus.created,
      verifiedRepetitions: 0,
      targetRepetitions: 5,
      accessGrantStatus: null,
      unlockUntil: null,
      accessAttemptState: null,
      isWorkoutPersisted: false,
      feedbackMessage: 'Встань так, чтобы камера видела ноги и корпус',
      clearError: true,
    ));
  }

  Future<void> _executeCompletionWorkflow(WorkoutSession session) async {
    final sessionId = session.sessionId;

    // Concurrency & duplicate callback suppression
    if (_completingSessionIds.contains(sessionId)) {
      return;
    }
    _completingSessionIds.add(sessionId);

    try {
      // 1. Confirm session has completed and retrieve authoritative WorkoutResult
      final workoutResult = session.toWorkoutResult();

      // 2. Persist completed workout result in SQLite
      await _workoutHistoryRepository.saveCompletedWorkout(workoutResult);
      _emitState(_currentState.copyWith(isWorkoutPersisted: true));

      // 3. Free workout never issues access
      if (session.challengeContext == ChallengeType.freeWorkout) {
        _emitState(_currentState.copyWith(
          feedbackMessage: 'Свободная тренировка завершена! Прогресс сохранён.',
        ));
        return;
      }

      // 4. Unlock Challenge: execute access grant workflow
      await _executeAccessGrantWorkflow(workoutResult);
    } catch (e) {
      _emitState(_currentState.copyWith(
        errorMessage: 'Completion workflow error: $e',
      ));
      if (_completionCompleter != null && !_completionCompleter!.isCompleted) {
        _completionCompleter!.completeError(e);
      }
      rethrow;
    } finally {
      _completingSessionIds.remove(sessionId);
      if (_completionCompleter != null && !_completionCompleter!.isCompleted) {
        _completionCompleter!.complete();
      }
    }
  }

  Future<void> _executeAccessGrantWorkflow(WorkoutResult result) async {
    final sessionId = result.sessionId;

    // 1. Query existing access-attempt journal for this session
    final existingAttempt = await _accessAttemptRepository.getAttemptBySessionId(sessionId);

    // If already confirmed, do not grant again (process & persistent idempotency)
    if (existingAttempt != null && existingAttempt.isConfirmed) {
      _emitState(_currentState.copyWith(
        accessGrantStatus: AccessGrantStatus.granted,
        unlockUntil: existingAttempt.unlockUntil,
        accessAttemptState: AccessAttemptState.confirmed,
        feedbackMessage: 'Доступ уже был выдан для этой тренировки.',
      ));
      return;
    }

    // If in prepared or uncertain state, DO NOT automatically retry!
    if (existingAttempt != null && existingAttempt.requiresReconciliation) {
      final msg = 'Access attempt for session "$sessionId" is in state '
          '"${existingAttempt.state.name}" and requires reconciliation before retry.';
      _emitState(_currentState.copyWith(
        accessAttemptState: existingAttempt.state,
        errorMessage: msg,
      ));
      throw AccessEngineException(
        code: 'REQUIRES_RECONCILIATION',
        message: msg,
      );
    }

    // 2. Create prepared access-attempt record in SQLite BEFORE calling native grantAccess
    // CRITICAL SAFETY RULE: If SQLite fails to persist the prepared attempt, DO NOT invoke native grantAccess.
    await _accessAttemptRepository.createAttemptIfAbsent(
      sessionId: sessionId,
      targetPackage: result.targetPackage!,
      durationSeconds: result.accessDurationSeconds,
      attemptedAt: _clock(),
    );

    _emitState(_currentState.copyWith(
      accessAttemptState: AccessAttemptState.prepared,
    ));

    // 3. Invoke AccessService to authorize and grant native access
    try {
      final grantResult = await _accessService.grantAccessForCompletedWorkout(result);

      if (grantResult.isSuccessful && grantResult.unlockUntil != null) {
        // Confirmation confirmed by native layer
        final confirmedRecord = await _accessAttemptRepository.markConfirmed(
          sessionId: sessionId,
          confirmedAt: _clock(),
          unlockUntil: grantResult.unlockUntil!,
        );

        // Synchronize FocusService with fresh native state
        try {
          await _focusService.refreshState();
        } catch (_) {}

        _emitState(_currentState.copyWith(
          accessGrantStatus: AccessGrantStatus.granted,
          unlockUntil: confirmedRecord.unlockUntil,
          accessAttemptState: AccessAttemptState.confirmed,
          feedbackMessage: 'Доступ выдан на 5 минут!',
        ));
      }
    } on Exception catch (e) {
      // Categorize failure: definitive rejection (pre-invocation) vs uncertain (platform/IPC error)
      if (e is MissingAccessibilityPermissionException ||
          e is FocusDisabledException ||
          e is TargetPackageMismatchException ||
          e is IneligibleWorkoutContextException ||
          e is UnsupportedAccessTargetException) {
        await _accessAttemptRepository.markDefinitivelyRejected(
          sessionId: sessionId,
          reason: e.toString(),
        );

        _emitState(_currentState.copyWith(
          accessGrantStatus: AccessGrantStatus.rejected,
          accessAttemptState: AccessAttemptState.definitivelyRejected,
          errorMessage: e.toString(),
        ));
      } else {
        await _accessAttemptRepository.markUncertain(
          sessionId: sessionId,
          reason: e.toString(),
        );

        _emitState(_currentState.copyWith(
          accessGrantStatus: AccessGrantStatus.failed,
          accessAttemptState: AccessAttemptState.uncertain,
          errorMessage: 'Uncertain access outcome: $e',
        ));
      }
      rethrow;
    }
  }

  void _emitState(CoordinatorState state) {
    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  @override
  void dispose() {
    detachPoseEventSource();
    _stateController.close();
  }
}
