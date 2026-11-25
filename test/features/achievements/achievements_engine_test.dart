import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/di/app_scope.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/database_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/achievements/application/achievement_service.dart';
import 'package:levelup_test/features/achievements/data/achievement_catalog.dart';
import 'package:levelup_test/features/achievements/data/achievement_repository.dart';
import 'package:levelup_test/features/achievements/models/achievement_unlock_record.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/progress/application/progress_service.dart';
import 'package:levelup_test/features/progress/data/progress_repository.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/features/statistics/application/statistics_service.dart';
import 'package:levelup_test/features/statistics/data/statistics_repository.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/verified_squat_frames.dart';

WorkoutResult _workout({
  required String sessionId,
  required DateTime completedAt,
  ChallengeType context = ChallengeType.unlockChallenge,
  int reps = 5,
  String source = 'camera',
}) {
  return WorkoutResult(
    sessionId: sessionId,
    requestId: 'req-$sessionId',
    challengeId: 'squat_5',
    challengeContext: context,
    exerciseType: ExerciseType.squats,
    targetPackage: context == ChallengeType.freeWorkout
        ? null
        : ChannelConstants.targetYouTube,
    completedRepetitions: reps,
    duration: const Duration(seconds: 25),
    completedAt: completedAt,
    eligibleForAccess: context == ChallengeType.unlockChallenge,
    accessDurationSeconds: context == ChallengeType.unlockChallenge ? 300 : 0,
    source: source,
  );
}

class _FailingReadAchievementRepo implements IAchievementRepository {
  @override
  Future<List<AchievementUnlockRecord>> getUnlockedRecords() async =>
      throw StateError('SQLite achievement read failed');

  @override
  Future<bool> recordUnlockIfAbsent(AchievementUnlockRecord record) async =>
      throw StateError('SQLite achievement read failed');
}

class _FailingWriteAchievementRepo implements IAchievementRepository {
  @override
  Future<List<AchievementUnlockRecord>> getUnlockedRecords() async => const [];

  @override
  Future<bool> recordUnlockIfAbsent(AchievementUnlockRecord record) async =>
      throw StateError('SQLite achievement write failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late LevelUpDatabase db;
  late WorkoutHistoryRepository historyRepo;
  late AccessAttemptRepository accessRepo;
  late SqliteProgressRepository progressRepo;
  late ProgressService progressService;
  late SqliteStatisticsRepository statsRepo;
  late StatisticsService statsService;
  late SqliteAchievementRepository achievementRepo;
  late AchievementService achievementService;
  late DateTime currentNow;

  setUp(() async {
    currentNow = DateTime(2026, 11, 25, 14, 0);
    db = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: inMemoryDatabasePath,
    );
    await db.database;

    historyRepo = WorkoutHistoryRepository(databaseManager: db);
    accessRepo = AccessAttemptRepository(databaseManager: db);
    progressRepo = SqliteProgressRepository(databaseManager: db);
    progressService = ProgressService(
      repository: progressRepo,
      historyRepository: historyRepo,
      clock: () => currentNow,
    );
    await progressService.initialize();

    statsRepo = SqliteStatisticsRepository(databaseManager: db);
    statsService = StatisticsService(
      repository: statsRepo,
      progressService: progressService,
      clock: () => currentNow,
    );
    await statsService.initialize();

    achievementRepo = SqliteAchievementRepository(databaseManager: db);
    achievementService = AchievementService(
      repository: achievementRepo,
      statisticsService: statsService,
      progressService: progressService,
      clock: () => currentNow,
    );
  });

  tearDown(() async {
    achievementService.dispose();
    statsService.dispose();
    progressService.dispose();
    await db.close();
  });

