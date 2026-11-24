import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/adapters/core_focus_gateway_adapter.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';
import 'package:levelup_test/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const controlChannel = MethodChannel(ChannelConstants.controlChannel);

  late String currentTarget;
  late bool currentEnabled;
  late bool currentServiceEnabled;
  late int currentUnlockUntil;
  late List<String> methodCalls;
  Completer<void>? delayNextSetEnabled;

  late FocusService focusService;
  late CoreFocusGatewayAdapter adapter;

  setUp(() {
    currentTarget = ChannelConstants.targetYouTube;
    currentEnabled = false;
    currentServiceEnabled = true;
    currentUnlockUntil = 0;
    methodCalls = <String>[];
    delayNextSetEnabled = null;

    messenger.setMockMethodCallHandler(controlChannel, (call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case ChannelConstants.methodGetState:
          return {
            ChannelConstants.keyTarget: currentTarget,
            ChannelConstants.keyEnabled: currentEnabled,
            ChannelConstants.keyUnlockUntil: currentUnlockUntil,
            ChannelConstants.keyServiceEnabled: currentServiceEnabled,
          };
        case ChannelConstants.methodSetTarget:
          final args = call.arguments as Map<dynamic, dynamic>;
          currentTarget = args[ChannelConstants.argTarget] as String;
          currentUnlockUntil = 0;
          return true;
        case ChannelConstants.methodSetEnabled:
          if (delayNextSetEnabled != null) {
            await delayNextSetEnabled!.future;
          }
          final args = call.arguments as Map<dynamic, dynamic>;
          currentEnabled = args[ChannelConstants.argEnabled] as bool;
          return true;
        default:
          return null;
      }
    });

    focusService = FocusService(bridge: const NativeBridge());
    adapter = CoreFocusGatewayAdapter(focusService: focusService);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(controlChannel, null);
    focusService.dispose();
  });

  group('CoreFocusGatewayAdapter Tests', () {
    test('1. read() synchronizes authoritative native state and preserves active unlockUntil', () async {
      final futureUnlock = DateTime.now().add(const Duration(minutes: 4));
      currentEnabled = true;
      currentServiceEnabled = true;
      currentTarget = ChannelConstants.targetInstagram;
      currentUnlockUntil = futureUnlock.millisecondsSinceEpoch;

      final snapshot = await adapter.read();

      expect(snapshot.enabled, isTrue);
      expect(snapshot.serviceEnabled, isTrue);
      expect(snapshot.active, isTrue);
      expect(snapshot.targets, [ChannelConstants.targetInstagram]);
      expect(
        snapshot.accessUntil[ChannelConstants.targetInstagram]?.millisecondsSinceEpoch,
        futureUnlock.millisecondsSinceEpoch,
      );
      expect(methodCalls, isNotEmpty);
      expect(methodCalls, everyElement(ChannelConstants.methodGetState));
    });

    test('2. enable() activates Focus and sets supported target via FocusService', () async {
      await adapter.enable(target: ChannelConstants.targetTikTok);

      expect(currentTarget, ChannelConstants.targetTikTok);
      expect(currentEnabled, isTrue);
      expect(methodCalls, contains(ChannelConstants.methodSetTarget));
      expect(methodCalls, contains(ChannelConstants.methodSetEnabled));
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });

    test('3. enable() fails with AccessibilityPermissionRequiredException when permission is missing', () async {
      currentServiceEnabled = false;

      await expectLater(
        () => adapter.enable(target: ChannelConstants.targetYouTube),
        throwsA(isA<AccessibilityPermissionRequiredException>()),
      );

      expect(currentEnabled, isFalse);
      expect(methodCalls, isNot(contains(ChannelConstants.methodGrantAccess)));
    });

    test('4. enable() rejects unsupported target package without touching native enable', () async {
      await expectLater(
        () => adapter.enable(target: 'com.unsupported.app'),
        throwsA(isA<UnsupportedTargetException>()),
      );

      expect(currentEnabled, isFalse);
      expect(methodCalls, isNot(contains(ChannelConstants.methodSetEnabled)));
    });

    test('5. disable() turns off Focus via FocusService', () async {
      currentEnabled = true;
      await adapter.disable();

      expect(currentEnabled, isFalse);
      expect(methodCalls, contains(ChannelConstants.methodSetEnabled));
    });

    test('6. Anti-racing lock rejects concurrent enable/disable calls', () async {
      final gate = Completer<void>();
      delayNextSetEnabled = gate;

      final firstCall = adapter.enable(target: ChannelConstants.targetYouTube);
      // Allow async getState to reach setEnabled
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await expectLater(
        () => adapter.disable(),
        throwsA(isA<FocusStateSyncException>()),
      );

      gate.complete();
      await firstCall;
      expect(currentEnabled, isTrue);
    });
  });
}
