import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/di/app_scope.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';
import 'package:levelup_test/features/progress/application/progress_service.dart';
import 'package:levelup_test/features/progress/data/progress_repository.dart';
import 'package:levelup_test/features/progress/models/xp_reward_record.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/application/settings_service.dart';
import 'package:levelup_test/features/settings/data/settings_repository.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/models/access_attempt_record.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _InMemoryWorkoutHistoryRepo implements IWorkoutHistoryRepository {
  final List<WorkoutResult> workouts = [];

  @override
  Future<int> countCompletedWorkouts() async => workouts.length;

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async {
    final sorted = [...workouts]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return sorted.take(limit).toList();
  }

  @override
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType}) async =>
      workouts.fold<int>(0, (s, w) => s + w.completedRepetitions);

  @override
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId) async =>
      workouts.where((w) => w.sessionId == sessionId).firstOrNull;

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      workouts;

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {
    if (!workouts.any((w) => w.sessionId == result.sessionId)) {
      workouts.add(result);
    }
  }
}

class _InMemoryAccessAttemptRepo implements IAccessAttemptRepository {
  final Map<String, AccessAttemptRecord> records = {};

  @override
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  }) async {
    return records.putIfAbsent(
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
      records[sessionId];

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async =>
      records.values.toList();

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) async {
    final existing = records[sessionId]!;
    final updated = existing.copyWith(
      state: AccessAttemptState.confirmed,
      confirmedAt: confirmedAt,
      unlockUntil: unlockUntil,
    );
    records[sessionId] = updated;
    return updated;
  }

  @override
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  }) async =>
      records[sessionId]!;

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) async =>
      records[sessionId]!;
}

class _ErrorProgressRepo implements IProgressRepository {
  @override
  Future<List<XpRewardRecord>> getAllRewards() async =>
      throw StateError('Simulated SQLite progress read failure');

  @override
  Future<int> getOrCreateProgressEpochMs(int defaultEpochMs) async =>
      defaultEpochMs;

  @override
  Future<XpRewardRecord?> getRewardBySessionId(String sessionId) async => null;

  @override
  Future<int> getTotalXp() async =>
      throw StateError('Simulated SQLite progress read failure');

  @override
  Future<bool> recordRewardIfAbsent(XpRewardRecord record) async => false;
}

