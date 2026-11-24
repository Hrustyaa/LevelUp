import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/native_bridge_exception.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
import 'package:levelup_test/services/native_bridge.dart';

/// Fake implementation of [INativeBridge] for deterministic unit testing of [FocusService].
class FakeNativeBridge implements INativeBridge {
  bool isAvailableResult;
  NativeFocusStatus currentStatus;
  final List<String> callLog = [];
  final Map<String, dynamic> lastCallArguments = {};

  Object? getStateError;
  Object? setTargetError;
  Object? setEnabledError;
  Object? openSettingsError;

  FakeNativeBridge({
    NativeFocusStatus? initialStatus,
    this.isAvailableResult = true,
  }) : currentStatus = initialStatus ??
            const NativeFocusStatus(
              targetPackage: ChannelConstants.defaultTarget,
              isGateEnabled: false,
              permissionStatus:
                  NativePermissionStatus(isAccessibilityGranted: true),
              accessStatus: NativeAccessStatus(),
            );

  @override
  Future<bool> isAvailable() async {
    callLog.add('isAvailable');
    return isAvailableResult;
  }

  @override
  Future<NativeFocusStatus> getState() async {
    callLog.add('getState');
    if (getStateError != null) throw getStateError!;
    return currentStatus;
  }

  @override
  Future<bool> setTarget(String targetPackage) async {
    callLog.add('setTarget');
    lastCallArguments['target'] = targetPackage;
    if (setTargetError != null) throw setTargetError!;

    // Replicate Kotlin native side effect:
    // prefs.edit().putString("target", target).putLong("unlock_until", 0L).apply()
    currentStatus = NativeFocusStatus(
      targetPackage: targetPackage,
      isGateEnabled: currentStatus.isGateEnabled,
      permissionStatus: currentStatus.permissionStatus,
      accessStatus: const NativeAccessStatus(unlockUntil: null),
    );
    return true;
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    callLog.add('setEnabled');
    lastCallArguments['enabled'] = enabled;
    if (setEnabledError != null) throw setEnabledError!;

    currentStatus = NativeFocusStatus(
      targetPackage: currentStatus.targetPackage,
      isGateEnabled: enabled,
      permissionStatus: currentStatus.permissionStatus,
      accessStatus: currentStatus.accessStatus,
    );
    return true;
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    callLog.add('openAccessibilitySettings');
    if (openSettingsError != null) throw openSettingsError!;
    return true;
  }

  @override
  Future<bool> consumeChallengeRequest() async {
    callLog.add('consumeChallengeRequest');
    return false;
  }

  @override
  Future<DateTime> grantAccess({int minutes = 5}) async {
    callLog.add('grantAccess');
    throw UnimplementedError('grantAccess must never be invoked by FocusService');
  }

  @override
  Future<bool> resetAccess() async {
    callLog.add('resetAccess');
    currentStatus = NativeFocusStatus(
      targetPackage: currentStatus.targetPackage,
      isGateEnabled: currentStatus.isGateEnabled,
      permissionStatus: currentStatus.permissionStatus,
      accessStatus: const NativeAccessStatus(unlockUntil: null),
    );
    return true;
  }

  @override
  Future<bool> openAppSettings() async {
    callLog.add('openAppSettings');
    return true;
  }

  @override
  Future<String> checkCameraPermission() async {
    callLog.add('checkCameraPermission');
    return 'granted';
  }
}

