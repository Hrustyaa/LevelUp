import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/android_usage_gateway.dart';
import 'package:levelup_test/data/dashboard_data.dart';

const _usage = MethodChannel('levelup/usage');
const _notifications = MethodChannel('levelup/focus_notifications');
const _id = 'com.google.android.youtube';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    for (final channel in [
      _usage,
      _notifications,
      ExistingFocusGateway.channel,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'reads selected app minutes and preserves missing days and metrics',
    () async {
      final date = DateTime(2026, 11, 22);
      messenger.setMockMethodCallHandler(_usage, (call) async {
        expect(call.method, 'getScreenTime');
        expect(call.arguments, {
          'packageIds': [_id],
        });
        return {
          'todayMs': 181500,
          'byAppMs': {_id: 181500, 'not.selected': 990000},
          'week': [
            {'dateMs': date.millisecondsSinceEpoch, 'durationMs': 181500},
          ],
        };
      });

      final usage = await const AndroidUsageGateway().read({_id});
      expect(usage.todayUsageMinutes, 3);
      expect(usage.week.single.date, date);
      expect(usage.week.single.minutes, 3);
      expect(usage.usageByApp, {_id: 3});
      expect(usage.todayUnlocks, isNull);
      expect(usage.totalXp, isNull);
      expect(usage.events, isEmpty);
    },
  );

  test(
    'denied or revoked usage access clears the previous observations',
    () async {
      var granted = true;
      messenger.setMockMethodCallHandler(_usage, (_) async {
        return granted
            ? {
                'todayMs': 0,
                'byAppMs': {_id: 0},
              }
            : null;
      });
      const gateway = AndroidUsageGateway();

      expect((await gateway.read({_id})).todayUsageMinutes, 0);
      granted = false;
      final missing = await gateway.read({_id});
      expect(missing.todayUsageMinutes, isNull);
      expect(missing.week, isEmpty);
      expect(missing.usageByApp, isEmpty);
    },
  );

  test('only confirmed manual Focus state changes trigger alerts', () async {
    var enabled = false;
    var reject = false;
    final alerts = <Object?>[];
    messenger.setMockMethodCallHandler(ExistingFocusGateway.channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getState':
          return {'enabled': enabled, 'serviceEnabled': true, 'target': _id};
        case 'setTarget':
          return true;
        case 'setEnabled':
          if (reject) return false;
          enabled = (call.arguments as Map)['enabled'] as bool;
          return true;
      }
      throw StateError(call.method);
    });
    messenger.setMockMethodCallHandler(_notifications, (call) async {
      expect(call.method, 'postManualChange');
      alerts.add(call.arguments);
      return null;
    });
    const gateway = ExistingFocusGateway(
      notificationLanguage: DashboardLanguage.ru,
    );

    await gateway.enable(target: _id);
    await Future<void>.delayed(Duration.zero);
    await gateway.enable(target: _id);
    await gateway.disable();
    await Future<void>.delayed(Duration.zero);
    reject = true;
    await expectLater(gateway.enable(), throwsStateError);
    await Future<void>.delayed(Duration.zero);

    expect(alerts, [
      {'enabled': true, 'language': 'ru'},
      {'enabled': false, 'language': 'ru'},
    ]);
  });
}
