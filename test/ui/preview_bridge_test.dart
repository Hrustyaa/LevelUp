import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const permissions = MethodChannel('levelup/permissions');
  const control = ExistingFocusGateway.channel;
  const gateway = ExistingFocusGateway();

  tearDown(() {
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(control, null);
  });

  test('preview leaves a legacy challenge request untouched', () async {
    messenger.setMockMethodCallHandler(control, (call) {
      fail('Unexpected legacy channel call: ${call.method}');
    });
    expect(await gateway.claimChallenge(), isNull);
  });

  test('a legacy boolean cannot open a verified challenge', () async {
    messenger.setMockMethodCallHandler(
      permissions,
      (_) async => {'accessibility': 'granted'},
    );
    messenger.setMockMethodCallHandler(control, (call) async {
      expect(call.method, 'consumeChallengeRequest');
      return true;
    });

    expect(await gateway.claimChallenge(), isNull);
  });
}
