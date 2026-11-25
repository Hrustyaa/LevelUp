import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';
import 'package:levelup_test/features/progress/application/level_calculator.dart';
import 'package:levelup_test/features/progress/application/progress_service.dart';
import 'package:levelup_test/features/progress/application/streak_calculator.dart';
import 'package:levelup_test/features/progress/application/xp_reward_policy.dart';
import 'package:levelup_test/features/progress/data/progress_repository.dart';
import 'package:levelup_test/features/progress/models/xp_reward_record.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailingProgressRepo implements IProgressRepository {
  @override
  Future<List<XpRewardRecord>> getAllRewards() async => const [];

  @override
  Future<XpRewardRecord?> getRewardBySessionId(String sessionId) async => null;

  @override
  Future<int> getTotalXp() async => 0;

  @override
  Future<int> getOrCreateProgressEpochMs(int defaultEpochMs) async =>
      defaultEpochMs;

  @override
  Future<bool> recordRewardIfAbsent(XpRewardRecord record) async {
    throw StateError('Simulated SQLite write failure');
  }
}

WorkoutResult _makeWorkout({
  required String sessionId,
  ChallengeType context = ChallengeType.unlockChallenge,
  String? target = ChannelConstants.targetYouTube,
  int reps = 5,
  String source = 'camera',
  DateTime? completedAt,
}) {
  return WorkoutResult(
    sessionId: sessionId,
    requestId: 'req-$sessionId',
    challengeId:
        context == ChallengeType.unlockChallenge ? 'squats_unlock_5' : 'squats_free_5',
    challengeContext: context,
    exerciseType: ExerciseType.squats,
    targetPackage: target,
    completedRepetitions: reps,
    duration: const Duration(seconds: 25),
    completedAt: completedAt ?? DateTime(2026, 11, 25, 10, 0),
    eligibleForAccess: context == ChallengeType.unlockChallenge,
    accessDurationSeconds: context == ChallengeType.unlockChallenge ? 300 : 0,
    earnedXp: 50,
    source: source,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Module 09A — XpRewardPolicy', () {
    const policy = XpRewardPolicy();

    test('1. Verified 5-rep unlock and free workouts award 50 XP', () {
      final unlockDecision = policy.evaluate(_makeWorkout(sessionId: 'u1'));
      expect(unlockDecision.eligible, isTrue);
      expect(unlockDecision.xpAmount, 50);

      final freeDecision = policy.evaluate(
        _makeWorkout(
          sessionId: 'f1',
          context: ChallengeType.freeWorkout,
          target: null,
        ),
      );
      expect(freeDecision.eligible, isTrue);
      expect(freeDecision.xpAmount, 50);
    });

    test('2. Incomplete (<5 reps), unknown, empty, mock, simulated, or preview workouts earn 0 XP', () {
      expect(
        policy.evaluate(_makeWorkout(sessionId: 'inc', reps: 4)).eligible,
        isFalse,
      );
      for (final untrusted in [
        'simulated',
        'preview',
        'ui_only',
        'mock',
        'unknown',
        'manual',
        '',
      ]) {
        expect(
          policy.evaluate(_makeWorkout(sessionId: 'src_$untrusted', source: untrusted)).eligible,
          isFalse,
          reason: 'Source "$untrusted" must be rejected',
        );
      }
    });
  });

  group('Module 09A — LevelCalculator', () {
    const calc = LevelCalculator();

    test('3. Exact level boundaries, negative clamping, and large XP', () {
      final zero = calc.calculate(0);
      expect(zero.level, 1);
      expect(zero.xpIntoCurrentLevel, 0);
      expect(zero.xpRequiredForNextLevel, 100);
      expect(zero.progressFraction, 0.0);

      final neg = calc.calculate(-500);
      expect(neg.totalXp, 0);
      expect(neg.level, 1);

      final l1Edge = calc.calculate(99);
      expect(l1Edge.level, 1);
      expect(l1Edge.xpIntoCurrentLevel, 99);
      expect(l1Edge.xpRequiredForNextLevel, 100);

      final l2Start = calc.calculate(100);
      expect(l2Start.level, 2);
      expect(l2Start.xpIntoCurrentLevel, 0);
      expect(l2Start.xpRequiredForNextLevel, 200);

      final l2Mid = calc.calculate(200);
      expect(l2Mid.level, 2);
      expect(l2Mid.xpIntoCurrentLevel, 100);
      expect(l2Mid.progressFraction, 0.5);

      final l3Start = calc.calculate(300);
      expect(l3Start.level, 3);
      expect(l3Start.xpIntoCurrentLevel, 0);
      expect(l3Start.xpRequiredForNextLevel, 300);

      final l4Start = calc.calculate(600);
      expect(l4Start.level, 4);

      final large = calc.calculate(1_000_000);
      expect(large.totalXp, 1_000_000);
      expect(large.level, greaterThan(100));
      expect(large.progressFraction, inInclusiveRange(0.0, 1.0));
    });
  });

  group('Module 09A — StreakCalculator', () {
    const streakCalc = StreakCalculator();

    test('4. Current & longest streak, multiple workouts same day, missed days, month/year boundaries', () {
      // Multiple workouts on same day count once
      final sameDay = streakCalc.calculate(
        ['2026-11-25', '2026-11-25', '2026-11-25'],
        now: DateTime(2026, 11, 25, 22, 0),
      );
      expect(sameDay.currentStreak, 1);
      expect(sameDay.longestStreak, 1);
      expect(sameDay.completedToday, isTrue);

      // Month & year boundary: Dec 30, Dec 31, Jan 1 -> 3-day streak
      final yearBoundary = streakCalc.calculate(
        ['2025-12-30', '2025-12-31', '2026-01-01'],
        now: DateTime(2026, 1, 2, 9, 0), // yesterday was Jan 1 -> still active!
      );
      expect(yearBoundary.currentStreak, 3);
      expect(yearBoundary.longestStreak, 3);
      expect(yearBoundary.completedToday, isFalse);

      // Missed day breaks currentStreak to 0, preserves longestStreak
      final broken = streakCalc.calculate(
        ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04', '2026-01-10'],
        now: DateTime(2026, 1, 12, 10, 0),
      );
      expect(broken.currentStreak, 0);
      expect(broken.longestStreak, 4);
      expect(broken.lastWorkoutLocalDate, '2026-01-10');
    });
  });

  group('Module 09A — ProgressService & SQLite Exactly-Once Persistence', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('levelup_progress_');
      dbPath = p.join(tempDir.path, 'progress.db');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('5. Exactly-once reward, concurrent calls, and persistence across restart', () async {
      final db1 = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final repo1 = SqliteProgressRepository(databaseManager: db1);
      final service1 = ProgressService(
        repository: repo1,
        clock: () => DateTime(2026, 11, 25, 12, 0),
      );
      await service1.initialize();

      final workout = _makeWorkout(
        sessionId: 'sess-concurrent',
        completedAt: DateTime(2026, 11, 25, 11, 0),
      );

      // Fire 5 concurrent reward calls for the same sessionId
      final outcomes = await Future.wait([
        for (var i = 0; i < 5; i++) service1.recordCompletedWorkout(workout),
      ]);

      expect(outcomes.where((o) => o.awarded).length, 1);
      expect(outcomes.where((o) => o.duplicate).length, 4);
      expect(service1.currentState.totalXp, 50);
      expect(service1.currentState.completedWorkoutCount, 1);
      expect(service1.currentState.currentStreak, 1);

      service1.dispose();
      await db1.close();

      // Simulate app restart with new DB & ProgressService instance
      final db2 = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final repo2 = SqliteProgressRepository(databaseManager: db2);
      final service2 = ProgressService(
        repository: repo2,
        clock: () => DateTime(2026, 11, 25, 15, 0),
      );
      await service2.initialize();

      expect(service2.currentState.totalXp, 50);
      expect(service2.currentState.completedWorkoutCount, 1);

      // Repeated attempt after restart is still rejected as duplicate
      final afterRestart = await service2.recordCompletedWorkout(workout);
      expect(afterRestart.awarded, isFalse);
      expect(afterRestart.duplicate, isTrue);
      expect(service2.currentState.totalXp, 50);

      service2.dispose();
      await db2.close();
    });
  });

  group('Module 09A — CoreIntegrationCoordinator Integration & Security', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const controlChannel = MethodChannel(ChannelConstants.controlChannel);

    late int grantCount;
    late List<int> grantedMinutes;
    late Directory tempDir;
    late LevelUpDatabase db;

    setUp(() async {
      grantCount = 0;
      grantedMinutes = [];
      tempDir = await Directory.systemTemp.createTemp('levelup_coord_prog_');
      db = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: p.join(tempDir.path, 'coord.db'),
      );

      messenger.setMockMethodCallHandler(controlChannel, (call) async {
        switch (call.method) {
          case ChannelConstants.methodGetState:
            return {
              ChannelConstants.keyTarget: ChannelConstants.targetYouTube,
              ChannelConstants.keyEnabled: true,
              ChannelConstants.keyUnlockUntil: 0,
              ChannelConstants.keyServiceEnabled: true,
            };
          case ChannelConstants.methodConsumeChallengeRequest:
            return true;
          case ChannelConstants.methodGrantAccess:
            grantCount++;
            final mins =
                (call.arguments as Map<dynamic, dynamic>)[ChannelConstants.argMinutes]
                    as int;
            grantedMinutes.add(mins);
            return DateTime.now()
                .add(Duration(minutes: mins))
                .millisecondsSinceEpoch;
          default:
            return null;
        }
      });
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(controlChannel, null);
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('6. Cancelled workout gives 0 XP; Free Workout gives 50 XP with 0 grantAccess; Unlock Challenge grants once and awards 50 XP', () async {
      const bridge = NativeBridge();
      final focusService = FocusService(bridge: bridge);
      final challengeService = ChallengeService();
      final sessionManager = WorkoutSessionManager(challengeService: challengeService);
      final accessService = AccessService(bridge: bridge);
      final historyRepo = WorkoutHistoryRepository(databaseManager: db);
      final accessRepo = AccessAttemptRepository(databaseManager: db);
      final progressRepo = SqliteProgressRepository(databaseManager: db);
      final progressService = ProgressService(repository: progressRepo);
      await progressService.initialize();

      final coordinator = CoreIntegrationCoordinator(
        nativeBridge: bridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: historyRepo,
        accessAttemptRepository: accessRepo,
        progressService: progressService,
      );
      await coordinator.initialize();

      // A. Cancelled workout -> 0 XP
      await coordinator.launchFreeWorkout();
      await coordinator.cancelCurrentSession(reason: 'User cancelled');
      expect(progressService.currentState.totalXp, 0);
      expect(grantCount, 0);
      coordinator.releaseTerminalSession();

      // B. Completed Free Workout -> 50 XP, 0 grantAccess
      await coordinator.launchFreeWorkout();
      for (var rep = 1; rep <= 5; rep++) {
        await coordinator.handlePoseResult(
          SquatCounterResult(
            phase: SquatPhase.up,
            repetitionCount: rep,
            isRepetitionCompleted: true,
            isValidTracking: true,
            consecutiveDownFrames: 0,
            consecutiveUpFrames: 2,
            feedbackMessage: 'Rep $rep',
          ),
        );
      }
      await coordinator.waitForCompletion();
      expect(progressService.currentState.totalXp, 50);
      expect(grantCount, 0);
      coordinator.releaseTerminalSession();

      // C. Completed Unlock Challenge -> +50 XP (total 100, Level 2) & 1 grantAccess(5)
      await coordinator.launchUnlockChallenge(requirePendingRequest: true);
      for (var rep = 1; rep <= 5; rep++) {
        await coordinator.handlePoseResult(
          SquatCounterResult(
            phase: SquatPhase.up,
            repetitionCount: rep,
            isRepetitionCompleted: true,
            isValidTracking: true,
            consecutiveDownFrames: 0,
            consecutiveUpFrames: 2,
            feedbackMessage: 'Rep $rep',
          ),
        );
      }
      await coordinator.waitForCompletion();
      expect(coordinator.currentState.sessionStatus, WorkoutSessionStatus.completed);
      expect(coordinator.currentState.accessGrantStatus, AccessGrantStatus.granted);
      expect(grantCount, 1);
      expect(grantedMinutes, [5]);
      expect(progressService.currentState.totalXp, 100);
      expect(progressService.currentState.level, 2);

      // Duplicate completion call must NOT award extra XP or second grantAccess
      await coordinator.completeCurrentSession();
      expect(grantCount, 1);
      expect(progressService.currentState.totalXp, 100);

      coordinator.dispose();
      progressService.dispose();
    });

    test('7. Reward persistence failure does not break or duplicate native grantAccess', () async {
      const bridge = NativeBridge();
      final focusService = FocusService(bridge: bridge);
      final challengeService = ChallengeService();
      final sessionManager = WorkoutSessionManager(challengeService: challengeService);
      final accessService = AccessService(bridge: bridge);
      final historyRepo = WorkoutHistoryRepository(databaseManager: db);
      final accessRepo = AccessAttemptRepository(databaseManager: db);
      final failingProgress = ProgressService(repository: _FailingProgressRepo());
      await failingProgress.initialize();

      final coordinator = CoreIntegrationCoordinator(
        nativeBridge: bridge,
        focusService: focusService,
        challengeService: challengeService,
        sessionManager: sessionManager,
        accessService: accessService,
        workoutHistoryRepository: historyRepo,
        accessAttemptRepository: accessRepo,
        progressService: failingProgress,
      );
      await coordinator.initialize();

      await coordinator.launchUnlockChallenge(requirePendingRequest: true);
      for (var rep = 1; rep <= 5; rep++) {
        await coordinator.handlePoseResult(
          SquatCounterResult(
            phase: SquatPhase.up,
            repetitionCount: rep,
            isRepetitionCompleted: true,
            isValidTracking: true,
            consecutiveDownFrames: 0,
            consecutiveUpFrames: 2,
            feedbackMessage: 'Rep $rep',
          ),
        );
      }
      await coordinator.waitForCompletion();

      // Native access still succeeds once despite XP journal failure
      expect(coordinator.currentState.accessGrantStatus, AccessGrantStatus.granted);
      expect(grantCount, 1);
      expect(failingProgress.currentState.errorMessage, isNotNull);
      expect(failingProgress.currentState.totalXp, 0);

      coordinator.dispose();
      failingProgress.dispose();
    });

    test('8. Recovers missing XP for failed Module-09A+ reward on restart without fabricating historical XP or re-granting access', () async {
      final epochTime = DateTime(2026, 11, 25, 10, 0);
      final historyRepo = WorkoutHistoryRepository(databaseManager: db);

      // Insert a pre-Module-09 historical workout BEFORE epochTime
      await historyRepo.saveCompletedWorkout(
        _makeWorkout(
          sessionId: 'pre-m09-old',
          completedAt: epochTime.subtract(const Duration(days: 1)),
        ),
      );

      // Boot ProgressService at epochTime -> persists progress_epoch_ms
      final repo1 = SqliteProgressRepository(databaseManager: db);
      final service1 = ProgressService(
        repository: repo1,
        historyRepository: historyRepo,
        clock: () => epochTime,
      );
      await service1.initialize();
      expect(service1.currentState.totalXp, 0); // Historical workout NOT fabricated
      service1.dispose();

      // Simulate a Module-09A+ workout saved to workout_sessions AFTER epochTime
      // whose XP write failed transiently (so xp_rewards has no row for it yet).
      await historyRepo.saveCompletedWorkout(
        _makeWorkout(
          sessionId: 'm09-failed-xp',
          completedAt: epochTime.add(const Duration(minutes: 5)),
        ),
      );

      // Restart ProgressService -> reconciles missing post-epoch reward automatically
      final repo2 = SqliteProgressRepository(databaseManager: db);
      final service2 = ProgressService(
        repository: repo2,
        historyRepository: historyRepo,
        clock: () => epochTime.add(const Duration(minutes: 10)),
      );
      await service2.initialize();

      expect(service2.currentState.totalXp, 50);
      expect(service2.currentState.completedWorkoutCount, 1);
      expect(grantCount, 0); // Never grants access during XP recovery

      // Refreshing again does not duplicate the recovered reward
      await service2.refresh();
      expect(service2.currentState.totalXp, 50);
      expect(service2.currentState.completedWorkoutCount, 1);

      service2.dispose();
    });
  });
}
