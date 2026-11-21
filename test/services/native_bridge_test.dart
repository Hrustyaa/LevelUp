import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/native_bridge_exception.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ChannelConstants.controlChannel);
  late NativeBridge bridge;
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    bridge = const NativeBridge(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void setMockHandler(Future<dynamic>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return handler(call);
    });
  }

  group('NativeBridge.getState', () {
    test('invokes getState and returns parsed NativeFocusStatus', () async {
      const unlockMs = 1700000000000;
      setMockHandler((call) async {
        if (call.method == ChannelConstants.methodGetState) {
          return <String, dynamic>{
            'target': 'com.instagram.android',
            'enabled': true,
            'unlockUntil': unlockMs,
            'serviceEnabled': true,
          };
        }
        return null;
      });

      final status = await bridge.getState();

      expect(log, hasLength(1));
      expect(log.first.method, equals(ChannelConstants.methodGetState));
      expect(log.first.arguments, isNull);

      expect(status.targetPackage, equals('com.instagram.android'));
      expect(status.isGateEnabled, isTrue);
      expect(status.isAccessibilityGranted, isTrue);
      expect(status.isServiceEnabled, isTrue);
      expect(status.unlockUntil?.millisecondsSinceEpoch, equals(unlockMs));
    });

    test('handles null native map gracefully with default values', () async {
      setMockHandler((call) async => null);

      final status = await bridge.getState();

      expect(status.targetPackage, equals(ChannelConstants.defaultTarget));
      expect(status.isGateEnabled, isFalse);
      expect(status.isAccessibilityGranted, isFalse);
      expect(status.unlockUntil, isNull);
    });

    test('wraps PlatformException in NativeBridgeException', () async {
      setMockHandler((call) async {
        throw PlatformException(code: 'FAILED', message: 'Gate lookup failed');
      });

      expect(
        () => bridge.getState(),
        throwsA(
          isA<NativeBridgeException>()
              .having((e) => e.code, 'code', equals('FAILED'))
              .having((e) => e.message, 'message', contains('Gate lookup failed')),
        ),
      );
    });

    test('wraps MissingPluginException in NativeBridgeNotImplementedException', () async {
      setMockHandler((call) async {
        throw MissingPluginException('No implementation found for method getState');
      });

      expect(
        () => bridge.getState(),
        throwsA(
          isA<NativeBridgeNotImplementedException>()
              .having((e) => e.method, 'method', equals(ChannelConstants.methodGetState))
              .having((e) => e.code, 'code', equals('NOT_IMPLEMENTED')),
        ),
      );
    });
  });

  group('NativeBridge.setTarget', () {
    test('invokes setTarget with serialized argument and returns true on success', () async {
      setMockHandler((call) async {
        if (call.method == ChannelConstants.methodSetTarget) {
          return true;
        }
        return null;
      });

      final success = await bridge.setTarget(ChannelConstants.targetTikTok);

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, equals(ChannelConstants.methodSetTarget));
      expect(
        log.first.arguments,
        equals({ChannelConstants.argTarget: ChannelConstants.targetTikTok}),
      );
    });

    test('throws UnsupportedTargetPackageException when native rejects target with code TARGET', () async {
      setMockHandler((call) async {
        throw PlatformException(
          code: 'TARGET',
          message: 'Unsupported test package',
        );
      });

      expect(
        () => bridge.setTarget('com.unsupported.app'),
        throwsA(
          isA<UnsupportedTargetPackageException>()
              .having((e) => e.targetPackage, 'targetPackage', equals('com.unsupported.app'))
              .having((e) => e.code, 'code', equals('TARGET')),
        ),
      );
    });

    test('wraps MissingPluginException in NativeBridgeNotImplementedException', () async {
      setMockHandler((call) async => throw MissingPluginException());

      expect(
        () => bridge.setTarget(ChannelConstants.targetYouTube),
        throwsA(isA<NativeBridgeNotImplementedException>()),
      );
    });
  });

  group('NativeBridge.setEnabled', () {
    test('invokes setEnabled with serialized argument', () async {
      setMockHandler((call) async => true);

      final resultTrue = await bridge.setEnabled(true);
      expect(resultTrue, isTrue);
      expect(
        log.last.arguments,
        equals({ChannelConstants.argEnabled: true}),
      );

      final resultFalse = await bridge.setEnabled(false);
      expect(resultFalse, isTrue);
      expect(
        log.last.arguments,
        equals({ChannelConstants.argEnabled: false}),
      );
    });

    test('wraps PlatformException in NativeBridgeException', () async {
      setMockHandler((call) async {
        throw PlatformException(code: 'PREFS_ERROR', message: 'Failed to write prefs');
      });

      expect(
        () => bridge.setEnabled(true),
        throwsA(isA<NativeBridgeException>()),
      );
    });
  });

  group('NativeBridge.openAccessibilitySettings', () {
    test('invokes openAccessibilitySettings without arguments and returns true', () async {
      setMockHandler((call) async => true);

      final success = await bridge.openAccessibilitySettings();

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, equals(ChannelConstants.methodOpenAccessibilitySettings));
      expect(log.first.arguments, isNull);
    });

    test('wraps PlatformException in NativeBridgeException', () async {
      setMockHandler((call) async {
        throw PlatformException(code: 'INTENT_FAILED', message: 'Activity not found');
      });

      expect(
        () => bridge.openAccessibilitySettings(),
        throwsA(isA<NativeBridgeException>()),
      );
    });
  });

  group('NativeBridge.consumeChallengeRequest', () {
    test('returns true when challenge was requested', () async {
      setMockHandler((call) async => true);

      final requested = await bridge.consumeChallengeRequest();

      expect(requested, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, equals(ChannelConstants.methodConsumeChallengeRequest));
    });

    test('returns false when challenge was not requested', () async {
      setMockHandler((call) async => false);

      final requested = await bridge.consumeChallengeRequest();

      expect(requested, isFalse);
    });

    test('wraps PlatformException in NativeBridgeException', () async {
      setMockHandler((call) async => throw PlatformException(code: 'ERR'));

      expect(
        () => bridge.consumeChallengeRequest(),
        throwsA(isA<NativeBridgeException>()),
      );
    });
  });

  group('NativeBridge.grantAccess', () {
    test('invokes grantAccess with minutes argument and parses return timestamp', () async {
      const returnedMs = 1700000300000;
      setMockHandler((call) async {
        if (call.method == ChannelConstants.methodGrantAccess) {
          return returnedMs;
        }
        return null;
      });

      final expiry = await bridge.grantAccess(minutes: 5);

      expect(log, hasLength(1));
      expect(log.first.method, equals(ChannelConstants.methodGrantAccess));
      expect(log.first.arguments, equals({ChannelConstants.argMinutes: 5}));
      expect(expiry.millisecondsSinceEpoch, equals(returnedMs));
    });

    test('throws MalformedNativeResponseException when native returns null or 0', () async {
      setMockHandler((call) async => null);

      expect(
        () => bridge.grantAccess(minutes: 5),
        throwsA(isA<MalformedNativeResponseException>()),
      );

      setMockHandler((call) async => 0);

      expect(
        () => bridge.grantAccess(minutes: 5),
        throwsA(isA<MalformedNativeResponseException>()),
      );
    });

    test('wraps PlatformException in NativeBridgeException', () async {
      setMockHandler((call) async {
        throw PlatformException(code: 'LAUNCH_ERROR', message: 'Target app not installed');
      });

      expect(
        () => bridge.grantAccess(minutes: 5),
        throwsA(isA<NativeBridgeException>()),
      );
    });
  });

  group('NativeBridge.resetAccess', () {
    test('invokes resetAccess and returns true', () async {
      setMockHandler((call) async => true);

      final success = await bridge.resetAccess();

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, equals(ChannelConstants.methodResetAccess));
      expect(log.first.arguments, isNull);
    });

    test('wraps PlatformException in NativeBridgeException', () async {
      setMockHandler((call) async {
        throw PlatformException(code: 'ERR', message: 'Reset failed');
      });

      expect(
        () => bridge.resetAccess(),
        throwsA(isA<NativeBridgeException>()),
      );
    });
  });

  group('NativeBridge.isAvailable', () {
    test('returns true when native getState responds successfully', () async {
      setMockHandler((call) async => <String, dynamic>{
        'target': 'com.google.android.youtube',
        'enabled': false,
        'unlockUntil': 0,
        'serviceEnabled': true,
      });

      final available = await bridge.isAvailable();
      expect(available, isTrue);
    });

    test('returns false when native throws MissingPluginException or PlatformException', () async {
      setMockHandler((call) async => throw MissingPluginException());

      final available = await bridge.isAvailable();
      expect(available, isFalse);
    });
  });

  group('Caller Capability Discrimination', () {
    test('callers can unambiguously distinguish all four operational states', () async {
      // Scenario 1: Focus disabled, Accessibility granted, No temporary access
      final status1 = NativeFocusStatus.fromMap({
        'target': 'com.google.android.youtube',
        'enabled': false,
        'serviceEnabled': true,
        'unlockUntil': 0,
      });

      expect(status1.isGateEnabled, isFalse, reason: 'Focus not enabled by user');
      expect(status1.isAccessibilityGranted, isTrue, reason: 'Accessibility granted');
      expect(status1.isAccessActive, isFalse, reason: 'No temporary access');

      // Scenario 2: Focus enabled by user, but Accessibility NOT granted
      final status2 = NativeFocusStatus.fromMap({
        'target': 'com.google.android.youtube',
        'enabled': true,
        'serviceEnabled': false,
        'unlockUntil': 0,
      });

      expect(status2.isGateEnabled, isTrue, reason: 'Focus enabled by user');
      expect(status2.isAccessibilityGranted, isFalse, reason: 'Accessibility missing');
      expect(status2.isAccessActive, isFalse, reason: 'No temporary access');

      // Scenario 3: Focus enabled, Accessibility granted, Temporary access active
      final futureMs = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      final status3 = NativeFocusStatus.fromMap({
        'target': 'com.google.android.youtube',
        'enabled': true,
        'serviceEnabled': true,
        'unlockUntil': futureMs,
      });

      expect(status3.isGateEnabled, isTrue, reason: 'Focus enabled');
      expect(status3.isAccessibilityGranted, isTrue, reason: 'Accessibility granted');
      expect(status3.isAccessActive, isTrue, reason: 'Temporary access active');
    });
  });
}
