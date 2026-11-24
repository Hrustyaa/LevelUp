import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/data/challenge_catalog.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/screens/history_database_screen.dart';
import 'package:levelup_test/features/developer_lab/screens/workout_result_screen.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:levelup_test/models/workout_result.dart';
import 'package:levelup_test/models/workout_session.dart';
import 'package:levelup_test/models/workout_session_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String dbPath;
  late LevelUpDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('workout_result_test_');
    dbPath = p.join(tempDir.path, 'workout_result.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
    await database.database;
  });

  tearDown(() async {
    database.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget createTestWidget(DevLabController controller, {required Widget child}) {
    return DevLabScope(
      notifier: controller,
      child: MaterialApp(
        theme: DevLabTheme.theme,
        home: child,
      ),
    );
  }

  Future<void> pumpUntilSettled(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    for (int i = 0; i < 20; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  group('Screen 4 — WorkoutResultScreen Tests', () {
    testWidgets('1. Displays completed Free Workout with N/A access grant', (tester) async {
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);
      final freeWorkout = WorkoutResult(
        sessionId: 'session_free_1',
        requestId: 'req_free_1',
        challengeId: ChallengeCatalog.squatFreeWorkout.challengeId,
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        targetPackage: null,
        completedRepetitions: 5,
        duration: const Duration(seconds: 42),
        completedAt: DateTime.now(),
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );
      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(freeWorkout);
      });

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(
        createTestWidget(
          controller,
          child: WorkoutResultScreen(
            sessionId: 'session_free_1',
            initialResult: freeWorkout,
          ),
        ),
      );
      await pumpUntilSettled(tester);

      expect(find.text('FREE WORKOUT'), findsAtLeastNWidgets(1));
      expect(find.text('COMPLETED'), findsOneWidget);
      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text('00:42'), findsOneWidget);
      expect(find.text('Persisted in DB'), findsOneWidget);
      expect(find.textContaining('Free Workout mode strictly enforces'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('2. Displays completed Unlock Challenge with confirmed active access', (tester) async {
      final activeExpiry = DateTime.now().add(const Duration(minutes: 5));
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);
      final attemptRepo = AccessAttemptRepository(databaseManager: database);

      final unlockResult = WorkoutResult(
        sessionId: 'session_unlock_active',
        requestId: 'req_unlock_1',
        challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetYouTube,
        completedRepetitions: 5,
        duration: const Duration(seconds: 55),
        completedAt: DateTime.now(),
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );
      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(unlockResult);

        await attemptRepo.createAttemptIfAbsent(
          sessionId: 'session_unlock_active',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 300,
          attemptedAt: DateTime.now(),
        );
        await attemptRepo.markConfirmed(
          sessionId: 'session_unlock_active',
          confirmedAt: DateTime.now(),
          unlockUntil: activeExpiry,
        );
      });

      final bridge = SimulationBridge(
        initialStatus: NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: true,
          permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(unlockUntil: activeExpiry),
        ),
      );

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await tester.pumpWidget(
        createTestWidget(
          controller,
          child: WorkoutResultScreen(
            sessionId: 'session_unlock_active',
            initialResult: unlockResult,
          ),
        ),
      );
      await pumpUntilSettled(tester);

      expect(find.text('UNLOCK CHALLENGE'), findsAtLeastNWidgets(1));
      expect(find.textContaining('ACTIVE'), findsOneWidget);
      expect(find.text(ChannelConstants.targetYouTube), findsOneWidget);
      expect(find.text('UNLOCKED'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('3. Historically confirmed but expired access displays EXPIRED, not active', (tester) async {
      final pastExpiry = DateTime.now().subtract(const Duration(minutes: 10));
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);
      final attemptRepo = AccessAttemptRepository(databaseManager: database);

      final expiredResult = WorkoutResult(
        sessionId: 'session_expired_1',
        requestId: 'req_expired_1',
        challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetPackage: ChannelConstants.targetInstagram,
        completedRepetitions: 5,
        duration: const Duration(seconds: 60),
        completedAt: pastExpiry.subtract(const Duration(minutes: 5)),
        eligibleForAccess: true,
        accessDurationSeconds: 300,
      );
      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(expiredResult);

        await attemptRepo.createAttemptIfAbsent(
          sessionId: 'session_expired_1',
          targetPackage: ChannelConstants.targetInstagram,
          durationSeconds: 300,
          attemptedAt: pastExpiry.subtract(const Duration(minutes: 5)),
        );
        await attemptRepo.markConfirmed(
          sessionId: 'session_expired_1',
          confirmedAt: pastExpiry.subtract(const Duration(minutes: 5)),
          unlockUntil: pastExpiry,
        );
      });

      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetInstagram,
          isGateEnabled: true,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(), // Expired
        ),
      );

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await tester.pumpWidget(
        createTestWidget(
          controller,
          child: WorkoutResultScreen(
            sessionId: 'session_expired_1',
            initialResult: expiredResult,
          ),
        ),
      );
      await pumpUntilSettled(tester);

      // Confirms critical invariant: Historically confirmed grant is NOT active
      expect(find.textContaining('EXPIRED'), findsAtLeastNWidgets(1));
      expect(find.text('RESTRICTED'), findsOneWidget);
      expect(
        find.textContaining('A historically confirmed grant is NOT currently active'),
        findsOneWidget,
      );

      controller.dispose();
    });

    testWidgets('4. Displays failed workout session and error diagnostics', (tester) async {
      final failedSession = WorkoutSession(
        sessionId: 'session_failed_1',
        requestId: 'req_failed_1',
        challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
        challengeContext: ChallengeType.unlockChallenge,
        exerciseType: ExerciseType.squats,
        targetRepetitions: 5,
        verifiedRepetitions: 2,
        status: WorkoutSessionStatus.failed,
        failureReason: 'Camera pipeline stalled during active exercise.',
      );

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(
        createTestWidget(
          controller,
          child: WorkoutResultScreen(
            sessionId: 'session_failed_1',
            initialSession: failedSession,
          ),
        ),
      );
      await pumpUntilSettled(tester);

      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('Camera pipeline stalled during active exercise.'), findsOneWidget);
      expect(find.text('Not Persisted'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('5. Navigates to HistoryDatabaseScreen via button', (tester) async {
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);
      final workout = WorkoutResult(
        sessionId: 'session_nav_1',
        requestId: 'req_nav_1',
        challengeId: ChallengeCatalog.squatFreeWorkout.challengeId,
        challengeContext: ChallengeType.freeWorkout,
        exerciseType: ExerciseType.squats,
        completedRepetitions: 5,
        duration: const Duration(seconds: 30),
        completedAt: DateTime.now(),
        eligibleForAccess: false,
        accessDurationSeconds: 0,
      );
      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(workout);
      });

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(
        createTestWidget(
          controller,
          child: WorkoutResultScreen(
            sessionId: 'session_nav_1',
            initialResult: workout,
          ),
        ),
      );
      await pumpUntilSettled(tester);

      final historyBtn = find.text('View in History & Database');
      expect(historyBtn, findsOneWidget);

      await tester.tap(historyBtn);
      // Pump frame for route transition
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HistoryDatabaseScreen), findsOneWidget);

      controller.dispose();
    });
  });
}
