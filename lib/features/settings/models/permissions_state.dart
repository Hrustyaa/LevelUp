import 'package:flutter/foundation.dart';

import 'camera_permission_status.dart';

/// Immutable snapshot of hardware and OS permissions required for LevelUp operation.
@immutable
class PermissionsState {
  /// Whether Android Accessibility permission is granted in system settings.
  final bool isAccessibilityGranted;

  /// Authoritative status of the device camera permission.
  final CameraPermissionStatus cameraStatus;

  /// Timestamp when permissions were last queried or refreshed.
  final DateTime lastChecked;

  const PermissionsState({
    required this.isAccessibilityGranted,
    required this.cameraStatus,
    required this.lastChecked,
  });

  /// Initial state prior to first verification.
  factory PermissionsState.initial() {
    return PermissionsState(
      isAccessibilityGranted: false,
      cameraStatus: CameraPermissionStatus.unknown,
      lastChecked: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// True if camera permission is confirmed granted.
  bool get isCameraGranted => cameraStatus == CameraPermissionStatus.granted;

  /// True if both Accessibility and Camera permissions are granted.
  bool get isReadyForChallenges => isAccessibilityGranted && isCameraGranted;

  /// True if at least one required permission is missing or denied.
  bool get hasAnyMissingPermission => !isReadyForChallenges;

  /// True if camera permission was denied and requires user navigation to OS settings.
  bool get isCameraPermanentlyDenied =>
      cameraStatus == CameraPermissionStatus.permanentlyDenied;

  PermissionsState copyWith({
    bool? isAccessibilityGranted,
    CameraPermissionStatus? cameraStatus,
    DateTime? lastChecked,
  }) {
    return PermissionsState(
      isAccessibilityGranted:
          isAccessibilityGranted ?? this.isAccessibilityGranted,
      cameraStatus: cameraStatus ?? this.cameraStatus,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PermissionsState &&
          runtimeType == other.runtimeType &&
          isAccessibilityGranted == other.isAccessibilityGranted &&
          cameraStatus == other.cameraStatus &&
          lastChecked == other.lastChecked;

  @override
  int get hashCode => Object.hash(
        isAccessibilityGranted,
        cameraStatus,
        lastChecked,
      );

  @override
  String toString() =>
      'PermissionsState(a11y: $isAccessibilityGranted, camera: ${cameraStatus.label}, checked: $lastChecked)';
}