  group('Module 11A — Achievements Engine & Persistent Badges', () {
    test('1. New user starts with all 6 achievements locked and zero progress', () async {
      final state = await achievementService.initialize();

      expect(state.hasError, isFalse);
      expect(state.totalCount, 6);
      expect(state.unlockedCount, 0);
      expect(state.unlockedAchievements, isEmpty);
      expect(state.lockedAchievements.length, 6);
      expect(state.recentlyUnlocked, isEmpty);
      expect(
        state.achievements
            .where((a) => a.id != AchievementCatalog.reachLevelTwoId)
            .every((a) => a.clampedCurrentValue == 0),
        isTrue,
      );
      expect(
        state.achievements
            .firstWhere((a) => a.id == AchievementCatalog.reachLevelTwoId)
            .clampedCurrentValue,
        1,
      );
    });

    test('2-8 & 20. Milestones unlock accurately (first_workout, five_workouts, twenty_five_squats, first_unlock, three_day_streak, reach_level_two) and progress updates', () async {
      // Day 1: 1st workout + confirmed unlock -> unlocks first_workout & first_unlock
      final day1 = DateTime(2026, 11, 23, 10, 0);
      currentNow = day1;
      final w1 = _workout(sessionId: 'w1', completedAt: day1);
      await historyRepo.saveCompletedWorkout(w1);
      await accessRepo.createAttemptIfAbsent(
        sessionId: 'w1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: day1,
      );
      await accessRepo.markConfirmed(
        sessionId: 'w1',
        confirmedAt: day1,
        unlockUntil: day1.add(const Duration(minutes: 5)),
      );
      await progressService.recordCompletedWorkout(w1);
      await statsService.refresh();

      var state = await achievementService.evaluateAndRefresh();
      expect(state.unlockedCount, 2);
      expect(
        state.unlockedAchievements.map((a) => a.id),
        containsAll([
          AchievementCatalog.firstWorkoutId,
          AchievementCatalog.firstUnlockId,
        ]),
      );
      final fiveProg = state.achievements
          .firstWhere((a) => a.id == AchievementCatalog.fiveWorkoutsId);
      expect(fiveProg.clampedCurrentValue, 1);
      expect(fiveProg.targetValue, 5);

      // Day 2: 2nd workout -> Level 2 (100 XP) -> reach_level_two unlocks
      final day2 = DateTime(2026, 11, 24, 10, 0);
      currentNow = day2;
      final w2 = _workout(sessionId: 'w2', completedAt: day2);
      await historyRepo.saveCompletedWorkout(w2);
      await progressService.recordCompletedWorkout(w2);
      await statsService.refresh();

      state = await achievementService.evaluateAndRefresh();
      expect(
        state.unlockedAchievements.map((a) => a.id),
        contains(AchievementCatalog.reachLevelTwoId),
      );
      expect(
        state.recentlyUnlocked.map((r) => r.achievementId),
        equals([AchievementCatalog.reachLevelTwoId]),
      );

      // Day 3: 3 more workouts (total 5 workouts, 25 squats, 3-day streak)
      final day3 = DateTime(2026, 11, 25, 10, 0);
      currentNow = day3;
      for (final id in ['w3', 'w4', 'w5']) {
        final w = _workout(
          sessionId: id,
          completedAt: day3,
          context: ChallengeType.freeWorkout,
        );
        await historyRepo.saveCompletedWorkout(w);
        await progressService.recordCompletedWorkout(w);
      }
      await statsService.refresh();

      state = await achievementService.evaluateAndRefresh();
      expect(state.unlockedCount, 6);
      expect(state.lockedAchievements, isEmpty);
      expect(
        state.recentlyUnlocked.map((r) => r.achievementId),
        containsAll([
          AchievementCatalog.fiveWorkoutsId,
          AchievementCatalog.twentyFiveSquatsId,
          AchievementCatalog.threeDayStreakId,
        ]),
      );
    });

    test('6, 9-12. Prepared/rejected attempts, cancelled workouts, and simulated workouts do not unlock; Free Workout counts for workouts only', () async {
      // Cancelled session
      final challengeService = ChallengeService();
      final sessionManager = WorkoutSessionManager(
        challengeService: challengeService,
        clock: () => currentNow,
      );
      final req = challengeService.createFreeWorkoutRequest();
      final s = sessionManager.createSession(req);
      sessionManager.startSession(s.sessionId);
      sessionManager.updateVerifiedProgress(s.sessionId, cumulativeReps: 3);
      sessionManager.cancelSession(s.sessionId);
      sessionManager.dispose();

      // Prepared & rejected access attempts
      await accessRepo.createAttemptIfAbsent(
        sessionId: 'prep-1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );
      await accessRepo.createAttemptIfAbsent(
        sessionId: 'rej-1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );
      await accessRepo.markDefinitivelyRejected(
        sessionId: 'rej-1',
        reason: 'Focus off',
      );

      // Simulated workout (not rewarded XP by ProgressService)
      final sim = _workout(
        sessionId: 'sim-1',
        completedAt: currentNow,
        context: ChallengeType.freeWorkout,
        source: 'simulated',
      );
      await progressService.recordCompletedWorkout(sim);
      await statsService.refresh();
      var state = await achievementService.evaluateAndRefresh();
      expect(state.unlockedCount, 0);

      // Real Free Workout -> unlocks first_workout, NOT first_unlock
      final free = _workout(
        sessionId: 'free-1',
        completedAt: currentNow,
        context: ChallengeType.freeWorkout,
      );
      await historyRepo.saveCompletedWorkout(free);
      await progressService.recordCompletedWorkout(free);
      await statsService.refresh();

      state = await achievementService.evaluateAndRefresh();
      expect(
        state.unlockedAchievements.map((a) => a.id),
        equals([AchievementCatalog.firstWorkoutId]),
      );
    });

    test('13-14. Repeated and concurrent evaluations are exactly-once and never duplicate records', () async {
      final w = _workout(sessionId: 'conc-1', completedAt: currentNow);
      await historyRepo.saveCompletedWorkout(w);
      await progressService.recordCompletedWorkout(w);
      await statsService.refresh();

      final results = await Future.wait([
        achievementService.evaluateAndRefresh(),
        achievementService.evaluateAndRefresh(),
        achievementService.evaluateAndRefresh(),
      ]);

      expect(results.first.unlockedCount, 1);
      final rows = await (await db.database).query(DatabaseConstants.tableAchievements);
      expect(rows.length, 1);

      // Subsequent evaluation has empty recentlyUnlocked
      final next = await achievementService.evaluateAndRefresh();
      expect(next.recentlyUnlocked, isEmpty);
      expect(next.unlockedCount, 1);
    });

    test('15-19. App restart preserves achievements; historical workouts evaluate without fabricating timestamps or retroactive XP', () async {
      final tempDir = await Directory.systemTemp.createTemp('levelup_11a_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dbPath = p.join(tempDir.path, 'levelup_11a.db');

      // Seed historical workout BEFORE ProgressService epoch exists (pre-Module 09)
      final oldTs = DateTime(2025, 1, 1, 12, 0);
      final seedDb = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final seedHistory = WorkoutHistoryRepository(databaseManager: seedDb);
      await seedHistory.saveCompletedWorkout(
        _workout(sessionId: 'hist-1', completedAt: oldTs),
      );
      await seedDb.close();

      // Boot AppScope 1 at currentNow
      const channel = MethodChannel(ChannelConstants.controlChannel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var grantCount = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == ChannelConstants.methodGetState) {
          return {
            ChannelConstants.keyTarget: ChannelConstants.targetYouTube,
            ChannelConstants.keyEnabled: true,
            ChannelConstants.keyUnlockUntil: 0,
            ChannelConstants.keyServiceEnabled: true,
          };
        }
        if (call.method == ChannelConstants.methodGrantAccess) {
          grantCount++;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      Future<AppScope> bootScope() async {
        final sDb = LevelUpDatabase(
          databaseFactory: databaseFactoryFfi,
          customPath: dbPath,
        );
        final scope = AppScope.production(
          database: sDb,
          nativeBridge: const NativeBridge(),
          cameraChecker: MockCameraPermissionChecker(
            status: CameraPermissionStatus.granted,
          ),
          clock: () => currentNow,
        );
        await scope.initialize();
        return scope;
      }

      final scope1 = await bootScope();
      // Historical workout unlocks first_workout using actual evaluation time (not 2025-01-01)
      // and awards 0 retroactive XP and 0 native grants.
      expect(scope1.achievementService.currentState.unlockedCount, 1);
      final unlocked =
          scope1.achievementService.currentState.unlockedAchievements.first;
      expect(unlocked.id, AchievementCatalog.firstWorkoutId);
      expect(unlocked.unlockedAt, currentNow.toUtc());
      expect(scope1.progressService.currentState.totalXp, 0);
      expect(grantCount, 0);
      await scope1.dispose();

      // Restart AppScope 2 later -> badge stays unlocked with original unlockedAt
      final laterNow = currentNow.add(const Duration(days: 5));
      currentNow = laterNow;
      final scope2 = await bootScope();
      expect(scope2.achievementService.currentState.unlockedCount, 1);
      expect(scope2.achievementService.currentState.recentlyUnlocked, isEmpty);
      expect(
        scope2.achievementService.currentState.unlockedAchievements.first.unlockedAt,
        DateTime(2026, 11, 25, 14, 0).toUtc(),
      );
      await scope2.dispose();
    });

    test('21. Previously unlocked three_day_streak remains unlocked after streak resets', () async {
      // Build 3-day streak
      for (var i = 0; i < 3; i++) {
        final d = DateTime(2026, 11, 23 + i, 10, 0);
        currentNow = d;
        final w = _workout(sessionId: 'st-$i', completedAt: d);
        await historyRepo.saveCompletedWorkout(w);
        await progressService.recordCompletedWorkout(w);
      }
      await statsService.refresh();
      var state = await achievementService.evaluateAndRefresh();
      expect(
        state.unlockedAchievements.map((a) => a.id),
        contains(AchievementCatalog.threeDayStreakId),
      );

      // Advance clock 10 days -> currentStreak resets to 0
      currentNow = DateTime(2026, 12, 5, 10, 0);
      await progressService.refresh();
      await statsService.refresh();
      expect(progressService.currentState.currentStreak, 0);

      state = await achievementService.evaluateAndRefresh();
      expect(
        state.unlockedAchievements.map((a) => a.id),
        contains(AchievementCatalog.threeDayStreakId),
      );
    });

    test('22-23. Database read/write failures propagate and do not partially unlock', () async {
      final readFailService = AchievementService(
        repository: _FailingReadAchievementRepo(),
        statisticsService: statsService,
        progressService: progressService,
        clock: () => currentNow,
      );
      await expectLater(readFailService.evaluateAndRefresh(), throwsStateError);
      expect(readFailService.currentState.hasError, isTrue);
      readFailService.dispose();

      final w = _workout(sessionId: 'wf-1', completedAt: currentNow);
      await historyRepo.saveCompletedWorkout(w);
      await statsService.refresh();

      final writeFailService = AchievementService(
        repository: _FailingWriteAchievementRepo(),
        statisticsService: statsService,
        progressService: progressService,
        clock: () => currentNow,
      );
      await expectLater(writeFailService.evaluateAndRefresh(), throwsStateError);
      expect(writeFailService.currentState.unlockedCount, 0);
      expect(writeFailService.currentState.hasError, isTrue);
      writeFailService.dispose();
    });

    test('24-25. Achievement evaluation with AppScope.production does not loop or grant XP/access', () async {
      const channel = MethodChannel(ChannelConstants.controlChannel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var grantCount = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == ChannelConstants.methodGetState) {
          return {
            ChannelConstants.keyTarget: ChannelConstants.targetYouTube,
            ChannelConstants.keyEnabled: true,
            ChannelConstants.keyUnlockUntil: 0,
            ChannelConstants.keyServiceEnabled: true,
          };
        }
        if (call.method == ChannelConstants.methodGrantAccess) {
          grantCount++;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final scope = AppScope.production(
        database: LevelUpDatabase(
          databaseFactory: databaseFactoryFfi,
          customPath: inMemoryDatabasePath,
        ),
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(
          status: CameraPermissionStatus.granted,
        ),
        clock: () => currentNow,
      );
      await scope.initialize();

      await scope.coordinator.launchFreeWorkout();
      await completeVerifiedSquats(scope.coordinator);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await scope.refresh();
      expect(grantCount, 0);
      expect(scope.progressService.currentState.totalXp, 50); // No bonus XP
      expect(scope.achievementService.currentState.unlockedCount, 1);

      await scope.dispose();
    });
  });
}
