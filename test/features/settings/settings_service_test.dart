import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/settings_exceptions.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/application/settings_service.dart';
import 'package:levelup_test/features/settings/data/settings_repository.dart';
import 'package:levelup_test/features/settings/models/app_settings.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/features/settings/models/settings_state.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Module 08 — Settings & Permissions Engine Tests', () {
    late Directory tempDir;
    late String dbPath;
    late LevelUpDatabase database;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('settings_test_');
      dbPath = p.join(tempDir.path, 'settings_test.db');
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

    // 1. Default settings initialization
    test('1. Default settings initialization provides deterministic baseline', () async {
      final repo = InMemorySettingsRepository();
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final cameraChecker = MockCameraPermissionChecker(status: CameraPermissionStatus.granted);

      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: cameraChecker,
      );

      final state = await service.initialize();

      expect(state.settings.defaultTargetPackage, equals(ChannelConstants.targetYouTube));
      expect(state.settings.defaultUnlockDurationSeconds, equals(300));
      expect(state.settings.emergencyPauseAllowed, isTrue);
      expect(state.settings.soundFeedbackEnabled, isTrue);
      expect(state.settings.diagnosticLoggingEnabled, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);

      service.dispose();
      focusService.dispose();
    });

    // 2. Loading persisted preferences
    test('2. Loading persisted preferences restores previously saved settings from SQLite', () async {
      final repo = SqliteSettingsRepository(databaseManager: database);
      const customSettings = AppSettings(
        defaultTargetPackage: ChannelConstants.targetInstagram,
        defaultUnlockDurationSeconds: 300,
        emergencyPauseAllowed: true,
        soundFeedbackEnabled: false,
        diagnosticLoggingEnabled: false,
      );
      await repo.saveSettings(customSettings);

      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      final state = await service.initialize();
      expect(state.settings, equals(customSettings));
      expect(state.settings.defaultTargetPackage, equals(ChannelConstants.targetInstagram));
      expect(state.settings.soundFeedbackEnabled, isFalse);

      service.dispose();
      focusService.dispose();
    });

    // 3. Saving valid preferences
    test('3. Saving valid preferences updates repository and state', () async {
      final repo = InMemorySettingsRepository();
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();

      const newSettings = AppSettings(
        defaultTargetPackage: ChannelConstants.targetYouTube,
        defaultUnlockDurationSeconds: 300,
        emergencyPauseAllowed: false,
        soundFeedbackEnabled: false,
        diagnosticLoggingEnabled: false,
      );

      final updatedState = await service.updateSettings(newSettings);
      expect(updatedState.settings.soundFeedbackEnabled, isFalse);
      expect(updatedState.settings.emergencyPauseAllowed, isFalse);

      final reloaded = await repo.loadSettings();
      expect(reloaded.soundFeedbackEnabled, isFalse);

      service.dispose();
      focusService.dispose();
    });

    // 4. Invalid settings rejection
    test('4. Invalid settings rejection prevents invalid target package and sub-60s duration', () async {
      final repo = InMemorySettingsRepository();
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();

      // Invalid target package
      expect(
        () => service.updateSettings(
          const AppSettings(
            defaultTargetPackage: 'com.android.settings',
            defaultUnlockDurationSeconds: 300,
            emergencyPauseAllowed: true,
            soundFeedbackEnabled: true,
            diagnosticLoggingEnabled: true,
          ),
        ),
        throwsA(isA<InvalidSettingsException>()),
      );

      // Sub-threshold duration (< 60s)
      expect(
        () => service.updateSettings(
          const AppSettings(
            defaultTargetPackage: ChannelConstants.targetYouTube,
            defaultUnlockDurationSeconds: 30,
            emergencyPauseAllowed: true,
            soundFeedbackEnabled: true,
            diagnosticLoggingEnabled: true,
          ),
        ),
        throwsA(isA<InvalidSettingsException>()),
      );

      // Over-threshold duration (> 900s)
      expect(
        () => service.updateSettings(
          const AppSettings(
            defaultTargetPackage: ChannelConstants.targetYouTube,
            defaultUnlockDurationSeconds: 1200,
            emergencyPauseAllowed: true,
            soundFeedbackEnabled: true,
            diagnosticLoggingEnabled: true,
          ),
        ),
        throwsA(isA<InvalidSettingsException>()),
      );

      service.dispose();
      focusService.dispose();
    });

    // 5. Storage failure recovery
    test('5. Storage failure recovery falls back to defaults without crashing', () async {
      final faultyRepo = InMemorySettingsRepository()..shouldFailLoad = true;
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: faultyRepo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      final state = await service.initialize();
      expect(state.settings, equals(AppSettings.defaults()));
      expect(state.isReady, isTrue);

      service.dispose();
      focusService.dispose();
    });

    // 6. State notifications
    test('6. State notifications emit through stateStream on every change', () async {
      final repo = InMemorySettingsRepository();
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      final emittedStates = <SettingsState>[];
      final sub = service.stateStream.listen(emittedStates.add);

      await service.initialize();
      await service.updateSettings(
        service.currentState.settings.copyWith(soundFeedbackEnabled: false),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emittedStates.length, greaterThanOrEqualTo(2));
      expect(emittedStates.last.settings.soundFeedbackEnabled, isFalse);

      await sub.cancel();
      service.dispose();
      focusService.dispose();
    });

    // 7. Accessibility permission granted
    test('7. Accessibility permission granted reflected in permissions and focus eligibility', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: false,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(status: CameraPermissionStatus.granted),
      );

      final state = await service.initialize();
      expect(state.isAccessibilityGranted, isTrue);
      expect(state.canEnableFocus, isTrue);
      expect(state.isReadyForChallenges, isTrue);

      service.dispose();
      focusService.dispose();
    });

    // 8. Accessibility permission missing
    test('8. Accessibility permission missing prevents focus activation', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: false,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(status: CameraPermissionStatus.granted),
      );

      final state = await service.initialize();
      expect(state.isAccessibilityGranted, isFalse);
      expect(state.canEnableFocus, isFalse);
      expect(state.isReadyForChallenges, isFalse);

      // Attempting to enable focus throws AccessibilityPermissionRequiredException
      expect(() => service.toggleFocus(true), throwsA(isA<AccessibilityPermissionRequiredException>()));

      service.dispose();
      focusService.dispose();
    });

    // 9. Camera permission denied
    test('9. Camera permission denied flags missing prerequisite for challenges', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: false,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final cameraChecker = MockCameraPermissionChecker(status: CameraPermissionStatus.denied);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: cameraChecker,
      );

      final state = await service.initialize();
      expect(state.isCameraGranted, isFalse);
      expect(state.cameraStatus, equals(CameraPermissionStatus.denied));
      expect(state.isReadyForChallenges, isFalse);

      service.dispose();
      focusService.dispose();
    });

    // 10. Permission state refresh after resume
    test('10. Permission state refresh updates state when permissions change in OS settings', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: false,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final cameraChecker = MockCameraPermissionChecker(status: CameraPermissionStatus.denied);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: cameraChecker,
      );

      await service.initialize();
      expect(service.currentState.isReadyForChallenges, isFalse);

      // Simulate user granting both permissions in Android OS settings
      bridge.status = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );
      cameraChecker.grantPermission();

      final refreshedState = await service.refresh();
      expect(refreshedState.isAccessibilityGranted, isTrue);
      expect(refreshedState.isCameraGranted, isTrue);
      expect(refreshedState.isReadyForChallenges, isTrue);

      service.dispose();
      focusService.dispose();
    });

    // 11. Externally revoked permission
    test('11. Externally revoked permission detected immediately on refresh', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: true,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final cameraChecker = MockCameraPermissionChecker(status: CameraPermissionStatus.granted);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: cameraChecker,
      );

      await service.initialize();
      expect(service.currentState.isReadyForChallenges, isTrue);

      // User revokes accessibility permission in OS settings
      bridge.status = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );

      final refreshed = await service.refresh();
      expect(refreshed.isAccessibilityGranted, isFalse);
      expect(refreshed.isReadyForChallenges, isFalse);

      service.dispose();
      focusService.dispose();
    });

    // 12. Voluntary Focus enable/disable coordination
    test('12. Voluntary Focus enable and disable coordinate with native gate', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: false,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();
      expect(service.currentState.isFocusEnabled, isFalse);

      await service.toggleFocus(true);
      expect(service.currentState.isFocusEnabled, isTrue);
      expect(bridge.status.isGateEnabled, isTrue);

      await service.toggleFocus(false);
      expect(service.currentState.isFocusEnabled, isFalse);
      expect(bridge.status.isGateEnabled, isFalse);

      service.dispose();
      focusService.dispose();
    });

    // 13. Single-target restrictions
    test('13. Single-target restriction permits only YouTube, Instagram, or TikTok', () async {
      final repo = InMemorySettingsRepository();
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();

      await service.setTargetApp(ChannelConstants.targetInstagram);
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetInstagram));

      await service.setTargetApp(ChannelConstants.targetTikTok);
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetTikTok));

      expect(() => service.setTargetApp('com.facebook.katana'), throwsA(isA<UnsupportedTargetException>()));

      service.dispose();
      focusService.dispose();
    });

    // 14. Target change synchronization
    test('14. Target change synchronizes to native bridge and invalidates active access', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetYouTube,
          isGateEnabled: true,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();

      await service.setTargetApp(ChannelConstants.targetInstagram);
      expect(bridge.status.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(bridge.callLog, contains('setTarget(${ChannelConstants.targetInstagram})'));

      service.dispose();
      focusService.dispose();
    });

    // 15. Existing five-minute reward invariant
    test('15. Default five-minute (300 seconds) reward invariant preserved', () {
      final settings = AppSettings.defaults();
      expect(settings.defaultUnlockDurationSeconds, equals(300));
      expect(settings.defaultUnlockDurationSeconds / 60, equals(5.0));
      expect(settings.isValid, isTrue);
    });

    // 16. Isolation between real and simulation environments
    test('16. Simulation mode uses isolated in-memory dependencies with no real IPC', () async {
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await controller.refreshAll();
      expect(controller.settingsService.currentState.isReady, isTrue);
      expect(controller.settingsService.currentState.isCameraGranted, isTrue);

      controller.dispose();
    });

    // 17. Correct disposal and lifecycle handling
    test('17. Correct disposal closes stream controllers without errors on subsequent calls', () {
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: FocusService(bridge: SimulationBridge()),
        nativeBridge: SimulationBridge(),
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      expect(() => service.dispose(), returnsNormally);
    });

    // 18. Existing module regression compatibility
    test('18. Settings service interacts cleanly with LevelUp SQLite database without wiping workout sessions', () async {
      // 1. Store a workout in workout_sessions
      final db = await database.database;
      await db.insert('workout_sessions', {
        'session_id': 'sess_persist_check',
        'request_id': 'req_1',
        'challenge_id': 'squats_unlock_5',
        'challenge_context': 'unlockChallenge',
        'exercise_type': 'squats',
        'target_package': ChannelConstants.targetYouTube,
        'completed_repetitions': 5,
        'duration_seconds': 45,
        'completed_at': DateTime.now().millisecondsSinceEpoch,
        'verification_source': 'realDevicePose',
      });

      // 2. Perform settings operations
      final repo = SqliteSettingsRepository(databaseManager: database);
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();
      await service.updateSettings(
        const AppSettings(
          defaultTargetPackage: ChannelConstants.targetYouTube,
          defaultUnlockDurationSeconds: 300,
          emergencyPauseAllowed: true,
          soundFeedbackEnabled: false,
          diagnosticLoggingEnabled: true,
        ),
      );

      // 3. Confirm workout session row remains intact
      final rows = await db.query('workout_sessions', where: 'session_id = ?', whereArgs: ['sess_persist_check']);
      expect(rows, hasLength(1));
      expect(rows.first['session_id'], equals('sess_persist_check'));

      service.dispose();
      focusService.dispose();
    });

    // 19. updateSettings does not inadvertently change native target
    test('19. updateSettings changing sound or diagnostic preferences does not change native target', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetInstagram,
          isGateEnabled: true,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final repo = InMemorySettingsRepository();
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetInstagram));

      bridge.callLog.clear();

      // Update sound feedback without explicitly changing target
      await service.updateSettings(
        service.currentState.settings.copyWith(soundFeedbackEnabled: false),
      );

      // Target must remain Instagram and setTarget must NOT have been called on bridge
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetInstagram));
      expect(bridge.status.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(bridge.callLog.where((c) => c.startsWith('setTarget')), isEmpty);

      service.dispose();
      focusService.dispose();
    });

    // 20. resetToDefaults preserves active native target and focus enabled state
    test('20. resetToDefaults resets user preferences without disabling Focus or switching target', () async {
      final bridge = SimulationBridge(
        initialStatus: const NativeFocusStatus(
          targetPackage: ChannelConstants.targetInstagram,
          isGateEnabled: true,
          permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
          accessStatus: NativeAccessStatus(),
        ),
      );
      final focusService = FocusService(bridge: bridge);
      final repo = InMemorySettingsRepository(
        initialSettings: const AppSettings(
          defaultTargetPackage: ChannelConstants.targetInstagram,
          defaultUnlockDurationSeconds: 300,
          emergencyPauseAllowed: false,
          soundFeedbackEnabled: false,
          diagnosticLoggingEnabled: false,
        ),
      );
      final service = SettingsService(
        repository: repo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();
      expect(service.currentState.isFocusEnabled, isTrue);
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetInstagram));

      await service.resetToDefaults();

      // Preferences are back to defaults
      expect(service.currentState.settings.soundFeedbackEnabled, isTrue);
      expect(service.currentState.settings.emergencyPauseAllowed, isTrue);
      // Active target and Focus state MUST NOT be disabled or switched
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetInstagram));
      expect(service.currentState.isFocusEnabled, isTrue);
      expect(bridge.status.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(bridge.status.isGateEnabled, isTrue);

      service.dispose();
      focusService.dispose();
    });

    // 21. setTargetApp persistence failure surfaces error while native state remains authoritative
    test('21. setTargetApp persistence failure surfaces error without hiding native authority', () async {
      final faultyRepo = InMemorySettingsRepository()..shouldFailSave = true;
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: faultyRepo,
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      await service.initialize();

      // Native target switches, but save throws SettingsPersistenceException
      await expectLater(
        () => service.setTargetApp(ChannelConstants.targetInstagram),
        throwsA(isA<SettingsPersistenceException>()),
      );

      // Native state was authoritatively updated
      expect(bridge.status.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(service.currentState.activeTargetPackage, equals(ChannelConstants.targetInstagram));
      expect(service.currentState.errorMessage, contains('failed to persist preference'));

      service.dispose();
      focusService.dispose();
    });

    // 22. openAppSettings dispatches openAppSettings on native bridge
    test('22. openAppSettings dispatches openAppSettings on native bridge', () async {
      final bridge = SimulationBridge();
      final focusService = FocusService(bridge: bridge);
      final service = SettingsService(
        repository: InMemorySettingsRepository(),
        focusService: focusService,
        nativeBridge: bridge,
        cameraPermissionChecker: MockCameraPermissionChecker(),
      );

      final success = await service.openAppSettings();
      expect(success, isTrue);
      expect(bridge.callLog, contains('openAppSettings'));

      service.dispose();
      focusService.dispose();
    });

    // 23. DefaultCameraPermissionChecker queries checkCameraPermission via native bridge
    test('23. DefaultCameraPermissionChecker queries checkCameraPermission without prompting', () async {
      final bridge = SimulationBridge();
      final checker = DefaultCameraPermissionChecker(nativeBridge: bridge);

      final status = await checker.checkCameraPermission();
      expect(status, equals(CameraPermissionStatus.granted));
      expect(bridge.callLog, contains('checkCameraPermission'));
    });
  });
}
