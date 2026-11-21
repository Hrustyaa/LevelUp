import 'package:flutter/foundation.dart';
import '../core/constants/channel_constants.dart';
import 'native_access_status.dart';
import 'native_permission_status.dart';

/// Complete live state of the Android native restriction gate.
@immutable
class NativeFocusStatus {
  /// The application package currently targeted for restriction.
  final String targetPackage;

  /// Whether the user has voluntarily enabled the restriction gate.
  final bool isGateEnabled;

  /// The Android system permission and service status.
  final NativePermissionStatus permissionStatus;

  /// The temporary unlocked access status.
  final NativeAccessStatus accessStatus;

  const NativeFocusStatus({
    required this.targetPackage,
    required this.isGateEnabled,
    required this.permissionStatus,
    required this.accessStatus,
  });

  /// Convenient helper to check whether Accessibility Service is enabled in system settings.
  bool get isAccessibilityGranted => permissionStatus.isAccessibilityGranted;

  /// Alias for backward compatibility with existing Flutter code.
  bool get isServiceEnabled => permissionStatus.isAccessibilityGranted;

  /// Expiration timestamp of temporary access, if active.
  DateTime? get unlockUntil => accessStatus.unlockUntil;

  /// Convenient helper to check whether temporary access is currently active.
  bool get isAccessActive => accessStatus.isAccessActive();

  /// Remaining access duration.
  Duration get remainingAccess => accessStatus.remainingAccess();

  /// Parse safely from native map returned by `getState`.
  /// Gracefully handles nulls, missing keys, and unexpected field types without crashing.
  factory NativeFocusStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const NativeFocusStatus(
        targetPackage: ChannelConstants.defaultTarget,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      );
    }

    final rawTarget = map[ChannelConstants.keyTarget];
    final target = (rawTarget is String && rawTarget.isNotEmpty)
        ? rawTarget
        : ChannelConstants.defaultTarget;

    final isGateEnabled = map[ChannelConstants.keyEnabled] == true;

    final serviceEnabledRaw = map[ChannelConstants.keyServiceEnabled];
    final permissionStatus = NativePermissionStatus.fromRaw(serviceEnabledRaw);

    final rawUnlockUntil = map[ChannelConstants.keyUnlockUntil];
    final accessStatus = NativeAccessStatus.fromEpochMs(rawUnlockUntil);

    return NativeFocusStatus(
      targetPackage: target,
      isGateEnabled: isGateEnabled,
      permissionStatus: permissionStatus,
      accessStatus: accessStatus,
    );
  }

  /// Serializes back to a Map representation matching the native contract format.
  Map<String, dynamic> toMap() {
    return {
      ChannelConstants.keyTarget: targetPackage,
      ChannelConstants.keyEnabled: isGateEnabled,
      ChannelConstants.keyServiceEnabled: isAccessibilityGranted,
      ChannelConstants.keyUnlockUntil: unlockUntil?.millisecondsSinceEpoch ?? 0,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeFocusStatus &&
          runtimeType == other.runtimeType &&
          targetPackage == other.targetPackage &&
          isGateEnabled == other.isGateEnabled &&
          permissionStatus == other.permissionStatus &&
          accessStatus == other.accessStatus;

  @override
  int get hashCode => Object.hash(
        targetPackage,
        isGateEnabled,
        permissionStatus,
        accessStatus,
      );

  @override
  String toString() =>
      'NativeFocusStatus(target: $targetPackage, gateEnabled: $isGateEnabled, permission: $permissionStatus, access: $accessStatus)';
}
