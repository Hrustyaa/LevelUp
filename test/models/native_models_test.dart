import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';

void main() {
  group('NativePermissionStatus', () {
    test('creates from boolean correctly', () {
      const statusTrue = NativePermissionStatus(isAccessibilityGranted: true);
      expect(statusTrue.isAccessibilityGranted, isTrue);

      const statusFalse = NativePermissionStatus(isAccessibilityGranted: false);
      expect(statusFalse.isAccessibilityGranted, isFalse);
    });

    test('fromRaw handles various raw types gracefully', () {
      expect(NativePermissionStatus.fromRaw(true).isAccessibilityGranted, isTrue);
      expect(NativePermissionStatus.fromRaw(false).isAccessibilityGranted, isFalse);
      expect(NativePermissionStatus.fromRaw(null).isAccessibilityGranted, isFalse);
      expect(NativePermissionStatus.fromRaw('true').isAccessibilityGranted, isFalse);
      expect(NativePermissionStatus.fromRaw(1).isAccessibilityGranted, isFalse);
    });

    test('implements value equality and toString', () {
      const a = NativePermissionStatus(isAccessibilityGranted: true);
      const b = NativePermissionStatus(isAccessibilityGranted: true);
      const c = NativePermissionStatus(isAccessibilityGranted: false);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('isAccessibilityGranted: true'));
    });
  });

  group('NativeAccessStatus', () {
    test('fromEpochMs parses valid timestamps', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final status = NativeAccessStatus.fromEpochMs(nowMs);

      expect(status.unlockUntil, isNotNull);
      expect(status.unlockUntil!.millisecondsSinceEpoch, equals(nowMs));
    });

    test('fromEpochMs handles 0, negative and invalid types safely', () {
      expect(NativeAccessStatus.fromEpochMs(0).unlockUntil, isNull);
      expect(NativeAccessStatus.fromEpochMs(-500).unlockUntil, isNull);
      expect(NativeAccessStatus.fromEpochMs(null).unlockUntil, isNull);
      expect(NativeAccessStatus.fromEpochMs('not-a-number').unlockUntil, isNull);
    });

    test('fromEpochMs supports double/num values', () {
      const numMs = 1700000000000.0;
      final status = NativeAccessStatus.fromEpochMs(numMs);
      expect(status.unlockUntil?.millisecondsSinceEpoch, equals(1700000000000));
    });

    test('isAccessActive correctly computes active state relative to reference time', () {
      final reference = DateTime(2026, 11, 21, 12, 0);
      final futureAccess = NativeAccessStatus(
        unlockUntil: reference.add(const Duration(minutes: 5)),
      );
      final expiredAccess = NativeAccessStatus(
        unlockUntil: reference.subtract(const Duration(minutes: 1)),
      );
      const noAccess = NativeAccessStatus(unlockUntil: null);

      expect(futureAccess.isAccessActive(reference), isTrue);
      expect(expiredAccess.isAccessActive(reference), isFalse);
      expect(noAccess.isAccessActive(reference), isFalse);
    });

    test('remainingAccess returns accurate duration or Duration.zero if expired', () {
      final reference = DateTime(2026, 11, 21, 12, 0);
      final futureAccess = NativeAccessStatus(
        unlockUntil: reference.add(const Duration(minutes: 3)),
      );
      final expiredAccess = NativeAccessStatus(
        unlockUntil: reference.subtract(const Duration(minutes: 2)),
      );
      const noAccess = NativeAccessStatus(unlockUntil: null);

      expect(futureAccess.remainingAccess(reference), equals(const Duration(minutes: 3)));
      expect(expiredAccess.remainingAccess(reference), equals(Duration.zero));
      expect(noAccess.remainingAccess(reference), equals(Duration.zero));
    });

    test('implements value equality and toString', () {
      final date = DateTime(2026, 11, 21);
      final a = NativeAccessStatus(unlockUntil: date);
      final b = NativeAccessStatus(unlockUntil: date);
      const c = NativeAccessStatus(unlockUntil: null);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('unlockUntil'));
    });
  });

  group('NativeFocusStatus', () {
    test('fromMap parses complete valid map accurately', () {
      final nowMs = DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      final rawMap = <String, dynamic>{
        'target': 'com.instagram.android',
        'enabled': true,
        'serviceEnabled': true,
        'unlockUntil': nowMs,
      };

      final status = NativeFocusStatus.fromMap(rawMap);

      expect(status.targetPackage, equals('com.instagram.android'));
      expect(status.isGateEnabled, isTrue);
      expect(status.isAccessibilityGranted, isTrue);
      expect(status.isServiceEnabled, isTrue);
      expect(status.isAccessActive, isTrue);
      expect(status.unlockUntil?.millisecondsSinceEpoch, equals(nowMs));
      expect(status.remainingAccess.inSeconds, greaterThan(0));
    });

    test('fromMap handles null input with robust default values', () {
      final status = NativeFocusStatus.fromMap(null);

      expect(status.targetPackage, equals(ChannelConstants.defaultTarget));
      expect(status.isGateEnabled, isFalse);
      expect(status.isAccessibilityGranted, isFalse);
      expect(status.isServiceEnabled, isFalse);
      expect(status.isAccessActive, isFalse);
      expect(status.unlockUntil, isNull);
      expect(status.remainingAccess, equals(Duration.zero));
    });

    test('fromMap handles empty map and missing keys gracefully', () {
      final status = NativeFocusStatus.fromMap({});

      expect(status.targetPackage, equals(ChannelConstants.defaultTarget));
      expect(status.isGateEnabled, isFalse);
      expect(status.isAccessibilityGranted, isFalse);
      expect(status.isAccessActive, isFalse);
      expect(status.unlockUntil, isNull);
    });

    test('fromMap handles unexpected types for fields without crashing', () {
      final rawMap = <dynamic, dynamic>{
        'target': 12345, // invalid type
        'enabled': 'yes', // invalid type
        'serviceEnabled': null,
        'unlockUntil': 'not_a_timestamp',
      };

      final status = NativeFocusStatus.fromMap(rawMap);

      expect(status.targetPackage, equals(ChannelConstants.defaultTarget));
      expect(status.isGateEnabled, isFalse);
      expect(status.isAccessibilityGranted, isFalse);
      expect(status.unlockUntil, isNull);
    });

    test('toMap converts back to map representation matching native keys', () {
      final unlockDate = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final status = NativeFocusStatus(
        targetPackage: 'com.zhiliaoapp.musically',
        isGateEnabled: true,
        permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(unlockUntil: unlockDate),
      );

      final map = status.toMap();

      expect(map[ChannelConstants.keyTarget], equals('com.zhiliaoapp.musically'));
      expect(map[ChannelConstants.keyEnabled], isTrue);
      expect(map[ChannelConstants.keyServiceEnabled], isTrue);
      expect(map[ChannelConstants.keyUnlockUntil], equals(1700000000000));
    });

    test('implements value equality and toString', () {
      const a = NativeFocusStatus(
        targetPackage: ChannelConstants.defaultTarget,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );
      const b = NativeFocusStatus(
        targetPackage: ChannelConstants.defaultTarget,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );
      const c = NativeFocusStatus(
        targetPackage: 'com.instagram.android',
        isGateEnabled: true,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('com.google.android.youtube'));
    });
  });
}