AppScope _buildInMemoryScope({
  required DateTime Function() clock,
  IProgressRepository? progressRepo,
  _InMemoryWorkoutHistoryRepo? historyRepo,
}) {
  const bridge = NativeBridge();
  final focusService = FocusService(bridge: bridge);
  final settingsRepo = InMemorySettingsRepository();
  final cameraChecker = MockCameraPermissionChecker(
    status: CameraPermissionStatus.granted,
  );
  final settingsService = SettingsService(
    repository: settingsRepo,
    focusService: focusService,
    nativeBridge: bridge,
    cameraPermissionChecker: cameraChecker,
    clock: clock,
  );
  final hRepo = historyRepo ?? _InMemoryWorkoutHistoryRepo();
  final aRepo = _InMemoryAccessAttemptRepo();
  final pRepo = progressRepo ?? InMemoryProgressRepository();
  final pService = ProgressService(
    repository: pRepo,
    historyRepository: hRepo,
    clock: clock,
  );
  final challengeService = ChallengeService();
  final sessionManager = WorkoutSessionManager(
    challengeService: challengeService,
    clock: clock,
  );
  final accessService = AccessService(bridge: bridge, clock: clock);
  final coordinator = CoreIntegrationCoordinator(
    nativeBridge: bridge,
    focusService: focusService,
    challengeService: challengeService,
    sessionManager: sessionManager,
    accessService: accessService,
    workoutHistoryRepository: hRepo,
    accessAttemptRepository: aRepo,
    progressService: pService,
    clock: clock,
  );

  return AppScope(
    database: LevelUpDatabase(),
    nativeBridge: bridge,
    focusService: focusService,
    settingsRepository: settingsRepo,
    cameraChecker: cameraChecker,
    settingsService: settingsService,
    workoutHistoryRepository: hRepo,
    accessAttemptRepository: aRepo,
    progressRepository: pRepo,
    progressService: pService,
    challengeService: challengeService,
    sessionManager: sessionManager,
    accessService: accessService,
    coordinator: coordinator,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late bool pendingChallenge;

  setUp(() {
    pendingChallenge = false;
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
          final wasPending = pendingChallenge;
          pendingChallenge = false;
          return wasPending;
        case ChannelConstants.methodGrantAccess:
          final mins = (call.arguments as Map)[ChannelConstants.argMinutes] as int;
          return DateTime.now()
              .add(Duration(minutes: mins))
              .millisecondsSinceEpoch;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(controlChannel, null);
  });

  group('Module 09B — Real XP, Levels & Streaks UI Integration Tests', () {
    testWidgets('1. New user renders Level 1, 0/100 XP, 0 day streak, updates live across 1st and 2nd workouts (Level 2), and shows XP history', (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      final fixedNow = DateTime(2026, 11, 25, 10, 0);
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });

      final scope = _buildInMemoryScope(clock: () => fixedNow);
      await scope.settingsService.initialize();
      await scope.focusService.refreshState();
      await scope.progressService.initialize();
      await scope.coordinator.initialize();

      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      // Open Progress tab -> verify Level 1, 0 / 100 XP, 0 day streak
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();

      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('0 / 100 XP · 0 total XP'), findsOneWidget);
      expect(find.text('0 day streak'), findsOneWidget);
      expect(find.text('Longest: 0 · Not yet today'), findsOneWidget);

      // Complete 1st verified 5-squat Free Workout via coordinator
      await scope.coordinator.launchFreeWorkout();
      for (var rep = 1; rep <= 5; rep++) {
        await scope.coordinator.handlePoseResult(
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
      await scope.coordinator.waitForCompletion();
      scope.coordinator.releaseTerminalSession();
      await tester.pumpAndSettle();

      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('50 / 100 XP · 50 total XP'), findsOneWidget);
      expect(find.text('1 day streak'), findsOneWidget);
      expect(find.text('Longest: 1 · Completed today'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('+50 XP'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('+50 XP'), findsOneWidget);

      // Complete 2nd verified 5-squat Unlock Challenge on SAME day -> 100 XP (Level 2), streak stays 1
      pendingChallenge = true;
      await scope.coordinator.launchUnlockChallenge(requirePendingRequest: true);
      for (var rep = 1; rep <= 5; rep++) {
        await scope.coordinator.handlePoseResult(
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
      await scope.coordinator.waitForCompletion();
      scope.coordinator.releaseTerminalSession();
      await tester.pumpAndSettle();

      expect(find.text('Level 2'), findsOneWidget);
      expect(find.text('0 / 200 XP · 100 total XP'), findsOneWidget);
      expect(find.text('1 day streak'), findsOneWidget);

      // Open Level detail screen -> verify remaining XP & XP history
      await tester.tap(find.byKey(const ValueKey('home_level')));
      await tester.pumpAndSettle();
      expect(find.text('200 XP to Level 3'), findsOneWidget);
      expect(find.text('+50 XP'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      scope.dispose();
    });

    testWidgets('2. Pre-epoch historical workouts do not fabricate XP, untrusted preview is ignored, and post-epoch failed XP recovers on refresh', (tester) async {
      final epochTime = DateTime(2026, 11, 25, 10, 0);
      final historyRepo = _InMemoryWorkoutHistoryRepo();
      final scope = _buildInMemoryScope(
        clock: () => epochTime,
        historyRepo: historyRepo,
      );
      await scope.progressService.initialize();

      // Pre-epoch workout -> must NOT earn fabricated XP
      await historyRepo.saveCompletedWorkout(
        WorkoutResult(
          sessionId: 'old-pre-epoch',
          requestId: 'r-old',
          challengeId: 'squats_free_5',
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          completedRepetitions: 5,
          duration: const Duration(seconds: 25),
          completedAt: epochTime.subtract(const Duration(days: 2)),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
          source: 'camera',
        ),
      );
      // Untrusted preview workout after epoch -> must NOT earn XP
      await historyRepo.saveCompletedWorkout(
        WorkoutResult(
          sessionId: 'untrusted-preview',
          requestId: 'r-prev',
          challengeId: 'squats_free_5',
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          completedRepetitions: 5,
          duration: const Duration(seconds: 25),
          completedAt: epochTime.add(const Duration(minutes: 2)),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
          source: 'preview',
        ),
      );
      // Post-epoch verified workout whose XP write failed -> SHOULD recover on refresh
      await historyRepo.saveCompletedWorkout(
        WorkoutResult(
          sessionId: 'post-epoch-recover',
          requestId: 'r-rec',
          challengeId: 'squats_free_5',
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          completedRepetitions: 5,
          duration: const Duration(seconds: 25),
          completedAt: epochTime.add(const Duration(minutes: 5)),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
          source: 'camera',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: scope.focusGateway,
            language: DashboardLanguage.en,
            logoAsset: null,
            loadInsights: () => scope.insightsAdapter.loadInsights(),
            progressStream: scope.progressService.stateStream,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only the 1 verified post-epoch workout earned 50 XP
      expect(find.text('Level 1'), findsOneWidget);
      expect(find.text('50 / 100 XP · 50 total XP'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      scope.dispose();
    });

    testWidgets('3. SQLite read failure shows honest error state instead of 0 XP, and disposal mid-refresh is safe', (tester) async {
      final scope = _buildInMemoryScope(
        clock: () => DateTime(2026, 11, 25, 10, 0),
        progressRepo: _ErrorProgressRepo(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: scope.focusGateway,
            language: DashboardLanguage.en,
            logoAsset: null,
            loadInsights: () => scope.insightsAdapter.loadInsights(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Progress could not be loaded.'), findsOneWidget);
      expect(find.text('0 / 100 XP · 0 total XP'), findsNothing);

      // Also test lifecycle resume refresh + disposal mid-flight
      final completer = Completer<DashboardInsights>();
      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: scope.focusGateway,
            language: DashboardLanguage.en,
            logoAsset: null,
            loadInsights: () => completer.future,
          ),
        ),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpWidget(const SizedBox()); // dispose before completer finishes
      completer.complete(const DashboardInsights(historyReady: true));
      await tester.pump();

      scope.dispose();
    });

    test('4. Progress persists in real SQLite across AppScope restart and surfaces in CoreInsightsAdapter', () async {
      final tempDir = await Directory.systemTemp.createTemp('levelup_09b_sql_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dbPath = p.join(tempDir.path, 'progress_ui.db');
      final now = DateTime(2026, 11, 25, 14, 0);

      Future<AppScope> bootSqlScope() async {
        final db = LevelUpDatabase(
          databaseFactory: databaseFactoryFfi,
          customPath: dbPath,
        );
        final scope = AppScope.production(
          database: db,
          cameraChecker: MockCameraPermissionChecker(
            status: CameraPermissionStatus.granted,
          ),
          clock: () => now,
        );
        await scope.initialize();
        return scope;
      }

      final scope1 = await bootSqlScope();
      await scope1.coordinator.launchFreeWorkout();
      for (var rep = 1; rep <= 5; rep++) {
        await scope1.coordinator.handlePoseResult(
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
      await scope1.coordinator.waitForCompletion();
      scope1.dispose();

      // Reopen fresh AppScope against same SQLite DB
      final scope2 = await bootSqlScope();
      final insights = await scope2.insightsAdapter.loadInsights();

      expect(insights.totalXp, 50);
      expect(insights.levelInfo?.level, 1);
      expect(insights.levelInfo?.xpIntoCurrentLevel, 50);
      expect(insights.streakInfo?.currentStreak, 1);
      expect(insights.streakInfo?.longestStreak, 1);
      expect(insights.streakInfo?.completedToday, isTrue);
      expect(insights.completedWorkoutCount, 1);
      expect(insights.events.single.xp, 50);

      scope2.dispose();
    });
  });
}
