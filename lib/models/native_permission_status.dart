import 'package:flutter/foundation.dart';

/// Live snapshot of Android system permissions and service availability for LevelUp.
@immutable
class NativePermissionStatus {
  /// Whether the Android Accessibility Service (`LevelUpAccessibilityService`)
  /// is currently enabled in system accessibility settings.
  final bool isAccessibilityGranted;

  const NativePermissionStatus({
    required this.isAccessibilityGranted,
  });

  /// Factory constructor that safely parses raw dynamic values from native map.
  factory NativePermissionStatus.fromRaw(dynamic serviceEnabled) {
    return NativePermissionStatus(
      isAccessibilityGranted: serviceEnabled == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativePermissionStatus &&
          runtimeType == other.runtimeType &&
          isAccessibilityGranted == other.isAccessibilityGranted;

  @override
  int get hashCode => isAccessibilityGranted.hashCode;

  @override
  String toString() =>
      'NativePermissionStatus(isAccessibilityGranted: $isAccessibilityGranted)';
}
