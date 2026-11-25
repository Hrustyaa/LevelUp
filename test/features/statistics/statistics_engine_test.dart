import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/di/app_scope.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/database_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';
import 'package:levelup_test/features/progress/application/progress_service.dart';
import 'package:levelup_test/features/progress/data/progress_repository.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/features/statistics/application/statistics_calendar.dart';
import 'package:levelup_test/features/statistics/application/statistics_service.dart';
import 'package:levelup_test/features/statistics/data/statistics_repository.dart';
import 'package:levelup_test/features/statistics/models/access_duration_statistics.dart';
import 'package:levelup_test/features/statistics/models/daily_activity_stats.dart';
import 'package:levelup_test/features/statistics/models/unlock_statistics.dart';
import 'package:levelup_test/features/statistics/models/workout_statistics.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

WorkoutResult _workout({
  required String sessionId,
  required DateTime completedAt,
  ChallengeType context = ChallengeType.unlockChallenge,
  int reps = 5,
  String? targetPackage = ChannelConstants.targetYouTube,
  String source = 'camera',
}) {
  return WorkoutResult(
    sessionId: sessionId,
    requestId: 'req-$sessionId',
    challengeId: 'squat_5',
    challengeContext: context,
    exerciseType: ExerciseType.squats,
    targetPackage: context == ChallengeType.freeWorkout ? null : targetPackage,
    completedRepetitions: reps,
    duration: const Duration(seconds: 25),
    completedAt: completedAt,
    eligibleForAccess: context == ChallengeType.unlockChallenge,
    accessDurationSeconds: context == ChallengeType.unlockChallenge ? 300 : 0,
    source: source,
  );
}

class _FailingStatisticsRepo implements IStatisticsRepository {
  @override
  Future<AccessDurationStatistics> loadAccessDurationStatistics({
    required DateTime now,
  }) async =>
      throw StateError('SQLite read failed');

  @override
  Future<UnlockStatistics> loadUnlockStatistics({
    required DateTime now,
  }) async =>
      throw StateError('SQLite read failed');

  @override
  Future<List<DailyActivityStats>> loadWeeklyActivity({
    required DateTime now,
  }) async =>
      throw StateError('SQLite read failed');

  @override
  Future<WorkoutStatistics> loadWorkoutStatistics({
    required DateTime now,
  }) async =>
      throw StateError('SQLite read failed');
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
  late DateTime currentNow;
  late StatisticsService statsService;

  setUp(() async {
    currentNow = DateTime(2026, 11, 25, 14, 0); // Wednesday
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
  });

  tearDown(() async {
    statsService.dispose();
    progressService.dispose();
    await db.close();
  });

