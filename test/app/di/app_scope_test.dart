import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/di/app_scope.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/levelup_permissions.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/services/native_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
  });

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late Directory tempDir;
  late LevelUpDatabase database;
  late bool serviceEnabled;
  late List<String> methodCalls;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_scope_test_');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: p.join(tempDir.path, 'app_scope.db'),
    );
    serviceEnabled = false;
    methodCalls = <String>[];

    messenger.setMockMethodCallHandler(controlChannel, (call) async {
      methodCalls.add(call.method);
      if (call.method == ChannelConstants.methodGetState) {
        return {
          ChannelConstants.keyTarget: ChannelConstants.targetYouTube,
          ChannelConstants.keyEnabled: false,
          ChannelConstants.keyUnlockUntil: 0,
          ChannelConstants.keyServiceEnabled: serviceEnabled,
        };
      }
      if (call.method == ChannelConstants.methodCheckCameraPermission) {
        return 'granted';
      }
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(controlChannel, null);
    await database.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('AppScope Production Container Tests', () {
    test('1. initialize() opens SQLite database, initializes engines, and syncs native state', () async {
      final scope = AppScope.production(
        database: database,
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(
          status: CameraPermissionStatus.granted,
        ),
      );

      expect(scope.isInitialized, isFalse);

      await scope.initialize();

      expect(scope.isInitialized, isTrue);
      expect(database.isOpen, isTrue);
      expect(scope.settingsService.currentState.isLoading, isFalse);
      expect(scope.focusService.currentState?.selectedTarget, ChannelConstants.targetYouTube);
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));

      await scope.dispose();
      expect(database.isOpen, isFalse);
    });

    test('2. refresh() synchronizes updated Accessibility permission after resume', () async {
      final scope = AppScope.production(
        database: database,
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(
          status: CameraPermissionStatus.granted,
        ),
      );

      await scope.initialize();
      expect(scope.settingsService.currentState.isAccessibilityGranted, isFalse);

      // Simulate user enabling Accessibility in Android Settings
      serviceEnabled = true;
      await scope.refresh();

      expect(scope.settingsService.currentState.isAccessibilityGranted, isTrue);
      expect(scope.focusService.currentState?.isAccessibilityGranted, isTrue);

      await scope.dispose();
    });

    testWidgets('3. AppScopeProvider exposes AppScope via BuildContext', (tester) async {
      final scope = AppScope.production(
        database: database,
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(),
      );

      AppScope? resolvedScope;
      await tester.pumpWidget(
        AppScopeProvider(
          scope: scope,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                resolvedScope = AppScope.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(resolvedScope, same(scope));
      await scope.dispose();
    });

    test('4. AppScope.production() wires DefaultCameraPermissionChecker to NativeBridge without dialogs', () async {
      final scope = AppScope.production(
        database: database,
        nativeBridge: const NativeBridge(),
      );

      await scope.initialize();
      final states = await scope.permissionGateway.read();

      expect(methodCalls, contains(ChannelConstants.methodCheckCameraPermission));
      expect(states[LevelUpPermission.camera], PermissionState.granted);
      expect(states[LevelUpPermission.usage], PermissionState.unavailable);
      expect(states[LevelUpPermission.notifications], PermissionState.unavailable);

      await scope.dispose();
    });

    test('5. initialize() records initializationError and stays uninitialized on failure', () async {
      final scope = AppScope.production(
        database: _FailingDatabase(),
        nativeBridge: const NativeBridge(),
        cameraChecker: MockCameraPermissionChecker(),
      );

      await expectLater(() => scope.initialize(), throwsA(isA<StateError>()));
      expect(scope.isInitialized, isFalse);
      expect(scope.initializationError, isNotNull);

      await scope.dispose();
    });
  });
}

class _FailingDatabase extends LevelUpDatabase {
  @override
  Future<Database> get database =>
      Future.error(StateError('Database open failed'));
}
