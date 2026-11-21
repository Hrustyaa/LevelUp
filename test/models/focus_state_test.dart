import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/models/focus_state.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';

void main() {
  group('FocusState', () {
    test('isRestrictionEffective is true only when all conditions are satisfied', () {
      // 1. Effective: bridge available, user enabled, permission granted, access not active
      final effective = FocusState(
        selectedTarget: ChannelConstants.targetYouTube,
        isUserEnabled: true,
        isAccessibilityGranted: true,
        isBridgeAvailable: true,
        isAccessActive: false,
        remainingAccess: Duration.zero,
      );
      expect(effective.isRestrictionEffective, isTrue);

      // 2. Not effective: temporary access is active (unlocked)
      final unlocked = FocusState(
        selectedTarget: ChannelConstants.targetYouTube,
        isUserEnabled: true,
        isAccessibilityGranted: true,
        isBridgeAvailable: true,
        isAccessActive: true,
        remainingAccess: const Duration(minutes: 5),
      );
      expect(unlocked.isRestrictionEffective, isFalse);

      // 3. Not effective: user disabled
      final disabled = FocusState(
        selectedTarget: ChannelConstants.targetYouTube,
        isUserEnabled: false,
        isAccessibilityGranted: true,
        isBridgeAvailable: true,
        isAccessActive: false,
        remainingAccess: Duration.zero,
      );
      expect(disabled.isRestrictionEffective, isFalse);

      // 4. Not effective: accessibility permission missing
      final noA11y = FocusState(
        selectedTarget: ChannelConstants.targetYouTube,
        isUserEnabled: true,
        isAccessibilityGranted: false,
        isBridgeAvailable: true,
        isAccessActive: false,
        remainingAccess: Duration.zero,
      );
      expect(noA11y.isRestrictionEffective, isFalse);

      // 5. Not effective: bridge unavailable
      final noBridge = FocusState(
        selectedTarget: ChannelConstants.targetYouTube,
        isUserEnabled: true,
        isAccessibilityGranted: true,
        isBridgeAvailable: false,
        isAccessActive: false,
        remainingAccess: Duration.zero,
      );
      expect(noBridge.isRestrictionEffective, isFalse);
    });

    test('targetDisplayName maps known targets to readable titles', () {
      final youtube = FocusState.unavailable(selectedTarget: ChannelConstants.targetYouTube);
      expect(youtube.targetDisplayName, equals('YouTube'));

      final instagram = FocusState.unavailable(selectedTarget: ChannelConstants.targetInstagram);
      expect(instagram.targetDisplayName, equals('Instagram'));

      final tiktok = FocusState.unavailable(selectedTarget: ChannelConstants.targetTikTok);
      expect(tiktok.targetDisplayName, equals('TikTok'));

      final unknown = FocusState.unavailable(selectedTarget: 'com.other.app');
      expect(unknown.targetDisplayName, equals('com.other.app'));
    });

    test('fromNative constructs accurate state relative to reference time', () {
      final ref = DateTime(2026, 11, 21, 16, 0);
      final nativeStatus = NativeFocusStatus(
        targetPackage: ChannelConstants.targetInstagram,
        isGateEnabled: true,
        permissionStatus: const NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(unlockUntil: ref.add(const Duration(minutes: 5))),
      );

      final state = FocusState.fromNative(
        nativeStatus: nativeStatus,
        isBridgeAvailable: true,
        referenceTime: ref,
      );

      expect(state.selectedTarget, equals(ChannelConstants.targetInstagram));
      expect(state.isUserEnabled, isTrue);
      expect(state.isAccessibilityGranted, isTrue);
      expect(state.isBridgeAvailable, isTrue);
      expect(state.isAccessActive, isTrue);
      expect(state.remainingAccess, equals(const Duration(minutes: 5)));
      expect(state.isRestrictionEffective, isFalse, reason: 'Unlocked access active');
    });

    test('unavailable factory creates consistent offline state', () {
      final state = FocusState.unavailable();

      expect(state.selectedTarget, equals(ChannelConstants.defaultTarget));
      expect(state.isUserEnabled, isFalse);
      expect(state.isAccessibilityGranted, isFalse);
      expect(state.isBridgeAvailable, isFalse);
      expect(state.isAccessActive, isFalse);
      expect(state.isRestrictionEffective, isFalse);
      expect(state.unlockUntil, isNull);
    });

    test('implements value equality and toMap', () {
      final a = FocusState.unavailable();
      final b = FocusState.unavailable();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final map = a.toMap();
      expect(map['selectedTarget'], equals(ChannelConstants.defaultTarget));
      expect(map['isUserEnabled'], isFalse);
      expect(map['isBridgeAvailable'], isFalse);
    });
  });
}
