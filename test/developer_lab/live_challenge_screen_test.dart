import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/screens/live_challenge_screen.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:levelup_test/models/access_grant_status.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:levelup_test/models/workout_session_status.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late String dbPath;
  late LevelUpDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('live_challenge_test_');
    dbPath = p.join(tempDir.path, 'live_challenge.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
  });

  tearDown(() async {
    database.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget createTestWidget(DevLabController controller, {bool isUnlockFromNative = false}) {
    return DevLabScope(
      notifier: controller,
      child: MaterialApp(
        theme: DevLabTheme.theme,
        home: LiveChallengeScreen(isUnlockFromNative: isUnlockFromNative),
      ),
    );
  }

  testWidgets('LiveChallengeScreen renders HUD, metrics, and executes Free Workout to completion', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final bridge = SimulationBridge();
    final controller = DevLabController(
      initialMode: DevExecutionMode.simulation,
      customBridge: bridge,
      customDatabase: database,
    );

    await tester.runAsync(() async {
      await controller.refreshAll();
    });

    await tester.pumpWidget(createTestWidget(controller));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Verify Title & Key Cards
    expect(find.text('LIVE CHALLENGE'), findsOneWidget);
    expect(find.text('Pose Engine Biometrics'), findsOneWidget);
    expect(find.text('Session Repetition Progress'), findsOneWidget);
    expect(find.text('0 / 5 Verified Repetitions'), findsOneWidget);

    // Verify Launch Workout Challenge Card with Free Workout & Unlock Challenge buttons
    expect(find.text('Start Free Workout (5 Reps)'), findsOneWidget);
    expect(find.text('Start Unlock Challenge (5 Reps)'), findsOneWidget);

    // Start Free Workout
    await tester.runAsync(() async {
      await tester.tap(find.text('Start Free Workout (5 Reps)'));
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      controller.coordinator.currentState.sessionStatus,
      equals(WorkoutSessionStatus.active),
    );
    expect(
      controller.coordinator.currentState.challengeContext,
      equals(ChallengeType.freeWorkout),
    );

    // Verify simulation controls are present and tap "Finish 5 Reps"
    final finishFinder = find.text('Finish 5 Reps');
    expect(finishFinder, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(finishFinder);
      await controller.coordinator.waitForCompletion();
      await Future.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    // Verify Workout is completed
    expect(
      controller.coordinator.currentState.sessionStatus,
      equals(WorkoutSessionStatus.completed),
    );
    expect(
      controller.coordinator.currentState.verifiedRepetitions,
      equals(5),
    );

    // Verify Victory Card indicates SQLite persistence and NO native access grant
    expect(find.text('Workout Completed!'), findsOneWidget);
    expect(
      find.text('Free Workout persisted in SQLite database. No access grant executed (as intended).'),
      findsOneWidget,
    );
    expect(bridge.status.accessStatus.unlockUntil, isNull);

    controller.dispose();
  });

  testWidgets('LiveChallengeScreen executes authentic Unlock Challenge and grants 5-minute access', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final bridge = SimulationBridge(
      challengeRequested: true,
      initialStatus: const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      ),
    );

    final controller = DevLabController(
      initialMode: DevExecutionMode.simulation,
      customBridge: bridge,
      customDatabase: database,
    );

    await tester.runAsync(() async {
      await controller.refreshAll();
    });

    await tester.pumpWidget(createTestWidget(controller));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Start Unlock Challenge
    await tester.runAsync(() async {
      await tester.tap(find.text('Start Unlock Challenge (5 Reps)'));
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      controller.coordinator.currentState.sessionStatus,
      equals(WorkoutSessionStatus.active),
    );
    expect(
      controller.coordinator.currentState.challengeContext,
      equals(ChallengeType.unlockChallenge),
    );

    // Complete 5 verified reps
    await tester.runAsync(() async {
      await tester.tap(find.text('Finish 5 Reps'));
      await controller.coordinator.waitForCompletion();
      await Future.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    // Verify terminal success state
    expect(
      controller.coordinator.currentState.sessionStatus,
      equals(WorkoutSessionStatus.completed),
    );
    expect(
      controller.coordinator.currentState.accessGrantStatus,
      equals(AccessGrantStatus.granted),
    );
    expect(bridge.status.accessStatus.unlockUntil, isNotNull);

    expect(find.text('Workout Completed!'), findsOneWidget);
    expect(
      find.text('Native Access Granted: 5 minutes granted for target app.'),
      findsOneWidget,
    );

    controller.dispose();
  });
}
