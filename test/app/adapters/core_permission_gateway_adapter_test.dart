import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/adapters/core_permission_gateway_adapter.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/levelup_permissions.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/application/settings_service.dart';
import 'package:levelup_test/features/settings/data/settings_repository.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late bool serviceEnabled;
  late List<String> methodCalls;
  late MockCameraPermissionChecker cameraChecker;
  late FocusService focusService;
  late SettingsService settingsService;
  late CorePermissionGatewayAdapter adapter;

  setUp(() async {
    serviceEnabled = false;
    methodCalls = <String>[];

    messenger.setMockMethodCallHandler(controlChannel, (call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case ChannelConstants.methodGetState:
          return {
            ChannelConstants.keyTarget: ChannelConstants.targetYouTube,
            ChannelConstants.keyEnabled: false,
            ChannelConstants.keyUnlockUntil: 0,
            ChannelConstants.keyServiceEnabled: serviceEnabled,
          };
        case ChannelConstants.methodOpenAccessibilitySettings:
        case ChannelConstants.methodOpenAppSettings:
          return true;
        default:
          return null;
      }
    });

    const bridge = NativeBridge();
    focusService = FocusService(bridge: bridge);
    cameraChecker = MockCameraPermissionChecker(
      status: CameraPermissionStatus.denied,
    );
    settingsService = SettingsService(
      repository: InMemorySettingsRepository(),
      focusService: focusService,
      nativeBridge: bridge,
      cameraPermissionChecker: cameraChecker,
    );
    await settingsService.initialize();

    adapter = CorePermissionGatewayAdapter(
      settingsService: settingsService,
      nativeBridge: bridge,
      cameraChecker: cameraChecker,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(controlChannel, null);
    settingsService.dispose();
    focusService.dispose();
  });

  group('CorePermissionGatewayAdapter Tests', () {
    test('1. Maps denied accessibility and denied camera accurately; marks usage and notifications unavailable', () async {
      final states = await adapter.read();

      expect(states[LevelUpPermission.accessibility], PermissionState.denied);
      expect(states[LevelUpPermission.camera], PermissionState.denied);
      expect(states[LevelUpPermission.usage], PermissionState.unavailable);
      expect(
        states[LevelUpPermission.notifications],
        PermissionState.unavailable,
      );
    });

    test('2. Refreshes granted accessibility and camera states after change', () async {
      serviceEnabled = true;
      cameraChecker.status = CameraPermissionStatus.granted;

      final states = await adapter.read();

      expect(states[LevelUpPermission.accessibility], PermissionState.granted);
      expect(states[LevelUpPermission.camera], PermissionState.granted);
      // Unsupported capabilities remain unavailable even when core permissions are granted
      expect(states[LevelUpPermission.usage], PermissionState.unavailable);
      expect(
        states[LevelUpPermission.notifications],
        PermissionState.unavailable,
      );
    });

    test('3. Permanently denied camera maps to unavailable', () async {
      cameraChecker.status = CameraPermissionStatus.permanentlyDenied;

      final states = await adapter.read();

      expect(states[LevelUpPermission.camera], PermissionState.unavailable);
    });

    test('4. request(accessibility) opens Accessibility Settings without granting', () async {
      await adapter.request(LevelUpPermission.accessibility);

      expect(methodCalls, contains(ChannelConstants.methodOpenAccessibilitySettings));
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });

    test('5. request(camera) triggers camera permission request without native grantAccess', () async {
      await adapter.request(LevelUpPermission.camera);

      expect(cameraChecker.requestCount, 1);
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });

    test('6. request(usage/notifications) is a no-op and never fakes granted state', () async {
      methodCalls.clear();
      await adapter.request(LevelUpPermission.usage);
      await adapter.request(LevelUpPermission.notifications);

      expect(methodCalls, isEmpty);
      final states = await adapter.read();
      expect(states[LevelUpPermission.usage], PermissionState.unavailable);
      expect(
        states[LevelUpPermission.notifications],
        PermissionState.unavailable,
      );
    });

    test('7. openAppSettings and openPermissionSettings dispatch correct native intents', () async {
      await adapter.openAppSettings();
      await adapter.openPermissionSettings(LevelUpPermission.accessibility);
      await adapter.openPermissionSettings(LevelUpPermission.camera);
      await adapter.openPermissionSettings(LevelUpPermission.usage);

      expect(
        methodCalls.where((m) => m == ChannelConstants.methodOpenAppSettings).length,
        2,
      );
      expect(
        methodCalls
            .where((m) => m == ChannelConstants.methodOpenAccessibilitySettings)
            .length,
        1,
      );
    });
    test('8. Supplemental Android permissions use their own channel', () async {
      const channel = MethodChannel('levelup/permissions');
      final calls = <(String, Object?)>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add((call.method, (call.arguments as Map?)?['permission']));
        return switch (call.method) {
          'getStates' => {'accessibility': 'granted', 'usage': 'granted', 'notifications': 'denied'},
          _ => null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final productionAdapter = CorePermissionGatewayAdapter(
        settingsService: settingsService,
        nativeBridge: const NativeBridge(),
        cameraChecker: cameraChecker,
        optionalPermissions: const AndroidPermissionGateway(),
      );
      final states = await productionAdapter.read();
      expect(states[LevelUpPermission.accessibility], PermissionState.denied);
      expect(states[LevelUpPermission.usage], PermissionState.granted);
      expect(states[LevelUpPermission.notifications], PermissionState.denied);
      await productionAdapter.request(LevelUpPermission.notifications);
      await productionAdapter.openPermissionSettings(LevelUpPermission.usage);
      expect(calls, [('getStates', null), ('request', 'notifications'), ('openPermissionSettings', 'usage')]);
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });
  });
}
