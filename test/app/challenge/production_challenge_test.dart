import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:levelup_test/app/challenge/production_challenge_controller.dart';
import 'package:levelup_test/app/challenge/production_challenge_screen.dart';
import 'package:levelup_test/app/di/app_scope.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/application/workout_session_manager.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/application/settings_service.dart';
import 'package:levelup_test/features/settings/data/settings_repository.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/focus_experience/focus_screens.dart';
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/models/access_attempt_record.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryWorkoutHistoryRepo implements IWorkoutHistoryRepository {
  final List<WorkoutResult> saved = [];

  @override
  Future<int> countCompletedWorkouts() async => saved.length;

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async =>
      saved;

  @override
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType}) async =>
      saved.fold<int>(0, (sum, w) => sum + w.completedRepetitions);

  @override
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId) async =>
      saved.where((w) => w.sessionId == sessionId).firstOrNull;

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      saved;

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {
    saved.add(result);
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
      records.values.toList(growable: false);

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) async {
    final existing = records[sessionId]!;
    final updated = AccessAttemptRecord(
      sessionId: existing.sessionId,
      targetPackage: existing.targetPackage,
      durationSeconds: existing.durationSeconds,
      state: AccessAttemptState.confirmed,
      attemptedAt: existing.attemptedAt,
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
  }) async {
    final existing = records[sessionId]!;
    final updated = AccessAttemptRecord(
      sessionId: existing.sessionId,
      targetPackage: existing.targetPackage,
      durationSeconds: existing.durationSeconds,
      state: AccessAttemptState.definitivelyRejected,
      attemptedAt: existing.attemptedAt,
      failureReason: reason,
    );
    records[sessionId] = updated;
    return updated;
  }

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) async {
    final existing = records[sessionId]!;
    final updated = AccessAttemptRecord(
      sessionId: existing.sessionId,
      targetPackage: existing.targetPackage,
      durationSeconds: existing.durationSeconds,
      state: AccessAttemptState.uncertain,
      attemptedAt: existing.attemptedAt,
      failureReason: reason,
    );
    records[sessionId] = updated;
    return updated;
  }
}

/// Builds a synthetic ML Kit [Pose] with either standing (~180°) or deep squat (~90°) landmarks.
Pose _buildSquatPose({required bool down}) {
  // Knee at (0, 100), ankle at (0, 200)
  // Standing: hip at (0, 0) -> angle = 180° (> 155°)
  // Squatting: hip at (100, 100) -> angle = 90° (< 125°)
  final hip = down
      ? PoseLandmark(
          type: PoseLandmarkType.leftHip,
          x: 100,
          y: 100,
          z: 0,
          likelihood: 0.95,
        )
      : PoseLandmark(
          type: PoseLandmarkType.leftHip,
          x: 0,
          y: 0,
          z: 0,
          likelihood: 0.95,
        );
  final knee = PoseLandmark(
    type: PoseLandmarkType.leftKnee,
    x: 0,
    y: 100,
    z: 0,
    likelihood: 0.95,
  );
  final ankle = PoseLandmark(
    type: PoseLandmarkType.leftAnkle,
    x: 0,
    y: 200,
    z: 0,
    likelihood: 0.95,
  );

  return Pose(landmarks: {
    PoseLandmarkType.leftHip: hip,
    PoseLandmarkType.leftKnee: knee,
    PoseLandmarkType.leftAnkle: ankle,
  });
}