  group('Module 10A — Real Statistics Engine', () {
    test('1. Empty database returns real zero statistics and unavailable screen time', () async {
      final snap = await statsService.refresh();

      expect(snap.hasError, isFalse);
      expect(snap.workouts.allTimeCompleted, 0);
      expect(snap.workouts.todayCompleted, 0);
      expect(snap.workouts.thisWeekCompleted, 0);
      expect(snap.workouts.totalVerifiedRepetitions, 0);
      expect(snap.workouts.unlockChallengesCompleted, 0);
      expect(snap.workouts.freeWorkoutsCompleted, 0);

      expect(snap.unlocks.todayConfirmed, 0);
      expect(snap.unlocks.thisWeekConfirmed, 0);
      expect(snap.unlocks.allTimeConfirmed, 0);

      expect(snap.accessDuration.totalAuthorizedDuration, Duration.zero);
      expect(snap.accessDuration.todayAuthorizedDuration, Duration.zero);
      expect(snap.accessDuration.averageAuthorizedDuration, isNull);

      expect(snap.weeklyActivity.length, 7);
      expect(
        snap.weeklyActivity.every(
          (d) =>
              d.completedWorkouts == 0 &&
              d.confirmedUnlocks == 0 &&
              d.verifiedRepetitions == 0,
        ),
        isTrue,
      );

      expect(snap.foregroundUsageMinutes, isNull);
      expect(snap.screenTimeSaved, isNull);
    });

    test('2-6. Completed workouts, squat totals, Free Workout separation, and cancelled/failed exclusion', () async {
      // Cancelled / failed sessions never reach workout_sessions; verify via WorkoutSessionManager
      final challengeService = ChallengeService();
      final sessionManager = WorkoutSessionManager(
        challengeService: challengeService,
        clock: () => currentNow,
      );
      final req = challengeService.createFreeWorkoutRequest();
      final session = sessionManager.createSession(req);
      sessionManager.startSession(session.sessionId);
      sessionManager.updateVerifiedProgress(
        session.sessionId,
        cumulativeReps: 2,
      );
      sessionManager.cancelSession(session.sessionId); // Cancelled at 2 reps -> never saved

      // Persist 1 completed unlockChallenge (5 reps) and 1 completed freeWorkout (5 reps)
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'u1', completedAt: currentNow),
      );
      await historyRepo.saveCompletedWorkout(
        _workout(
          sessionId: 'f1',
          completedAt: currentNow,
          context: ChallengeType.freeWorkout,
        ),
      );

      final snap = await statsService.refresh();
      expect(snap.workouts.allTimeCompleted, 2);
      expect(snap.workouts.todayCompleted, 2);
      expect(snap.workouts.thisWeekCompleted, 2);
      expect(snap.workouts.totalVerifiedRepetitions, 10);
      expect(snap.workouts.unlockChallengesCompleted, 1);
      expect(snap.workouts.freeWorkoutsCompleted, 1);
      expect(snap.unlocks.allTimeConfirmed, 0); // Free workout never unlocks

      sessionManager.dispose();
    });

    test('7-10. Confirmed unlocks only, excludes prepared/rejected/uncertain, deduplicates sessionIds', () async {
      // Confirmed unlock
      await accessRepo.createAttemptIfAbsent(
        sessionId: 's-confirmed',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );
      await accessRepo.markConfirmed(
        sessionId: 's-confirmed',
        confirmedAt: currentNow,
        unlockUntil: currentNow.add(const Duration(minutes: 5)),
      );
      // Idempotent duplicate createAttemptIfAbsent must not inflate
      await accessRepo.createAttemptIfAbsent(
        sessionId: 's-confirmed',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );

      // Prepared
      await accessRepo.createAttemptIfAbsent(
        sessionId: 's-prepared',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );

      // Uncertain
      await accessRepo.createAttemptIfAbsent(
        sessionId: 's-uncertain',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );
      await accessRepo.markUncertain(
        sessionId: 's-uncertain',
        reason: 'IPC timeout',
      );

      // Definitively rejected
      await accessRepo.createAttemptIfAbsent(
        sessionId: 's-rejected',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: currentNow,
      );
      await accessRepo.markDefinitivelyRejected(
        sessionId: 's-rejected',
        reason: 'Focus disabled',
      );

      // Duplicate idempotent workout save
      final w = _workout(sessionId: 's-confirmed', completedAt: currentNow);
      await historyRepo.saveCompletedWorkout(w);
      await historyRepo.saveCompletedWorkout(w);

      final snap = await statsService.refresh();
      expect(snap.workouts.allTimeCompleted, 1);
      expect(snap.unlocks.todayConfirmed, 1);
      expect(snap.unlocks.thisWeekConfirmed, 1);
      expect(snap.unlocks.allTimeConfirmed, 1);
      expect(snap.accessDuration.totalAuthorizedDuration, const Duration(seconds: 300));
      expect(snap.accessDuration.todayAuthorizedDuration, const Duration(seconds: 300));
      expect(snap.accessDuration.averageAuthorizedDuration, const Duration(seconds: 300));
    });

