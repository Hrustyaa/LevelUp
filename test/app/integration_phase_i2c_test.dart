import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/adapters/core_insights_adapter.dart';
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

class _StubHistoryRepo implements IWorkoutHistoryRepository {
  List<WorkoutResult> workouts;
  Object? error;
  _StubHistoryRepo(this.workouts);

  @override
  Future<int> countCompletedWorkouts() async => workouts.length;

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async {
    if (error != null) throw error!;
    return workouts.take(limit).toList();
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
  ) async {
    if (error != null) throw error!;
    return workouts;
  }

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {
    workouts.add(result);
  }
}

class _StubAccessRepo implements IAccessAttemptRepository {
  List<AccessAttemptRecord> attempts;
  Object? error;
  _StubAccessRepo(this.attempts);

  @override
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId) async =>
      attempts.where((a) => a.sessionId == sessionId).firstOrNull;

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async {
    if (error != null) throw error!;
    return attempts.take(limit).toList();
  }

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  }) =>
      throw UnimplementedError();

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) =>
      throw UnimplementedError();
}

WorkoutResult _workout({
  required String sessionId,
  required DateTime completedAt,
  ChallengeType context = ChallengeType.unlockChallenge,
  String? targetPackage = ChannelConstants.targetYouTube,
  int reps = 5,
}) =>
    WorkoutResult(
      sessionId: sessionId,
      requestId: 'req-$sessionId',
      challengeId: context == ChallengeType.unlockChallenge
          ? 'squats_unlock_5'
          : 'squats_free_5',
      challengeContext: context,
      exerciseType: ExerciseType.squats,
      targetPackage: targetPackage,
      completedRepetitions: reps,
      duration: const Duration(seconds: 25),
      completedAt: completedAt,
      eligibleForAccess: context == ChallengeType.unlockChallenge,
      accessDurationSeconds: context == ChallengeType.unlockChallenge ? 300 : 0,
      earnedXp: 50,
    );

