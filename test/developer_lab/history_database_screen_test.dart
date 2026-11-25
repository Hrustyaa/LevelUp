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
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:levelup_test/models/workout_result.dart';
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
    tempDir = await Directory.systemTemp.createTemp('history_screen_test_');
    dbPath = p.join(tempDir.path, 'history_test.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
    await database.database;
  });

  tearDown(() async {
    await database.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget createTestWidget(DevLabController controller, {String? highlightSessionId}) {
    return DevLabScope(
      notifier: controller,
      child: MaterialApp(
        theme: DevLabTheme.theme,
        home: HistoryDatabaseScreen(highlightSessionId: highlightSessionId),
      ),
    );
  }

  Future<void> pumpUntilLoaded(WidgetTester tester) async {
    for (int i = 0; i < 30; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (!tester.any(find.byType(CircularProgressIndicator))) {
        break;
      }
    }
  }

  group('Screen 5 — HistoryDatabaseScreen Tests', () {
    testWidgets('1. Displays empty state when SQLite tables have no records', (tester) async {
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.runAsync(() async {
        await database.database;
      });

      await tester.pumpWidget(createTestWidget(controller));
      await pumpUntilLoaded(tester);

      expect(find.text('No completed workouts found in SQLite table.'), findsOneWidget);
      expect(find.text('Target Database: Isolated QA Simulation (levelup_simulation.db)'), findsOneWidget);

      // Switch to Access Attempts tab
      await tester.tap(find.textContaining('Access Attempts'));
      await tester.pumpAndSettle();

      expect(find.text('No access attempt records found in SQLite table.'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('2. Loads and displays workouts from SQLite repository', (tester) async {
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);

      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(WorkoutResult(
          sessionId: 'session_hist_1',
          requestId: 'req_1',
          challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
          challengeContext: ChallengeType.unlockChallenge,
          exerciseType: ExerciseType.squats,
          targetPackage: ChannelConstants.targetYouTube,
          completedRepetitions: 5,
          duration: const Duration(seconds: 45),
          completedAt: DateTime.now(),
          eligibleForAccess: true,
          accessDurationSeconds: 300,
        ));

        await workoutRepo.saveCompletedWorkout(WorkoutResult(
          sessionId: 'session_hist_2',
          requestId: 'req_2',
          challengeId: ChallengeCatalog.squatFreeWorkout.challengeId,
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          targetPackage: null,
          completedRepetitions: 5,
          duration: const Duration(seconds: 50),
          completedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
        ));
      });

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(createTestWidget(controller));
      await pumpUntilLoaded(tester);

      expect(find.text('session_hist_1'), findsOneWidget);
      expect(find.text('session_hist_2'), findsOneWidget);
      expect(find.text('UNLOCK'), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('5 reps'), findsNWidgets(2));
      expect(find.text('Workouts (2)'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('3. Filters workouts by challenge context', (tester) async {
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);

      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(WorkoutResult(
          sessionId: 'session_unlock_only',
          requestId: 'req_u',
          challengeId: ChallengeCatalog.squatUnlockChallenge.challengeId,
          challengeContext: ChallengeType.unlockChallenge,
          exerciseType: ExerciseType.squats,
          targetPackage: ChannelConstants.targetInstagram,
          completedRepetitions: 5,
          duration: const Duration(seconds: 40),
          completedAt: DateTime.now(),
          eligibleForAccess: true,
          accessDurationSeconds: 300,
        ));

        await workoutRepo.saveCompletedWorkout(WorkoutResult(
          sessionId: 'session_free_only',
          requestId: 'req_f',
          challengeId: ChallengeCatalog.squatFreeWorkout.challengeId,
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          completedRepetitions: 5,
          duration: const Duration(seconds: 35),
          completedAt: DateTime.now(),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
        ));
      });

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(createTestWidget(controller));
      await pumpUntilLoaded(tester);

      // Tap 'Unlock Challenges' filter chip
      await tester.tap(find.text('Unlock Challenges'));
      await tester.pumpAndSettle();

      expect(find.text('session_unlock_only'), findsOneWidget);
      expect(find.text('session_free_only'), findsNothing);

      // Tap 'Free Workouts' filter chip
      await tester.tap(find.text('Free Workouts'));
      await tester.pumpAndSettle();

      expect(find.text('session_unlock_only'), findsNothing);
      expect(find.text('session_free_only'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('4. Loads and filters access attempts by state', (tester) async {
      final attemptRepo = AccessAttemptRepository(databaseManager: database);

      await tester.runAsync(() async {
        await attemptRepo.createAttemptIfAbsent(
          sessionId: 'session_attempt_conf',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 300,
          attemptedAt: DateTime.now(),
        );
        await attemptRepo.markConfirmed(
          sessionId: 'session_attempt_conf',
          confirmedAt: DateTime.now(),
          unlockUntil: DateTime.now().add(const Duration(minutes: 5)),
        );

        await attemptRepo.createAttemptIfAbsent(
          sessionId: 'session_attempt_unc',
          targetPackage: ChannelConstants.targetTikTok,
          durationSeconds: 300,
          attemptedAt: DateTime.now(),
        );
        await attemptRepo.markUncertain(
          sessionId: 'session_attempt_unc',
          reason: 'IPC timeout',
        );
      });

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(createTestWidget(controller));
      await pumpUntilLoaded(tester);

      // Switch to Access Attempts tab
      await tester.tap(find.textContaining('Access Attempts'));
      await tester.pumpAndSettle();

      expect(find.text('session_attempt_conf'), findsOneWidget);
      expect(find.text('session_attempt_unc'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsOneWidget);
      expect(find.text('UNCERTAIN'), findsOneWidget);

      // Filter by 'Confirmed'
      await tester.tap(find.text('Confirmed'));
      await tester.pumpAndSettle();

      expect(find.text('session_attempt_conf'), findsOneWidget);
      expect(find.text('session_attempt_unc'), findsNothing);

      controller.dispose();
    });

    testWidgets('5. App resume triggers reload of SQLite tables', (tester) async {
      final workoutRepo = WorkoutHistoryRepository(databaseManager: database);

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(createTestWidget(controller));
      await pumpUntilLoaded(tester);

      expect(find.text('Workouts (0)'), findsOneWidget);

      // Background insertion
      await tester.runAsync(() async {
        await workoutRepo.saveCompletedWorkout(WorkoutResult(
          sessionId: 'session_resumed',
          requestId: 'req_r',
          challengeId: ChallengeCatalog.squatFreeWorkout.challengeId,
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          completedRepetitions: 5,
          duration: const Duration(seconds: 40),
          completedAt: DateTime.now(),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
        ));
      });

      // Trigger app resumed lifecycle event
      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
      await pumpUntilLoaded(tester);

      expect(find.text('Workouts (1)'), findsOneWidget);
      expect(find.text('session_resumed'), findsOneWidget);

      controller.dispose();
    });
  });
}