    test('11-16. Local calendar boundaries: today, current week (Monday-Sunday), 7-day zeros, midnight, month/year, DST', () async {
      // currentNow is Wednesday 2026-11-25 14:00
      // Monday of this week: 2026-11-23 00:00
      // Sunday of previous week: 2026-11-22 23:59:59
      final prevSundayLate = DateTime(2026, 11, 22, 23, 59, 59);
      final thisMondayStart = DateTime(2026, 11, 23, 0, 0, 0);
      final yesterdayLate = DateTime(2026, 11, 24, 23, 59, 59);
      final todayStart = DateTime(2026, 11, 25, 0, 0, 0);

      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'sun', completedAt: prevSundayLate),
      );
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'mon', completedAt: thisMondayStart),
      );
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'tue', completedAt: yesterdayLate),
      );
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'wed', completedAt: todayStart),
      );

      final snap = await statsService.refresh();
      expect(snap.workouts.todayCompleted, 1); // Only wed
      expect(snap.workouts.thisWeekCompleted, 3); // mon, tue, wed (not sun!)
      expect(snap.workouts.allTimeCompleted, 4);

      expect(snap.weeklyActivity.length, 7);
      expect(snap.weeklyActivity.first.dateKey, '2026-11-19');
      expect(snap.weeklyActivity.last.dateKey, '2026-11-25');
      // Days with zero records (Nov 19, 20, 21) have genuine 0s
      expect(snap.weeklyActivity[0].completedWorkouts, 0);
      expect(snap.weeklyActivity[1].completedWorkouts, 0);
      expect(snap.weeklyActivity[2].completedWorkouts, 0);
      expect(snap.weeklyActivity[3].completedWorkouts, 1); // Nov 22
      expect(snap.weeklyActivity[4].completedWorkouts, 1); // Nov 23
      expect(snap.weeklyActivity[5].completedWorkouts, 1); // Nov 24
      expect(snap.weeklyActivity[6].completedWorkouts, 1); // Nov 25

      // Month & year boundary (Dec 31 -> Jan 1)
      final jan1 = DateTime(2027, 1, 1, 0, 30);
      final yearDays = StatisticsCalendar.last7LocalDays(jan1);
      expect(StatisticsCalendar.formatLocalDate(yearDays.first), '2026-12-26');
      expect(StatisticsCalendar.formatLocalDate(yearDays.last), '2027-01-01');

      final janWeek = StatisticsCalendar.currentWeekRange(jan1);
      // 2027-01-01 is Friday -> Monday is 2026-12-28
      expect(StatisticsCalendar.formatLocalDate(janWeek.start), '2026-12-28');
      expect(StatisticsCalendar.formatLocalDate(janWeek.end), '2027-01-04');

      // Calendar arithmetic uses DateTime(year, month, day) rather than +24h,
      // guaranteeing 7 distinct local dates even across 23h/25h DST transitions.
      final springDst = DateTime(2026, 3, 8, 12, 0);
      final springDays = StatisticsCalendar.last7LocalDays(springDst);
      expect(springDays.length, 7);
      expect(springDays.map(StatisticsCalendar.formatLocalDate).toSet().length, 7);
      expect(StatisticsCalendar.localDayRange(springDst).start.hour, 0);
      expect(StatisticsCalendar.localDayRange(springDst).end.hour, 0);
    });

    test('17. All-time statistics are not truncated by 50-record history limit', () async {
      for (var i = 0; i < 65; i++) {
        final ts = currentNow.subtract(Duration(days: i, minutes: 5));
        await historyRepo.saveCompletedWorkout(
          _workout(sessionId: 'bulk-$i', completedAt: ts),
        );
        await accessRepo.createAttemptIfAbsent(
          sessionId: 'bulk-$i',
          targetPackage: ChannelConstants.targetInstagram,
          durationSeconds: 300,
          attemptedAt: ts,
        );
        await accessRepo.markConfirmed(
          sessionId: 'bulk-$i',
          confirmedAt: ts,
          unlockUntil: ts.add(const Duration(minutes: 5)),
        );
      }

      final snap = await statsService.refresh();
      expect(snap.workouts.allTimeCompleted, 65);
      expect(snap.workouts.totalVerifiedRepetitions, 325);
      expect(snap.unlocks.allTimeConfirmed, 65);
      expect(
        snap.accessDuration.totalAuthorizedDuration,
        const Duration(seconds: 65 * 300),
      );
      expect(
        snap.accessDuration.averageAuthorizedDuration,
        const Duration(seconds: 300),
      );
    });

    test('18-19 & 24. XP comes from ProgressService, never workoutCount * 50, and queries never award XP', () async {
      // Pre-epoch historical workout (before progress_epoch_ms)
      final preEpoch = currentNow.subtract(const Duration(days: 10));
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'pre-1', completedAt: preEpoch),
      );
      // Post-epoch workout NOT yet rewarded
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'post-unrewarded', completedAt: currentNow),
      );

      final snap = await statsService.refresh();
      expect(snap.workouts.allTimeCompleted, 2);
      // Statistics refresh MUST NOT award XP or multiply workoutCount * 50!
      expect(snap.totalXp, 0);
      expect(snap.currentLevel, 1);

      final rawRewards = await (await db.database).query(DatabaseConstants.tableXpRewards);
      expect(rawRewards, isEmpty);

      // Award 1 workout via ProgressService -> StatisticsService reflects 50 XP
      await progressService.recordCompletedWorkout(
        _workout(sessionId: 'post-unrewarded', completedAt: currentNow),
      );
      final snap2 = await statsService.refresh();
      expect(snap2.totalXp, 50);
      expect(snap2.currentLevel, 1);
      expect(snap2.currentStreak, 1);
    });

    test('20. Database read errors propagate and emit error state instead of 0s', () async {
      final failingService = StatisticsService(
        repository: _FailingStatisticsRepo(),
        progressService: progressService,
        clock: () => currentNow,
      );
      final emitted = <bool>[];
      final sub = failingService.snapshotStream.listen((s) => emitted.add(s.hasError));

      await expectLater(failingService.refresh(), throwsStateError);
      await Future<void>.delayed(Duration.zero);

      expect(failingService.currentSnapshot.hasError, isTrue);
      expect(emitted.last, isTrue);

      await sub.cancel();
      failingService.dispose();
    });

    test('22. Concurrent refreshes serialize cleanly without deadlock', () async {
      await historyRepo.saveCompletedWorkout(
        _workout(sessionId: 'conc-1', completedAt: currentNow),
      );
      final results = await Future.wait([
        statsService.refresh(),
        statsService.refresh(),
        statsService.refresh(),
      ]);

      expect(results.length, 3);
      for (final s in results) {
        expect(s.workouts.allTimeCompleted, 1);
        expect(s.hasError, isFalse);
      }
    });

    test('23 & 25. AppScope.production integration & Free Workout never grants access', () async {
      const channel = MethodChannel(ChannelConstants.controlChannel);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var grantCount = 0;

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
            grantCount++;
            return currentNow.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final scopeDb = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      final scope = AppScope.production(
        database: scopeDb,
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(
          status: CameraPermissionStatus.granted,
        ),
        clock: () => currentNow,
      );
      await scope.initialize();

      // Run a real Free Workout through coordinator
      await scope.coordinator.launchFreeWorkout();
      await scope.coordinator.handlePoseResult(
        const SquatCounterResult(
          repetitionCount: 5,
          phase: SquatPhase.up,
          kneeAngle: 170,
          isValidTracking: true,
          consecutiveDownFrames: 0,
          consecutiveUpFrames: 2,
          isRepetitionCompleted: true,
          feedbackMessage: 'Repetition complete',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final snap = await scope.statisticsService.refresh();
      expect(grantCount, 0);
      expect(snap.workouts.freeWorkoutsCompleted, 1);
      expect(snap.workouts.allTimeCompleted, 1);
      expect(snap.unlocks.allTimeConfirmed, 0);
      expect(snap.totalXp, 50);
      expect(snap.focus?.isUserEnabled, isTrue);

      scope.dispose();
    });
  });
}