InputImage _dummyInputImage() => InputImage.fromBytes(
      bytes: Uint8List(16),
      metadata: InputImageMetadata(
        size: const Size(4, 4),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: 4,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late bool serviceEnabled;
  late bool gateEnabled;
  late bool pendingChallenge;
  late String targetPackage;
  late int consumeCount;
  late int grantCount;
  late List<int> grantedMinutesArgs;
  late List<String> methodCalls;
  late bool rejectNextGrant;

  late _InMemoryWorkoutHistoryRepo historyRepo;
  late _InMemoryAccessAttemptRepo accessRepo;
  late MockCameraPermissionChecker cameraChecker;
  late AppScope scope;

  setUp(() async {
    serviceEnabled = true;
    gateEnabled = true;
    pendingChallenge = true;
    targetPackage = ChannelConstants.targetYouTube;
    consumeCount = 0;
    grantCount = 0;
    grantedMinutesArgs = <int>[];
    methodCalls = <String>[];
    rejectNextGrant = false;

    messenger.setMockMethodCallHandler(controlChannel, (call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case ChannelConstants.methodGetState:
          return {
            ChannelConstants.keyTarget: targetPackage,
            ChannelConstants.keyEnabled: gateEnabled,
            ChannelConstants.keyUnlockUntil: 0,
            ChannelConstants.keyServiceEnabled: serviceEnabled,
          };
        case ChannelConstants.methodConsumeChallengeRequest:
          consumeCount++;
          final wasPending = pendingChallenge;
          pendingChallenge = false;
          return wasPending;
        case ChannelConstants.methodGrantAccess:
          if (rejectNextGrant) {
            throw PlatformException(code: 'DENIED', message: 'Native rejected');
          }
          grantCount++;
          final args = call.arguments as Map<dynamic, dynamic>;
          final mins = args[ChannelConstants.argMinutes] as int;
          grantedMinutesArgs.add(mins);
          return DateTime.now()
              .add(Duration(minutes: mins))
              .millisecondsSinceEpoch;
        case ChannelConstants.methodOpenAppSettings:
          return true;
        default:
          return null;
      }
    });

    const bridge = NativeBridge();
    final focusService = FocusService(bridge: bridge);
    final settingsRepo = InMemorySettingsRepository();
    cameraChecker = MockCameraPermissionChecker(
      status: CameraPermissionStatus.granted,
    );
    final settingsService = SettingsService(
      repository: settingsRepo,
      focusService: focusService,
      nativeBridge: bridge,
      cameraPermissionChecker: cameraChecker,
    );
    historyRepo = _InMemoryWorkoutHistoryRepo();
    accessRepo = _InMemoryAccessAttemptRepo();
    final challengeService = ChallengeService();
    final sessionManager = WorkoutSessionManager(
      challengeService: challengeService,
    );
    final accessService = AccessService(bridge: bridge);
    final coordinator = CoreIntegrationCoordinator(
      nativeBridge: bridge,
      focusService: focusService,
      challengeService: challengeService,
      sessionManager: sessionManager,
      accessService: accessService,
      workoutHistoryRepository: historyRepo,
      accessAttemptRepository: accessRepo,
    );

    scope = AppScope(
      database: LevelUpDatabase(),
      nativeBridge: bridge,
      focusService: focusService,
      settingsRepository: settingsRepo,
      cameraChecker: cameraChecker,
      settingsService: settingsService,
      workoutHistoryRepository: historyRepo,
      accessAttemptRepository: accessRepo,
      challengeService: challengeService,
      sessionManager: sessionManager,
      accessService: accessService,
      coordinator: coordinator,
    );
    await settingsService.initialize();
    await focusService.refreshState();
    await coordinator.initialize();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(controlChannel, null);
    scope.dispose();
  });

  Future<void> performVerifiedSquat(
    ProductionChallengeController controller, {
    required List<Pose> nextPoses,
    required void Function(List<Pose>) setPoses,
  }) async {
    // 2 consecutive down frames (< 125°)
    setPoses([_buildSquatPose(down: true)]);
    await controller.processInputImage(_dummyInputImage());
    await controller.processInputImage(_dummyInputImage());
    // 2 consecutive up frames (> 155°)
    setPoses([_buildSquatPose(down: false)]);
    await controller.processInputImage(_dummyInputImage());
    await controller.processInputImage(_dummyInputImage());
  }

  group('Phase I2B — Real Camera Challenge & Native Unlock Tests', () {
    testWidgets('1. Gate-triggered challenge launches once, consumes pending request once, and does not grant before 5 squats', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      pendingChallenge = true;
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      // Gate request consumed exactly once and ProductionChallengeScreen opened
      expect(consumeCount, 1);
      expect(find.byType(ProductionChallengeScreen), findsOneWidget);
      final screen = tester.widget<ProductionChallengeScreen>(
        find.byType(ProductionChallengeScreen),
      );
      expect(screen.isUnlockChallenge, isTrue);
      expect(screen.appName, 'YouTube');
      expect(grantCount, 0);

      // Resuming again while already open does NOT double-consume
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(consumeCount, 1);
    });

    testWidgets('2. Missing or stale pending request does not launch challenge', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      pendingChallenge = false;
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      expect(consumeCount, 1);
      expect(find.byType(ProductionChallengeScreen), findsNothing);
      expect(find.byType(LevelUpHomeScreen), findsOneWidget);
      expect(grantCount, 0);
    });

    testWidgets('3. Ineligible native state (Focus disabled) rejects launch safely', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      gateEnabled = false;
      pendingChallenge = true;
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      expect(find.byType(ProductionChallengeScreen), findsNothing);
      expect(grantCount, 0);
    });

    test('4. 5 verified ML Kit squats grant exactly one 300s (5 min) native unlock; extra frames do not double-grant', () async {
      List<Pose> currentPoses = [];
      final controller = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: true,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => currentPoses,
      );

      await controller.start();
      expect(controller.repetitions, 0);
      expect(grantCount, 0);

      // Perform 4 squats: no access granted yet
      for (var i = 0; i < 4; i++) {
        await performVerifiedSquat(
          controller,
          nextPoses: currentPoses,
          setPoses: (p) => currentPoses = p,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.repetitions, 4);
      expect(grantCount, 0);
      expect(controller.isUnlockConfirmed, isFalse);

      // 5th squat completes session and triggers authoritative grantAccess(5)
      await performVerifiedSquat(
        controller,
        nextPoses: currentPoses,
        setPoses: (p) => currentPoses = p,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.repetitions, 5);
      expect(grantCount, 1);
      expect(grantedMinutesArgs, [5]); // 5 minutes == 300 seconds
      expect(controller.isUnlockConfirmed, isTrue);
      expect(controller.grantedMinutes, 5);
      expect(historyRepo.saved.length, 1);
      expect(
        accessRepo.records.values.single.state,
        AccessAttemptState.confirmed,
      );

      // Duplicate completion protection: extra squats after 5/5 do NOT grant again
      await performVerifiedSquat(
        controller,
        nextPoses: currentPoses,
        setPoses: (p) => currentPoses = p,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(grantCount, 1);

      controller.dispose();
    });

    test('5. Free Workout completes 5/5 squats without ever calling grantAccess', () async {
      List<Pose> currentPoses = [];
      final controller = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: false,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => currentPoses,
      );

      await controller.start();

      for (var i = 0; i < 5; i++) {
        await performVerifiedSquat(
          controller,
          nextPoses: currentPoses,
          setPoses: (p) => currentPoses = p,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.repetitions, 5);
      expect(controller.isFreeWorkoutCompleted, isTrue);
      expect(controller.isUnlockConfirmed, isFalse);
      expect(grantCount, 0);
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
      expect(historyRepo.saved.length, 1);
      expect(accessRepo.records, isEmpty);

      controller.dispose();
    });

    test('6. Camera permission denied and permanently denied handle errors and openAppSettings on retry', () async {
      cameraChecker.status = CameraPermissionStatus.denied;
      final controller = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: false,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => const [],
      );

      await controller.start();

      expect(cameraChecker.requestCount, 1);
      expect(controller.error, contains('Allow camera access'));
      expect(controller.canRetry, isTrue);
      expect(controller.isCameraPermissionPermanentlyDenied, isFalse);

      // Grant permission and retry
      cameraChecker.grantPermission();
      await controller.retry();
      expect(controller.isCameraPermissionPermanentlyDenied, isFalse);

      // Now test permanently denied -> retry opens Android App Settings
      cameraChecker.status = CameraPermissionStatus.permanentlyDenied;
      final permController = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: false,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => const [],
      );
      // Release previous terminal/active session first
      await controller.cancel();
      controller.dispose();

      await permController.start();
      expect(permController.isCameraPermissionPermanentlyDenied, isTrue);
      expect(permController.error, contains('Open app settings'));

      await permController.retry();
      expect(methodCalls, contains(ChannelConstants.methodOpenAppSettings));

      permController.dispose();
    });

    test('7. Cancel and lifecycle interruption release resources and never grant access', () async {
      final controller = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: true,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => const [],
      );

      await controller.start();
      expect(
        scope.coordinator.currentState.sessionStatus,
        WorkoutSessionStatus.active,
      );

      // Simulate background interruption
      await controller.handleLifecycleChange(AppLifecycleState.paused);
      expect(controller.trackingReady, isFalse);

      // Resume
      await controller.handleLifecycleChange(AppLifecycleState.resumed);

      // Cancel
      await controller.cancel();
      expect(grantCount, 0);
      expect(
        scope.coordinator.currentState.sessionStatus,
        WorkoutSessionStatus.created, // released terminal session
      );

      controller.dispose();
    });

    testWidgets('8. FocusAccessGrantedScreen renders only after confirmed native grant, never on failed grant', (tester) async {
      List<Pose> currentPoses = [];
      rejectNextGrant = true;

      final controller = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: true,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => currentPoses,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionChallengeScreen(
            scope: scope,
            isUnlockChallenge: true,
            appName: 'YouTube',
            language: 'en',
            controllerOverride: controller,
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 5; i++) {
        await performVerifiedSquat(
          controller,
          nextPoses: currentPoses,
          setPoses: (p) => currentPoses = p,
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      // Failed native grant must NOT show FocusAccessGrantedScreen
      expect(find.byType(FocusAccessGrantedScreen), findsNothing);
      expect(
        scope.coordinator.currentState.accessGrantStatus,
        AccessGrantStatus.failed,
      );
      expect(controller.isUnlockConfirmed, isFalse);

      controller.dispose();
    });

    testWidgets('9. FocusAccessGrantedScreen renders on confirmed 5-min native grant', (tester) async {
      List<Pose> currentPoses = [];
      rejectNextGrant = false;

      final controller = ProductionChallengeController(
        coordinator: scope.coordinator,
        cameraPermissionChecker: cameraChecker,
        nativeBridge: scope.nativeBridge,
        isUnlockChallenge: true,
        language: 'en',
        availableCamerasOverride: () async => <CameraDescription>[],
        poseProcessorOverride: (_) async => currentPoses,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionChallengeScreen(
            scope: scope,
            isUnlockChallenge: true,
            appName: 'YouTube',
            language: 'en',
            controllerOverride: controller,
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 5; i++) {
        await performVerifiedSquat(
          controller,
          nextPoses: currentPoses,
          setPoses: (p) => currentPoses = p,
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.byType(FocusAccessGrantedScreen), findsOneWidget);
      expect(find.textContaining('5 min of access granted'), findsOneWidget);
      expect(grantCount, 1);

      controller.dispose();
    });
  });
}
