import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/adapters/core_insights_adapter.dart';
import 'package:levelup_test/app/di/app_scope.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/achievements/application/achievement_service.dart';
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
import 'package:levelup_test/features/statistics/models/access_duration_statistics.dart';
import 'package:levelup_test/features/statistics/models/daily_activity_stats.dart';
import 'package:levelup_test/features/statistics/models/unlock_statistics.dart';
import 'package:levelup_test/features/statistics/models/workout_statistics.dart';
import 'package:levelup_test/models/access_attempt_record.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/verified_squat_frames.dart';

class _StubFocusGateway implements DashboardFocusGateway {
  @override
  Future<void> disable() async {}

  @override
  Future<void> enable({String? target}) async {}

  @override
  Future<FocusSnapshot> read() async => const FocusSnapshot(
        enabled: true,
        serviceEnabled: true,
        targets: [ChannelConstants.targetYouTube],
      );
}

class _InMemoryHistoryRepo implements IWorkoutHistoryRepository {
  final List<WorkoutResult> items = [];

  @override
  Future<int> countCompletedWorkouts() async => items.length;

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async =>
      items.reversed.take(limit).toList(growable: false);

  @override
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType}) async =>
      items.fold<int>(0, (s, w) => s + w.completedRepetitions);

  @override
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId) async =>
      items.where((w) => w.sessionId == sessionId).firstOrNull;

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      items;

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {
    if (items.any((w) => w.sessionId == result.sessionId)) return;
    items.add(result);
  }
}

class _InMemoryAccessRepo implements IAccessAttemptRepository {
  final Map<String, AccessAttemptRecord> items = {};

  @override
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  }) async {
    return items.putIfAbsent(
      sessionId,
      () => AccessAttemptRecord(
        sessionId: sessionId,
        targetPackage: targetPackage,
        durationSeconds: durationSeconds,
        state: AccessAttemptState.prepared,
        attemptedAt: attemptedAt,
      ),
    );
  }

  @override
  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId) async =>
      items[sessionId];

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async =>
      items.values.toList(growable: false);

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) async {
    final prev = items[sessionId]!;
    return items[sessionId] = AccessAttemptRecord(
      sessionId: prev.sessionId,
      targetPackage: prev.targetPackage,
      durationSeconds: prev.durationSeconds,
      state: AccessAttemptState.confirmed,
      attemptedAt: prev.attemptedAt,
      confirmedAt: confirmedAt,
      unlockUntil: unlockUntil,
    );
  }

  @override
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  }) async {
    final prev = items[sessionId]!;
    return items[sessionId] = AccessAttemptRecord(
      sessionId: prev.sessionId,
      targetPackage: prev.targetPackage,
      durationSeconds: prev.durationSeconds,
      state: AccessAttemptState.definitivelyRejected,
      attemptedAt: prev.attemptedAt,
      failureReason: reason,
    );
  }

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) async {
    final prev = items[sessionId]!;
    return items[sessionId] = AccessAttemptRecord(
      sessionId: prev.sessionId,
      targetPackage: prev.targetPackage,
      durationSeconds: prev.durationSeconds,
      state: AccessAttemptState.uncertain,
      attemptedAt: prev.attemptedAt,
      failureReason: reason,
    );
  }
}

class _InMemoryStatsRepo implements IStatisticsRepository {
  final _InMemoryHistoryRepo historyRepo;
  final _InMemoryAccessRepo accessRepo;

  _InMemoryStatsRepo({
    required this.historyRepo,
    required this.accessRepo,
  });

  static const _untrusted = {'simulated', 'preview', 'ui_only', 'mock'};

