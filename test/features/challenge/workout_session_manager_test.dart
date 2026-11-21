import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';

void main() {
  late ChallengeService challengeService;
  late WorkoutSessionManager manager;
  late DateTime fixedTime;
  var idSequence = 0;

  setUp(() {
    idSequence = 0;
    fixedTime = DateTime(2026, 11, 21, 17, 30);
    challengeService = ChallengeService();
    manager = WorkoutSessionManager(
      challengeService: challengeService,
      idGenerator: () => 'test_session_${++idSequence}',
      clock: () => fixedTime,
    );
  });

  tearDown(() {
    manager.dispose();
  });

  group('Session Creation', () {
    test('creates unlock session with target package and 300s access', () {
      final request = challengeService.createUnlockChallengeRequest(ChannelConstants.targetYouTube);
      final session = manager.createSession(request);

      expect(session.sessionId, equals('test_session_1'));
      expect(session.requestId, equals(request.requestId));
      expect(session.challengeContext, equals(ChallengeType.unlockChallenge));
      expect(session.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(session.exerciseType, equals(ExerciseType.squats));
      expect(session.targetRepetitions, equals(5));
      expect(session.verifiedRepetitions, equals(0));
      expect(session.accessDurationSeconds, equals(300));
      expect(session.status, equals(WorkoutSessionStatus.created));
      expect(manager.currentSession, equals(session));
    });

    test('creates free workout session without target package and 0 access', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);

      expect(session.sessionId, equals('test_session_1'));
      expect(session.challengeContext, equals(ChallengeType.freeWorkout));
      expect(session.targetPackage, isNull);
      expect(session.accessDurationSeconds, equals(0));
      expect(session.status, equals(WorkoutSessionStatus.created));
    });

    test('prevents creating a new session while another is active or preparing', () {
      final req1 = challengeService.createFreeWorkoutRequest();
      final session1 = manager.createSession(req1);
      manager.prepareSession(session1.sessionId);

      final req2 = challengeService.createFreeWorkoutRequest();
      expect(
        () => manager.createSession(req2),
        throwsA(
          isA<SessionAlreadyActiveException>()
              .having((e) => e.activeSessionId, 'activeSessionId', equals(session1.sessionId)),
        ),
      );
    });

    test('allows creating a new session after previous session reached terminal status', () {
      final req1 = challengeService.createFreeWorkoutRequest();
      final session1 = manager.createSession(req1);
      manager.cancelSession(session1.sessionId);

      final req2 = challengeService.createFreeWorkoutRequest();
      final session2 = manager.createSession(req2);

      expect(session2.sessionId, equals('test_session_2'));
      expect(session2.status, equals(WorkoutSessionStatus.created));
    });
  });

  group('Lifecycle Transitions', () {
    test('standard flow: created -> preparing -> active -> completed', () {
      final request = challengeService.createUnlockChallengeRequest(ChannelConstants.targetInstagram);
      final session = manager.createSession(request);
      expect(session.status, equals(WorkoutSessionStatus.created));

      final prep = manager.prepareSession(session.sessionId);
      expect(prep.status, equals(WorkoutSessionStatus.preparing));

      final active = manager.startSession(session.sessionId);
      expect(active.status, equals(WorkoutSessionStatus.active));
      expect(active.startedAt, equals(fixedTime));

      final completed = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);
      expect(completed.status, equals(WorkoutSessionStatus.completed));
      expect(completed.completedAt, equals(fixedTime));
    });

    test('direct transition: created -> active is allowed', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);

      final active = manager.startSession(session.sessionId);
      expect(active.status, equals(WorkoutSessionStatus.active));
    });

    test('prepareSession and startSession are idempotent', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);

      final p1 = manager.prepareSession(session.sessionId);
      final p2 = manager.prepareSession(session.sessionId);
      expect(p1, equals(p2));

      final a1 = manager.startSession(session.sessionId);
      final a2 = manager.startSession(session.sessionId);
      expect(a1, equals(a2));
    });

    test('rejects illegal transitions with InvalidSessionTransitionException', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);

      // Cannot update progress before active
      expect(
        () => manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 1),
        throwsA(isA<InvalidSessionTransitionException>()),
      );

      // Start and complete session
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);

      // Cannot prepare or start an already completed session
      expect(
        () => manager.prepareSession(session.sessionId),
        throwsA(isA<InvalidSessionTransitionException>()),
      );
      expect(
        () => manager.startSession(session.sessionId),
        throwsA(isA<InvalidSessionTransitionException>()),
      );
    });
  });

  group('Repetition Progress & Anti-Cheat Invariants', () {
    test('updates verified repetitions and auto-completes at target', () {
      final request = challengeService.createUnlockChallengeRequest(ChannelConstants.targetTikTok);
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);

      final step1 = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 2);
      expect(step1.verifiedRepetitions, equals(2));
      expect(step1.status, equals(WorkoutSessionStatus.active));

      final step2 = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 4);
      expect(step2.verifiedRepetitions, equals(4));
      expect(step2.status, equals(WorkoutSessionStatus.active));

      final step3 = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);
      expect(step3.verifiedRepetitions, equals(5));
      expect(step3.status, equals(WorkoutSessionStatus.completed));
      expect(step3.completedAt, equals(fixedTime));
    });

    test('ignores non-increasing or repeated cumulative repetitions', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);

      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 3);

      // Same count (3)
      final same = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 3);
      expect(same.verifiedRepetitions, equals(3));

      // Lower count (2) - e.g. reset attempt or camera glitch
      final lower = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 2);
      expect(lower.verifiedRepetitions, equals(3), reason: 'Progress must be monotonically non-decreasing');
    });

    test('deduplicates progress events by eventId', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);

      final r1 = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 1, eventId: 'evt_1');
      expect(r1.verifiedRepetitions, equals(1));

      // Duplicate delivery of evt_1 with higher count
      final r2 = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 2, eventId: 'evt_1');
      expect(r2.verifiedRepetitions, equals(1), reason: 'Duplicate eventId must be ignored');

      // New eventId works normally
      final r3 = manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 2, eventId: 'evt_2');
      expect(r3.verifiedRepetitions, equals(2));
    });

    test('rejects negative cumulative repetitions with InvalidProgressException', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);

      expect(
        () => manager.updateVerifiedProgress(session.sessionId, cumulativeReps: -1),
        throwsA(isA<InvalidProgressException>()),
      );
    });
  });

  group('Session Completion & Result Conversion', () {
    test('completeSession returns structured WorkoutResult with valid duration', () {
      final request = challengeService.createUnlockChallengeRequest(ChannelConstants.targetYouTube);
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);

      final result = manager.completeSession(session.sessionId);

      expect(result.sessionId, equals(session.sessionId));
      expect(result.requestId, equals(request.requestId));
      expect(result.challengeContext, equals(ChallengeType.unlockChallenge));
      expect(result.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(result.completedRepetitions, equals(5));
      expect(result.eligibleForAccess, isTrue);
      expect(result.accessDurationSeconds, equals(300));
      expect(result.earnedXp, equals(50));
      expect(result.source, equals('camera'));
    });

    test('rejects premature completion when verified repetitions < target goal', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 3);

      expect(
        () => manager.completeSession(session.sessionId),
        throwsA(
          isA<IncompleteWorkoutException>()
              .having((e) => e.verified, 'verified', equals(3))
              .having((e) => e.target, 'target', equals(5)),
        ),
      );
    });

    test('completeSession is idempotent when called repeatedly', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);

      final res1 = manager.completeSession(session.sessionId);
      final res2 = manager.completeSession(session.sessionId);

      expect(res1, equals(res2));
    });

    test('free workout completion results never authorize access', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);

      final result = manager.completeSession(session.sessionId);

      expect(result.eligibleForAccess, isFalse);
      expect(result.accessDurationSeconds, equals(0));
      expect(result.targetPackage, isNull);
    });
  });

  group('Cancellation & Failure', () {
    test('cancelSession sets status to cancelled and records completion timestamp', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 2);

      final cancelled = manager.cancelSession(session.sessionId, reason: 'User exited');

      expect(cancelled.status, equals(WorkoutSessionStatus.cancelled));
      expect(cancelled.completedAt, equals(fixedTime));
      expect(cancelled.verifiedRepetitions, equals(2));
    });

    test('cancelSession is idempotent', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.cancelSession(session.sessionId);
      final c2 = manager.cancelSession(session.sessionId);
      expect(c2.status, equals(WorkoutSessionStatus.cancelled));
    });

    test('failSession sets status to failed and records failure reason', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);

      final failed = manager.failSession(session.sessionId, reason: 'Camera disconnected');

      expect(failed.status, equals(WorkoutSessionStatus.failed));
      expect(failed.failureReason, equals('Camera disconnected'));
      expect(failed.completedAt, equals(fixedTime));
    });

    test('rejects progress updates after cancellation or failure with SessionTerminatedException', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.cancelSession(session.sessionId);

      expect(
        () => manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 3),
        throwsA(
          isA<SessionTerminatedException>()
              .having((e) => e.statusName, 'statusName', equals('cancelled')),
        ),
      );
    });

    test('cannot complete or cancel an already failed session', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);
      manager.failSession(session.sessionId, reason: 'Sensor error');

      expect(
        () => manager.completeSession(session.sessionId),
        throwsA(isA<SessionTerminatedException>()),
      );
      expect(
        () => manager.cancelSession(session.sessionId),
        throwsA(isA<InvalidSessionTransitionException>()),
      );
    });
  });

  group('Session Release & Clean Up', () {
    test('releaseCurrentSession clears terminal session allowing fresh creation', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.cancelSession(session.sessionId);

      manager.releaseCurrentSession();
      expect(manager.currentSession, isNull);

      // Now a new session can be created cleanly
      final s2 = manager.createSession(request);
      expect(s2.sessionId, equals('test_session_2'));
    });

    test('releaseCurrentSession throws if session is active or preparing', () {
      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.startSession(session.sessionId);

      expect(
        () => manager.releaseCurrentSession(),
        throwsA(isA<SessionAlreadyActiveException>()),
      );
    });

    test('operations throw UnknownSessionException for non-matching sessionId', () {
      expect(
        () => manager.prepareSession('non_existent_id'),
        throwsA(isA<UnknownSessionException>()),
      );
      expect(
        () => manager.startSession('non_existent_id'),
        throwsA(isA<UnknownSessionException>()),
      );
      expect(
        () => manager.completeSession('non_existent_id'),
        throwsA(isA<UnknownSessionException>()),
      );
      expect(
        () => manager.cancelSession('non_existent_id'),
        throwsA(isA<UnknownSessionException>()),
      );
      expect(
        () => manager.failSession('non_existent_id', reason: 'Error'),
        throwsA(isA<UnknownSessionException>()),
      );
    });
  });

  group('Reactive sessionStream', () {
    test('emits updates on each state transition and progress update', () async {
      final emittedStatuses = <WorkoutSessionStatus>[];
      final sub = manager.sessionStream.listen((s) => emittedStatuses.add(s.status));

      final request = challengeService.createFreeWorkoutRequest();
      final session = manager.createSession(request);
      manager.prepareSession(session.sessionId);
      manager.startSession(session.sessionId);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 2);
      manager.updateVerifiedProgress(session.sessionId, cumulativeReps: 5);

      await pumpEventQueue();

      expect(emittedStatuses, equals([
        WorkoutSessionStatus.created,
        WorkoutSessionStatus.preparing,
        WorkoutSessionStatus.active,
        WorkoutSessionStatus.active,
        WorkoutSessionStatus.completed,
      ]));

      await sub.cancel();
    });
  });
}