void main() {
  late FakeNativeBridge fakeBridge;
  late FocusService focusService;

  setUp(() {
    fakeBridge = FakeNativeBridge();
    focusService = FocusService(bridge: fakeBridge);
  });

  tearDown(() {
    focusService.dispose();
  });

  group('Initialization', () {
    test('does not perform implicit native calls or activate focus on creation', () {
      final freshBridge = FakeNativeBridge();
      final service = FocusService(bridge: freshBridge);

      expect(freshBridge.callLog, isEmpty);
      expect(service.currentState, isNull);

      service.dispose();
    });
  });

  group('Reading Focus Status', () {
    test('getFocusStatus reads and maps native focus status accurately', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetInstagram,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      final state = await focusService.getFocusStatus();

      expect(state.selectedTarget, equals(ChannelConstants.targetInstagram));
      expect(state.isUserEnabled, isTrue);
      expect(state.isAccessibilityGranted, isTrue);
      expect(state.isBridgeAvailable, isTrue);
      expect(state.isAccessActive, isFalse);
      expect(state.isRestrictionEffective, isTrue);

      expect(focusService.currentState, equals(state));
      expect(fakeBridge.callLog, contains('getState'));
    });

    test('getSelectedTarget returns current selected target package', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetTikTok,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );

      final target = await focusService.getSelectedTarget();
      expect(target, equals(ChannelConstants.targetTikTok));
    });

    test('getPermissionStatus returns native permission status', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.defaultTarget,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      final perm = await focusService.getPermissionStatus();
      expect(perm.isAccessibilityGranted, isTrue);
    });
  });

  group('Enabling Focus', () {
    test('enables focus successfully when accessibility permission is granted', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      final state = await focusService.enableFocus();

      expect(state.isUserEnabled, isTrue);
      expect(fakeBridge.callLog, contains('setEnabled'));
      expect(fakeBridge.lastCallArguments['enabled'], isTrue);
      expect(state.isRestrictionEffective, isTrue);
    });

    test('throws AccessibilityPermissionRequiredException when accessibility permission is missing', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );

      expect(
        () => focusService.enableFocus(),
        throwsA(isA<AccessibilityPermissionRequiredException>()),
      );

      // Verify native setEnabled was NEVER invoked without permission
      expect(fakeBridge.callLog, isNot(contains('setEnabled')));
    });

    test('throws FocusStateSyncException when native setEnabled throws', () async {
      fakeBridge.setEnabledError = const NativeBridgeException(
        message: 'SharedPreferences write failed',
        code: 'IO_ERROR',
      );

      expect(
        () => focusService.enableFocus(),
        throwsA(isA<FocusStateSyncException>()),
      );
    });
  });

  group('Disabling Focus (Safe Exit)', () {
    test('disables focus successfully and confirms native state', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      final state = await focusService.disableFocus();

      expect(state.isUserEnabled, isFalse);
      expect(fakeBridge.callLog, contains('setEnabled'));
      expect(fakeBridge.lastCallArguments['enabled'], isFalse);
      expect(state.isRestrictionEffective, isFalse);
    });

    test('disabling focus succeeds even if accessibility permission is not granted (safe exit)', () async {
      fakeBridge.currentStatus = const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );

      final state = await focusService.disableFocus();

      expect(state.isUserEnabled, isFalse);
      expect(fakeBridge.callLog, contains('setEnabled'));
      expect(fakeBridge.lastCallArguments['enabled'], isFalse);
    });

    test('throws FocusStateSyncException when native disable fails', () async {
      fakeBridge.setEnabledError = const NativeBridgeException(
        message: 'Platform failure',
        code: 'ERR',
      );

      expect(
        () => focusService.disableFocus(),
        throwsA(isA<FocusStateSyncException>()),
      );
    });
  });

  group('Target Selection', () {
    test('selects supported target and confirms native state', () async {
      for (final target in ChannelConstants.allowedTargets) {
        final state = await focusService.selectTargetApp(target);

        expect(state.selectedTarget, equals(target));
        expect(fakeBridge.lastCallArguments['target'], equals(target));
      }
    });

    test('rejects unsupported target package with UnsupportedTargetException', () async {
      const unsupported = 'com.facebook.katana';

      expect(
        () => focusService.selectTargetApp(unsupported),
        throwsA(
          isA<UnsupportedTargetException>()
              .having((e) => e.packageName, 'packageName', equals(unsupported)),
        ),
      );

      // Verify bridge setTarget was not called for invalid package
      expect(fakeBridge.callLog, isNot(contains('setTarget')));
    });

    test('selecting a different target revokes active temporary access (native side-effect)', () async {
      // Setup state with active unlock
      final futureExpiry = DateTime.now().add(const Duration(minutes: 5));
      fakeBridge.currentStatus = NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(unlockUntil: futureExpiry),
      );

      // Confirm unlock is initially active
      final initial = await focusService.getFocusStatus();
      expect(initial.isAccessActive, isTrue);

      // Switch target to Instagram
      final updated = await focusService.selectTargetApp(ChannelConstants.targetInstagram);

      // Verify target changed AND access was cleared
      expect(updated.selectedTarget, equals(ChannelConstants.targetInstagram));
      expect(updated.isAccessActive, isFalse);
      expect(updated.unlockUntil, isNull);
    });
  });

  group('Accessibility Settings Intent', () {
    test('openAccessibilitySettings dispatches native intent', () async {
      final result = await focusService.openAccessibilitySettings();

      expect(result, isTrue);
      expect(fakeBridge.callLog, contains('openAccessibilitySettings'));
    });

    test('throws FocusStateSyncException when opening settings fails', () async {
      fakeBridge.openSettingsError = const NativeBridgeException(
        message: 'Activity not found',
        code: 'NO_ACTIVITY',
      );

      expect(
        () => focusService.openAccessibilitySettings(),
        throwsA(isA<FocusStateSyncException>()),
      );
    });
  });

  group('Bridge Unavailable & Error Handling', () {
    test('returns unavailable state when bridge isAvailable is false', () async {
      fakeBridge.isAvailableResult = false;

      final state = await focusService.getFocusStatus();

      expect(state.isBridgeAvailable, isFalse);
      expect(state.isRestrictionEffective, isFalse);
      expect(state.isUserEnabled, isFalse);
    });

    test('enableFocus throws NativeBridgeUnavailableException when bridge is offline', () async {
      fakeBridge.isAvailableResult = false;

      expect(
        () => focusService.enableFocus(),
        throwsA(isA<NativeBridgeUnavailableException>()),
      );
    });

    test('selectTargetApp throws NativeBridgeUnavailableException when bridge is offline', () async {
      fakeBridge.isAvailableResult = false;

      expect(
        () => focusService.selectTargetApp(ChannelConstants.targetInstagram),
        throwsA(isA<NativeBridgeUnavailableException>()),
      );
    });

    test('refreshState throws FocusStateSyncException when bridge throws unexpected exception', () async {
      fakeBridge.getStateError = const NativeBridgeException(
        message: 'IPC channel closed',
        code: 'IPC_CLOSED',
      );

      expect(
        () => focusService.refreshState(),
        throwsA(isA<FocusStateSyncException>()),
      );
    });
  });

  group('Access State & Invariant Checks', () {
    test('never calls grantAccess from FocusService under any circumstance', () async {
      // Execute all public methods of FocusService
      await focusService.getFocusStatus();
      await focusService.enableFocus();
      await focusService.disableFocus();
      await focusService.selectTargetApp(ChannelConstants.targetTikTok);
      await focusService.getSelectedTarget();
      await focusService.getPermissionStatus();
      await focusService.openAccessibilitySettings();
      await focusService.refreshState();

      // Assert grantAccess was NEVER called
      expect(
        fakeBridge.callLog,
        isNot(contains('grantAccess')),
        reason: 'FocusService must never issue or manage access grants',
      );
    });

    test('restriction is NOT effective while temporary access is active', () async {
      final future = DateTime.now().add(const Duration(minutes: 5));
      fakeBridge.currentStatus = NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: true,
        permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(unlockUntil: future),
      );

      final state = await focusService.getFocusStatus();

      expect(state.isUserEnabled, isTrue);
      expect(state.isAccessibilityGranted, isTrue);
      expect(state.isAccessActive, isTrue);
      expect(state.remainingAccess.inSeconds, greaterThan(0));
      expect(
        state.isRestrictionEffective,
        isFalse,
        reason: 'User has unlocked temporary access, gate is not blocking',
      );
    });
  });

  group('Reactive stateStream', () {
    test('emits state updates on refresh and operations', () async {
      final emittedStates = <FocusState>[];
      final subscription = focusService.stateStream.listen(emittedStates.add);

      await focusService.refreshState();
      await focusService.enableFocus();
      await focusService.selectTargetApp(ChannelConstants.targetInstagram);
      await focusService.disableFocus();

      await pumpEventQueue();

      expect(emittedStates.length, equals(4));
      expect(emittedStates[0].isUserEnabled, isFalse);
      expect(emittedStates[1].isUserEnabled, isTrue);
      expect(emittedStates[2].selectedTarget, equals(ChannelConstants.targetInstagram));
      expect(emittedStates[3].isUserEnabled, isFalse);

      await subscription.cancel();
    });
  });
}