  @override
  Future<WorkoutStatistics> loadWorkoutStatistics({required DateTime now}) async {
    final bySession = {
      for (final w in historyRepo.items)
        if (!_untrusted.contains(w.source)) w.sessionId: w,
    };
    var reps = 0, unlock = 0, free = 0;
    for (final w in bySession.values) {
      reps += w.completedRepetitions;
      if (w.challengeContext == ChallengeType.unlockChallenge) {
        unlock++;
      } else {
        free++;
      }
    }
    return WorkoutStatistics(
      allTimeCompleted: bySession.length,
      todayCompleted: bySession.length,
      thisWeekCompleted: bySession.length,
      totalVerifiedRepetitions: reps,
      unlockChallengesCompleted: unlock,
      freeWorkoutsCompleted: free,
    );
  }

  @override
  Future<UnlockStatistics> loadUnlockStatistics({required DateTime now}) async {
    final confirmed = accessRepo.items.values.where((a) => a.isConfirmed).length;
    return UnlockStatistics(
      todayConfirmed: confirmed,
      thisWeekConfirmed: confirmed,
      allTimeConfirmed: confirmed,
    );
  }

  @override
  Future<AccessDurationStatistics> loadAccessDurationStatistics({
    required DateTime now,
  }) async =>
      AccessDurationStatistics.empty;

  @override
  Future<List<DailyActivityStats>> loadWeeklyActivity({
    required DateTime now,
  }) async =>
      const [];
}

class _FailingAchievementRepo implements IAchievementRepository {
  @override
  Future<List<AchievementUnlockRecord>> getUnlockedRecords() async =>
      throw StateError('SQLite achievements read failed');

  @override
  Future<bool> recordUnlockIfAbsent(AchievementUnlockRecord record) async =>
      throw StateError('SQLite achievements write failed');
}

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

