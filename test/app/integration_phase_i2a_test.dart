import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/models/access_attempt_record.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';
import 'package:levelup_test/services/access_service.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

class _InMemoryWorkoutHistoryRepo implements IWorkoutHistoryRepository {
  @override
  Future<int> countCompletedWorkouts() async => 0;

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async =>
      const [];

  @override
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType}) async =>
      0;

  @override
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId) async => null;

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async =>
      const [];

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {}
}

class _InMemoryAccessAttemptRepo implements IAccessAttemptRepository {
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
      null;

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async =>
      const [];

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late bool serviceEnabled;
  late bool gateEnabled;
  late String targetPackage;
  late List<String> methodCalls;
  late AppScope scope;

  setUp(() async {
    serviceEnabled = false;
    gateEnabled = false;
    targetPackage = ChannelConstants.targetYouTube;
    methodCalls = <String>[];

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
        case ChannelConstants.methodSetTarget:
          final args = call.arguments as Map<dynamic, dynamic>;
          targetPackage = args[ChannelConstants.argTarget] as String;
          return true;
        case ChannelConstants.methodSetEnabled:
          final args = call.arguments as Map<dynamic, dynamic>;
          gateEnabled = args[ChannelConstants.argEnabled] as bool;
          return true;
        case ChannelConstants.methodOpenAccessibilitySettings:
        case ChannelConstants.methodOpenAppSettings:
          return true;
        default:
          return null;
      }
    });

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
    );
    final historyRepo = _InMemoryWorkoutHistoryRepo();
    final accessRepo = _InMemoryAccessAttemptRepo();
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

  group('Phase I2A UI/Core Integration Tests', () {
    testWidgets('1. Onboarding completes without enabling native Focus or calling grantAccess', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      methodCalls.clear();
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      expect(find.byType(LevelUpWelcomeScreen), findsOneWidget);
      await tap(find.byKey(const Key('welcome_get_started')));

      // Step 1: Supported catalog shows YouTube, Instagram, TikTok
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('TikTok'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TikTok'), findsOneWidget);

      await tap(find.text('Instagram'));
      await tap(find.byKey(const ValueKey('continue')));

      // Step 2: Focus setup
      await tap(find.byKey(const ValueKey('focus_continue')));

      // Step 3: Permissions (Accessibility denied, Usage/Notifications unavailable)
      await tap(find.byKey(const ValueKey('permissions_skip')));

      expect(find.byType(LevelUpHomeScreen), findsOneWidget);
      // Onboarding must NOT silently enable native blocker or grant access
      expect(gateEnabled, isFalse);
      expect(methodCalls, isNot(contains(ChannelConstants.methodSetEnabled)));
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });

    testWidgets('2. Enabling Focus with missing Accessibility shows dialog and does not enable native gate', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      serviceEnabled = false;
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      final enableButton = find.byKey(const ValueKey('home_enable'));
      await tester.ensureVisible(enableButton);
      await tester.tap(enableButton);
      await tester.pumpAndSettle();

      expect(find.text('Accessibility Required'), findsOneWidget);
      expect(gateEnabled, isFalse);
      expect(methodCalls, isNot(contains(ChannelConstants.methodSetEnabled)));
    });

    testWidgets('3. Explicit enable with Accessibility granted activates single target via FocusService', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [
          ChannelConstants.targetYouTube,
          ChannelConstants.targetInstagram,
        ],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      serviceEnabled = true;
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      final enableButton = find.byKey(const ValueKey('home_enable'));
      await tester.ensureVisible(enableButton);
      await tester.tap(enableButton);
      await tester.pumpAndSettle();

      // Multi-app draft prompts user to select exactly one native target
      expect(find.text('Enable Focus for one app'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('focus_target_${ChannelConstants.targetInstagram}')),
      );
      await tester.pumpAndSettle();

      expect(targetPackage, ChannelConstants.targetInstagram);
      expect(gateEnabled, isTrue);
      expect(methodCalls, contains(ChannelConstants.methodSetTarget));
      expect(methodCalls, contains(ChannelConstants.methodSetEnabled));
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });

    testWidgets('4. App resume refreshes Scope permissions and native Focus state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      serviceEnabled = false;
      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      expect(scope.settingsService.currentState.isAccessibilityGranted, isFalse);

      // Simulate user enabling Accessibility in Android Settings and returning
      serviceEnabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(scope.settingsService.currentState.isAccessibilityGranted, isTrue);
      expect(scope.focusService.currentState?.isAccessibilityGranted, isTrue);
    });

    testWidgets('5. Challenge tab Movement action launches Free Workout without ever calling grantAccess', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
        'levelup.focus.selected_apps': [ChannelConstants.targetYouTube],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      await tester.pumpWidget(LevelUpIntroDemo(scope: scope));
      await tester.pumpAndSettle();

      // Navigate to Challenge tab
      await tester.tap(find.text('Challenge'));
      await tester.pumpAndSettle();

      final openChallengeBtn = find.text('Open movement challenge');
      await tester.ensureVisible(openChallengeBtn);
      await tester.tap(openChallengeBtn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.byType(ProductionChallengeScreen), findsOneWidget);
      final screen = tester.widget<ProductionChallengeScreen>(
        find.byType(ProductionChallengeScreen),
      );
      expect(screen.isUnlockChallenge, isFalse);
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
      expect(methodCalls, isNot(contains('setGateLanguage')));
    });

    testWidgets('6. Surfaces AppScope initializationError instead of faking a ready state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'en',
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      final failingScope = AppScope.production(
        database: _FailingDatabase(),
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(),
      );

      await expectLater(() => failingScope.initialize(), throwsA(isA<StateError>()));
      expect(failingScope.initializationError, isNotNull);

      await tester.pumpWidget(LevelUpIntroDemo(scope: failingScope));
      await tester.pumpAndSettle();

      expect(find.text('Core initialization failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(LevelUpHomeScreen), findsNothing);

      failingScope.dispose();
    });
  });
}

class _FailingDatabase extends LevelUpDatabase {
  @override
  Future<Database> get database =>
      Future.error(StateError('Database open failed'));
}