AccessAttemptRecord _attempt({
  required String sessionId,
  required AccessAttemptState state,
  required DateTime attemptedAt,
  DateTime? confirmedAt,
  DateTime? unlockUntil,
  String targetPackage = ChannelConstants.targetYouTube,
}) =>
    AccessAttemptRecord(
      sessionId: sessionId,
      targetPackage: targetPackage,
      durationSeconds: 300,
      state: state,
      attemptedAt: attemptedAt,
      confirmedAt: confirmedAt,
      unlockUntil: unlockUntil,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late bool serviceEnabled;
  late bool gateEnabled;
  late String targetPackage;
  late int unlockUntilMs;
  late List<String> methodCalls;

  setUp(() {
    serviceEnabled = true;
    gateEnabled = true;
    targetPackage = ChannelConstants.targetInstagram;
    unlockUntilMs = 0;
    methodCalls = [];

    messenger.setMockMethodCallHandler(controlChannel, (call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case ChannelConstants.methodGetState:
          return {
            ChannelConstants.keyTarget: targetPackage,
            ChannelConstants.keyEnabled: gateEnabled,
            ChannelConstants.keyUnlockUntil: unlockUntilMs,
            ChannelConstants.keyServiceEnabled: serviceEnabled,
          };
        case ChannelConstants.methodSetTarget:
          final args = call.arguments as Map<dynamic, dynamic>;
          targetPackage = args[ChannelConstants.argTarget] as String;
          unlockUntilMs = 0;
          return true;
        case ChannelConstants.methodSetEnabled:
          final args = call.arguments as Map<dynamic, dynamic>;
          gateEnabled = args[ChannelConstants.argEnabled] as bool;
          return true;
        case ChannelConstants.methodConsumeChallengeRequest:
          return false;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(controlChannel, null);
  });

  group('Phase I2C — CoreInsightsAdapter Data & Honesty Tests', () {
    test('1. Counts only confirmed unlocks, ignores prepared/uncertain/rejected, and deduplicates sessionIds', () async {
      final now = DateTime(2026, 11, 25, 14, 0);
      final history = _StubHistoryRepo([
        _workout(
          sessionId: 's1',
          completedAt: now.subtract(const Duration(minutes: 10)),
          targetPackage: ChannelConstants.targetInstagram,
        ),
        _workout(
          sessionId: 's1',
          completedAt: now.subtract(const Duration(minutes: 10)),
          targetPackage: ChannelConstants.targetInstagram,
        ), // duplicate
        _workout(sessionId: 's2', completedAt: now.subtract(const Duration(minutes: 5))),
        _workout(sessionId: 's3', completedAt: now.subtract(const Duration(minutes: 3))),
        _workout(sessionId: 's4', completedAt: now.subtract(const Duration(minutes: 1))),
      ]);
      final access = _StubAccessRepo([
        _attempt(
          sessionId: 's1',
          state: AccessAttemptState.confirmed,
          attemptedAt: now.subtract(const Duration(minutes: 10)),
          confirmedAt: now.subtract(const Duration(minutes: 10)),
          unlockUntil: now.subtract(const Duration(minutes: 5)),
          targetPackage: ChannelConstants.targetInstagram,
        ),
        _attempt(
          sessionId: 's1', // duplicate
          state: AccessAttemptState.confirmed,
          attemptedAt: now.subtract(const Duration(minutes: 10)),
          confirmedAt: now.subtract(const Duration(minutes: 10)),
          unlockUntil: now.subtract(const Duration(minutes: 5)),
          targetPackage: ChannelConstants.targetInstagram,
        ),
        _attempt(
          sessionId: 's2',
          state: AccessAttemptState.prepared,
          attemptedAt: now.subtract(const Duration(minutes: 5)),
        ),
        _attempt(
          sessionId: 's3',
          state: AccessAttemptState.uncertain,
          attemptedAt: now.subtract(const Duration(minutes: 3)),
        ),
        _attempt(
          sessionId: 's4',
          state: AccessAttemptState.definitivelyRejected,
          attemptedAt: now.subtract(const Duration(minutes: 1)),
        ),
      ]);

      final adapter = CoreInsightsAdapter(
        historyRepo: history,
        accessRepo: access,
        clock: () => now,
      );

      final insights = await adapter.loadInsights();

      expect(insights.historyReady, isTrue);
      expect(insights.todayUnlocks, 1);
      expect(insights.todayWorkouts, 4);
      expect(insights.events.length, 4);
      // Only s1 is temporaryAccess; s2/s3/s4 remain movementCompleted (never fake-unlocked)
      expect(
        insights.events.where((e) => e.kind == ActivityKind.temporaryAccess).length,
        1,
      );
      expect(insights.events.last.appName, 'Instagram');
      expect(insights.events.last.minutes, 5);
      // Unsupported metrics & XP remain null
      expect(insights.todayUsageMinutes, isNull);
      expect(insights.totalXp, isNull);
      expect(insights.week, isEmpty);
      expect(insights.usageByApp, isEmpty);
      for (final e in insights.events) {
        expect(e.xp, isNull);
      }
    });

    test('2. Distinguishes Free Workout vs Unlock Challenge and sorts descending', () async {
      final t1 = DateTime(2026, 11, 25, 9, 0);
      final t2 = DateTime(2026, 11, 25, 11, 0);
      final history = _StubHistoryRepo([
        _workout(
          sessionId: 'free-1',
          completedAt: t1,
          context: ChallengeType.freeWorkout,
          targetPackage: null,
        ),
        _workout(
          sessionId: 'unlock-1',
          completedAt: t2,
          context: ChallengeType.unlockChallenge,
          targetPackage: ChannelConstants.targetTikTok,
        ),
      ]);
      final access = _StubAccessRepo([
        _attempt(
          sessionId: 'unlock-1',
          state: AccessAttemptState.confirmed,
          attemptedAt: t2,
          confirmedAt: t2,
          unlockUntil: t2.add(const Duration(minutes: 5)),
          targetPackage: ChannelConstants.targetTikTok,
        ),
      ]);

      final adapter = CoreInsightsAdapter(
        historyRepo: history,
        accessRepo: access,
        clock: () => DateTime(2026, 11, 25, 12, 0),
      );

      final insights = await adapter.loadInsights();

      expect(insights.events.length, 2);
      expect(insights.events[0].id, 'unlock-1');
      expect(insights.events[0].kind, ActivityKind.temporaryAccess);
      expect(insights.events[0].appName, 'TikTok');
      expect(insights.events[0].minutes, 5);
      expect(insights.events[1].id, 'free-1');
      expect(insights.events[1].kind, ActivityKind.movementCompleted);
      expect(insights.events[1].appName, isNull);
      expect(insights.events[1].minutes, isNull);
    });

    test('3. Respects local-day boundaries at midnight', () async {
      final nowLocal = DateTime(2026, 11, 25, 0, 5);
      final yesterdayLate = DateTime(2026, 11, 24, 23, 59);
      final todayStart = DateTime(2026, 11, 25, 0, 0);

      final history = _StubHistoryRepo([
        _workout(sessionId: 'prev', completedAt: yesterdayLate),
        _workout(sessionId: 'curr', completedAt: todayStart),
      ]);
      final access = _StubAccessRepo([
        _attempt(
          sessionId: 'prev',
          state: AccessAttemptState.confirmed,
          attemptedAt: yesterdayLate,
          confirmedAt: yesterdayLate,
          unlockUntil: yesterdayLate.add(const Duration(minutes: 5)),
        ),
        _attempt(
          sessionId: 'curr',
          state: AccessAttemptState.confirmed,
          attemptedAt: todayStart,
          confirmedAt: todayStart,
          unlockUntil: todayStart.add(const Duration(minutes: 5)),
        ),
      ]);

      final adapter = CoreInsightsAdapter(
        historyRepo: history,
        accessRepo: access,
        clock: () => nowLocal,
      );

      final insights = await adapter.loadInsights();
      expect(insights.todayUnlocks, 1);
      expect(insights.todayWorkouts, 1);
      expect(insights.events.length, 2);
    });

    test('4. Empty SQLite history returns zero daily counts and honest null XP/usage', () async {
      final adapter = CoreInsightsAdapter(
        historyRepo: _StubHistoryRepo(const []),
        accessRepo: _StubAccessRepo(const []),
      );

      final insights = await adapter.loadInsights();

      expect(insights.historyReady, isTrue);
      expect(insights.todayUnlocks, 0);
      expect(insights.todayWorkouts, 0);
      expect(insights.events, isEmpty);
      expect(insights.todayUsageMinutes, isNull);
      expect(insights.totalXp, isNull);
    });

    test('5. Propagates repository errors so UI can display error state', () async {
      final history = _StubHistoryRepo(const [])
        ..error = StateError('SQLite read failed');
      final adapter = CoreInsightsAdapter(
        historyRepo: history,
        accessRepo: _StubAccessRepo(const []),
      );

      expect(() => adapter.loadInsights(), throwsStateError);
    });
  });

  group('Phase I2C — Dashboard, Settings Persistence & Lifecycle Tests', () {
    testWidgets('6. Dashboard renders Core state, handles DB error honestly, and disposes safely mid-refresh', (tester) async {
      final completer = Completer<DashboardInsights>();
      final bridge = const NativeBridge();
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
      );
      await settingsService.initialize();
      await focusService.refreshState();

      final historyRepo = _StubHistoryRepo(const [])
        ..error = StateError('DB error');
      final insightsAdapter = CoreInsightsAdapter(
        historyRepo: historyRepo,
        accessRepo: _StubAccessRepo(const []),
      );

      final scope = AppScope(
        database: LevelUpDatabase(),
        nativeBridge: bridge,
        focusService: focusService,
        settingsRepository: settingsRepo,
        cameraChecker: cameraChecker,
        settingsService: settingsService,
        workoutHistoryRepository: historyRepo,
        accessAttemptRepository: _StubAccessRepo(const []),
        challengeService: ChallengeService(),
        sessionManager: WorkoutSessionManager(challengeService: ChallengeService()),
        accessService: AccessService(bridge: bridge),
        coordinator: CoreIntegrationCoordinator(
          nativeBridge: bridge,
          focusService: focusService,
          challengeService: ChallengeService(),
          sessionManager: WorkoutSessionManager(challengeService: ChallengeService()),
          accessService: AccessService(bridge: bridge),
          workoutHistoryRepository: historyRepo,
          accessAttemptRepository: _StubAccessRepo(const []),
        ),
        insightsAdapter: insightsAdapter,
      );

      // Render Home with failing insights -> error note appears
      await tester.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: scope.focusGateway,
            language: DashboardLanguage.en,
            logoAsset: null,
            loadInsights: () => scope.insightsAdapter.loadInsights(),
            catalog: const [
              DashboardApp(ChannelConstants.targetInstagram, 'Instagram'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Focus active'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Activity data could not be loaded.'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Activity data could not be loaded.'), findsOneWidget);

      // Now trigger an in-flight async refresh and dispose widget before it resolves
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
      await tester.pump();
      await tester.pumpWidget(const SizedBox()); // dispose while pending
      completer.complete(const DashboardInsights(historyReady: true));
      await tester.pump();

      scope.dispose();
    });

    testWidgets('7. Settings persist to real SQLite across restart without altering native target or active unlockUntil', (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      final tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('levelup_i2c_'),
      );
      addTearDown(() => tester.runAsync(() => tempDir!.delete(recursive: true)));
      final dbPath = p.join(tempDir!.path, 'levelup_i2c.db');

      final futureUnlock = DateTime.now().add(const Duration(minutes: 4));
      unlockUntilMs = futureUnlock.millisecondsSinceEpoch;
      targetPackage = ChannelConstants.targetInstagram;

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
        );
        await scope.initialize();
        return scope;
      }

      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetInstagram],
      });

      final scope1 = (await tester.runAsync(bootScope))!;
      methodCalls.clear();

      await tester.pumpWidget(LevelUpIntroDemo(scope: scope1));
      await tester.pumpAndSettle();

      // Navigate to Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Sound & haptic feedback'), findsOneWidget);
      expect(find.text('Diagnostic logging'), findsOneWidget);

      // Toggle Sound & haptic feedback OFF
      await tester.tap(find.text('Sound & haptic feedback'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      // Verify native target & unlockUntil were NOT altered
      expect(methodCalls, isNot(contains(ChannelConstants.methodSetTarget)));
      expect(targetPackage, ChannelConstants.targetInstagram);
      expect(unlockUntilMs, futureUnlock.millisecondsSinceEpoch);
      expect(
        scope1.settingsService.currentState.settings.soundFeedbackEnabled,
        isFalse,
      );

      // Unmount and dispose first scope (simulating app restart)
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async => scope1.dispose());

      // Boot fresh scope against same SQLite DB
      final scope2 = (await tester.runAsync(bootScope))!;
      expect(
        scope2.settingsService.currentState.settings.soundFeedbackEnabled,
        isFalse,
      );
      expect(
        scope2.settingsService.currentState.settings.diagnosticLoggingEnabled,
        isTrue,
      );
      expect(
        scope2.focusService.currentState?.selectedTarget,
        ChannelConstants.targetInstagram,
      );
      expect(scope2.focusService.currentState?.isAccessActive, isTrue);

      await tester.runAsync(() async => scope2.dispose());
    });
  });
}