Future<void> _settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Module 11B — Real Achievements UI Integration Tests', () {
    testWidgets('1. New user displays 0 / 6 locked badges, unlocks milestones live across Unlock Challenge, Free Workout, Level 2, and 3-day streak', (tester) async {
      var now = DateTime(2026, 11, 23, 10, 0);
      final historyRepo = _InMemoryHistoryRepo();
      final accessRepo = _InMemoryAccessRepo();
      final progressService = ProgressService(
        repository: InMemoryProgressRepository(),
        historyRepository: historyRepo,
        clock: () => now,
      );
      await progressService.initialize();

      final statsService = StatisticsService(
        repository: _InMemoryStatsRepo(
          historyRepo: historyRepo,
          accessRepo: accessRepo,
        ),
        progressService: progressService,
        clock: () => now,
      );
      await statsService.initialize();

      final achievementService = AchievementService(
        repository: InMemoryAchievementRepository(),
        statisticsService: statsService,
        progressService: progressService,
        clock: () => now,
      );
      await achievementService.initialize();

      final adapter = CoreInsightsAdapter(
        historyRepo: historyRepo,
        accessRepo: accessRepo,
        progressService: progressService,
        statisticsService: statsService,
        achievementService: achievementService,
        clock: () => now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: _StubFocusGateway(),
            progressStream: progressService.stateStream,
            statisticsStream: statsService.snapshotStream,
            achievementStream: achievementService.stateStream,
            loadInsights: () => adapter.loadInsights(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();

      expect(find.byKey(const ValueKey('achievements_card')), findsOneWidget);
      expect(find.text('Achievements: 0 / 6'), findsOneWidget);
      expect(find.text('First Step'), findsOneWidget);
      expect(find.text('Getting Stronger'), findsOneWidget);
      expect(find.text('Squat Starter'), findsOneWidget);
      expect(find.text('Focus Breakthrough'), findsOneWidget);
      expect(find.text('Consistency'), findsOneWidget);
      expect(find.text('Level Up'), findsOneWidget);

      // Day 1: 1st Unlock Challenge + confirmed unlock -> 2 / 6
      final w1 = _workout(sessionId: 'u1', completedAt: now);
      await historyRepo.saveCompletedWorkout(w1);
      await accessRepo.createAttemptIfAbsent(
        sessionId: 'u1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: now,
      );
      await accessRepo.markConfirmed(
        sessionId: 'u1',
        confirmedAt: now,
        unlockUntil: now.add(const Duration(minutes: 5)),
      );
      await progressService.recordCompletedWorkout(w1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Achievements: 2 / 6'), findsOneWidget);
      expect(find.textContaining('Unlocked · '), findsNWidgets(2));
      expect(find.textContaining('Achievement unlocked:'), findsOneWidget);
      await tester.pumpAndSettle();

      // Day 2: Free Workout -> Level 2 (100 XP) -> 3 / 6
      now = DateTime(2026, 11, 24, 10, 0);
      final w2 = _workout(
        sessionId: 'f2',
        completedAt: now,
        context: ChallengeType.freeWorkout,
      );
      await historyRepo.saveCompletedWorkout(w2);
      await progressService.recordCompletedWorkout(w2);
      await statsService.refresh();
      await achievementService.evaluateAndRefresh();
      await tester.pumpAndSettle();

      expect(find.text('Achievements: 3 / 6'), findsOneWidget);

      // Day 3: 3 more workouts -> 5 workouts, 25 squats, 3-day streak -> 6 / 6
      now = DateTime(2026, 11, 25, 10, 0);
      for (final id in ['f3', 'f4', 'f5']) {
        final w = _workout(
          sessionId: id,
          completedAt: now,
          context: ChallengeType.freeWorkout,
        );
        await historyRepo.saveCompletedWorkout(w);
        await progressService.recordCompletedWorkout(w);
      }
      await statsService.refresh();
      await achievementService.evaluateAndRefresh();
      await tester.pumpAndSettle();

      expect(find.text('Achievements: 6 / 6'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      achievementService.dispose();
      statsService.dispose();
      progressService.dispose();
    });

    testWidgets('2. Excludes simulated workouts and failed/uncertain unlocks; keeps Consistency unlocked after streak reset', (tester) async {
      var now = DateTime(2026, 11, 23, 10, 0);
      final historyRepo = _InMemoryHistoryRepo();
      final accessRepo = _InMemoryAccessRepo();
      final progressService = ProgressService(
        repository: InMemoryProgressRepository(),
        historyRepository: historyRepo,
        clock: () => now,
      );
      await progressService.initialize();

      // Simulated workout MUST NOT unlock First Step
      await historyRepo.saveCompletedWorkout(
        _workout(
          sessionId: 'sim-1',
          completedAt: now,
          context: ChallengeType.freeWorkout,
          source: 'simulated',
        ),
      );
      // Rejected & uncertain access attempts MUST NOT unlock Focus Breakthrough
      await accessRepo.createAttemptIfAbsent(
        sessionId: 'rej-1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: now,
      );
      await accessRepo.markDefinitivelyRejected(
        sessionId: 'rej-1',
        reason: 'Focus off',
      );
      await accessRepo.createAttemptIfAbsent(
        sessionId: 'unc-1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: now,
      );
      await accessRepo.markUncertain(
        sessionId: 'unc-1',
        reason: 'IPC timeout',
      );

      final statsService = StatisticsService(
        repository: _InMemoryStatsRepo(
          historyRepo: historyRepo,
          accessRepo: accessRepo,
        ),
        progressService: progressService,
        clock: () => now,
      );
      await statsService.initialize();
      final achievementService = AchievementService(
        repository: InMemoryAchievementRepository(),
        statisticsService: statsService,
        progressService: progressService,
        clock: () => now,
      );
      await achievementService.initialize();

      final adapter = CoreInsightsAdapter(
        historyRepo: historyRepo,
        accessRepo: accessRepo,
        progressService: progressService,
        statisticsService: statsService,
        achievementService: achievementService,
        clock: () => now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: _StubFocusGateway(),
            progressStream: progressService.stateStream,
            statisticsStream: statsService.snapshotStream,
            achievementStream: achievementService.stateStream,
            loadInsights: () => adapter.loadInsights(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();

      expect(find.text('Achievements: 0 / 6'), findsOneWidget);

      // Build 3-day streak -> Consistency unlocks, then reset streak -> remains unlocked
      for (var i = 0; i < 3; i++) {
        final d = DateTime(2026, 11, 23 + i, 10, 0);
        now = d;
        final w = _workout(
          sessionId: 'st-$i',
          completedAt: d,
          context: ChallengeType.freeWorkout,
        );
        await historyRepo.saveCompletedWorkout(w);
        await progressService.recordCompletedWorkout(w);
      }
      await statsService.refresh();
      await achievementService.evaluateAndRefresh();
      // Reset streak by advancing 10 days
      now = DateTime(2026, 12, 5, 10, 0);
      await progressService.refresh();
      await statsService.refresh();
      await achievementService.evaluateAndRefresh();
      await tester.pumpAndSettle();

      // Consistency (and First Step, Level Up) remain unlocked despite 0 currentStreak
      expect(find.text('Achievements: 3 / 6'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      achievementService.dispose();
      statsService.dispose();
      progressService.dispose();
    });

    testWidgets('3. SQLite error shows honest error, EN/RU/KK localization works, and stream disposal/loop safety holds', (tester) async {
      final now = DateTime(2026, 11, 25, 14, 0);
      final progressService = ProgressService(
        repository: InMemoryProgressRepository(),
        clock: () => now,
      );
      await progressService.initialize();

      final statsService = StatisticsService(
        repository: _InMemoryStatsRepo(
          historyRepo: _InMemoryHistoryRepo(),
          accessRepo: _InMemoryAccessRepo(),
        ),
        progressService: progressService,
        clock: () => now,
      );
      await statsService.initialize();

      final failingAch = AchievementService(
        repository: _FailingAchievementRepo(),
        statisticsService: statsService,
        progressService: progressService,
        clock: () => now,
      );
      final adapter = CoreInsightsAdapter(
        historyRepo: _InMemoryHistoryRepo(),
        accessRepo: _InMemoryAccessRepo(),
        progressService: progressService,
        statisticsService: statsService,
        achievementService: failingAch,
        clock: () => now,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: _StubFocusGateway(),
            achievementStream: failingAch.stateStream,
            loadInsights: () => adapter.loadInsights(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();

      expect(find.byKey(const ValueKey('achievements_error')), findsOneWidget);
      expect(find.text('Achievements could not be loaded.'), findsOneWidget);

      // Verify RU & KK localization renders without English fallback
      final okAch = AchievementService(
        repository: InMemoryAchievementRepository(),
        statisticsService: statsService,
        progressService: progressService,
        clock: () => now,
      );
      await okAch.initialize();
      final okAdapter = CoreInsightsAdapter(
        historyRepo: _InMemoryHistoryRepo(),
        accessRepo: _InMemoryAccessRepo(),
        progressService: progressService,
        statisticsService: statsService,
        achievementService: okAch,
        clock: () => now,
      );

      for (final (lang, navLabel, expectedTitle) in [
        (DashboardLanguage.ru, 'Прогресс', 'Первый шаг'),
        (DashboardLanguage.kk, 'Ілгерілеу', 'Алғашқы қадам'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: LevelUpHomeScreen(
              key: ValueKey(lang),
              gateway: _StubFocusGateway(),
              language: lang,
              achievementStream: okAch.stateStream,
              loadInsights: () => okAdapter.loadInsights(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(navLabel));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pump();
        expect(find.text(expectedTitle), findsOneWidget);
      }

      // Safe disposal mid-refresh
      final completer = Completer<DashboardInsights>();
      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: _StubFocusGateway(),
            loadInsights: () => completer.future,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      completer.complete(const DashboardInsights(historyReady: true));
      await tester.pump();

      okAch.dispose();
      failingAch.dispose();
      statsService.dispose();
      progressService.dispose();
    });

    testWidgets('4. Achievements persist across AppScope.production restart without fabricating dates or replaying SnackBars', (tester) async {
      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('levelup_11b_'),
      );
      addTearDown(() => tester.runAsync(() => tempDir!.delete(recursive: true)));
      final dbPath = p.join(tempDir!.path, 'levelup_11b.db');

      const channel = MethodChannel(ChannelConstants.controlChannel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final now = DateTime(2026, 11, 25, 14, 0);

      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case ChannelConstants.methodGetState:
            return {
              ChannelConstants.keyTarget: ChannelConstants.targetYouTube,
              ChannelConstants.keyEnabled: true,
              ChannelConstants.keyUnlockUntil: 0,
              ChannelConstants.keyServiceEnabled: true,
            };
          case ChannelConstants.methodGrantAccess:
            return now.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      Future<AppScope> bootScope() async {
        final db = LevelUpDatabase(
          databaseFactory: databaseFactoryFfi,
          customPath: dbPath,
        );
        final scope = AppScope.production(
          database: db,
          nativeBridge: const NativeBridge(),
          cameraChecker: MockCameraPermissionChecker(
            status: CameraPermissionStatus.granted,
          ),
          clock: () => now,
        );
        await scope.initialize();
        return scope;
      }

      final scope1 = (await tester.runAsync(bootScope))!;
      await tester.runAsync(() async {
        await scope1.coordinator.launchFreeWorkout();
        await completeVerifiedSquats(scope1.coordinator);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await scope1.refresh();
      });
      expect(scope1.achievementService.currentState.unlockedCount, 1);
      await tester.runAsync(() async => scope1.dispose());

      // Restart AppScope against same SQLite DB
      final scope2 = (await tester.runAsync(bootScope))!;
      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: scope2.focusGateway,
            progressStream: scope2.progressService.stateStream,
            statisticsStream: scope2.statisticsService.snapshotStream,
            achievementStream: scope2.achievementService.stateStream,
            loadInsights: () => scope2.insightsAdapter.loadInsights(),
          ),
        ),
      );
      await _settleAsync(tester);

      // Historical/persisted unlock on startup MUST NOT replay SnackBar
      expect(find.textContaining('Achievement unlocked:'), findsNothing);

      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();

      expect(find.text('Achievements: 1 / 6'), findsOneWidget);
      expect(find.textContaining('Unlocked · '), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => scope2.dispose());
    });

    test('5. SqliteStatisticsRepository excludes simulated and preview workouts from production achievements', () async {
      final now = DateTime(2026, 11, 25, 14, 0);
      final db = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await db.database;

      final sqlHistory = WorkoutHistoryRepository(databaseManager: db);
      final sqlProgress = ProgressService(
        repository: SqliteProgressRepository(databaseManager: db),
        historyRepository: sqlHistory,
        clock: () => now,
      );
      await sqlProgress.initialize();

      await sqlHistory.saveCompletedWorkout(
        _workout(
          sessionId: 'sim-sql-1',
          completedAt: now,
          context: ChallengeType.freeWorkout,
          source: 'simulated',
        ),
      );
      await sqlHistory.saveCompletedWorkout(
        _workout(
          sessionId: 'prev-sql-1',
          completedAt: now,
          context: ChallengeType.freeWorkout,
          source: 'preview',
        ),
      );

      final statsService = StatisticsService(
        repository: SqliteStatisticsRepository(databaseManager: db),
        progressService: sqlProgress,
        clock: () => now,
      );
      await statsService.initialize();

      final achievementService = AchievementService(
        repository: SqliteAchievementRepository(databaseManager: db),
        statisticsService: statsService,
        progressService: sqlProgress,
        clock: () => now,
      );
      final state = await achievementService.initialize();

      expect(statsService.currentSnapshot.workouts.allTimeCompleted, 0);
      expect(state.unlockedCount, 0);

      achievementService.dispose();
      statsService.dispose();
      sqlProgress.dispose();
      await db.close();
    });
  });
}
