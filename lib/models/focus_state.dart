import 'package:flutter/foundation.dart';

import '../core/constants/channel_constants.dart';
import 'native_focus_status.dart';

/// Complete application-level snapshot of the LevelUp Focus Engine state.
///
/// Unambiguously distinguishes between:
/// 1. User-enabled Focus preference ([isUserEnabled]).
/// 2. Accessibility permission granted in system settings ([isAccessibilityGranted]).
/// 3. Native platform bridge availability ([isBridgeAvailable]).
/// 4. Currently selected target application ([selectedTarget]).
/// 5. Temporary access active or expired ([isAccessActive], [remainingAccess], [unlockUntil]).
/// 6. Whether restriction is currently effective ([isRestrictionEffective]).
@immutable
class FocusState {
  /// The package identifier of the single currently restricted app.
  /// (e.g. 'com.google.android.youtube')
  final String selectedTarget;

  /// Whether the user has voluntarily enabled the Focus restriction in LevelUp.
  final bool isUserEnabled;

  /// Whether the Android Accessibility Service permission is granted in OS settings.
  ///
  /// Note: Permission granted does not guarantee the OS has not killed or paused
  /// the service. Only what Android reports via AccessibilityManager is reflected here.
  final bool isAccessibilityGranted;

  /// Whether the Android native bridge is reachable and responsive.
  final bool isBridgeAvailable;

  /// Expiration timestamp of temporary unlocked access, or null if expired/locked.
  final DateTime? unlockUntil;

  /// Whether temporary unlocked access is currently active according to calendar time.
  final bool isAccessActive;

  /// Remaining duration of temporary access (Duration.zero if locked or expired).
  final Duration remainingAccess;

  /// The underlying raw native status snapshot, if available.
  final NativeFocusStatus? rawNativeStatus;

  const FocusState({
    required this.selectedTarget,
    required this.isUserEnabled,
    required this.isAccessibilityGranted,
    required this.isBridgeAvailable,
    this.unlockUntil,
    required this.isAccessActive,
    required this.remainingAccess,
    this.rawNativeStatus,
  });

  /// True when restriction is actively blocking target app launches:
  /// - Native bridge is operational.
  /// - User has enabled the gate.
  /// - Accessibility permission is granted in Android system settings.
  /// - Temporary access is NOT currently active.
  bool get isRestrictionEffective =>
      isBridgeAvailable &&
      isUserEnabled &&
      isAccessibilityGranted &&
      !isAccessActive;

  /// User-friendly display name of the selected target app (e.g. "YouTube").
  String get targetDisplayName =>
      ChannelConstants.targetDisplayNames[selectedTarget] ?? selectedTarget;

  /// Constructs [FocusState] from verified [NativeFocusStatus] and bridge status.
  factory FocusState.fromNative({
    required NativeFocusStatus nativeStatus,
    required bool isBridgeAvailable,
    DateTime? referenceTime,
  }) {
    final now = referenceTime ?? DateTime.now();
    final isAccessActive = nativeStatus.accessStatus.isAccessActive(now);
    final remainingAccess = nativeStatus.accessStatus.remainingAccess(now);

    return FocusState(
      selectedTarget: nativeStatus.targetPackage,
      isUserEnabled: nativeStatus.isGateEnabled,
      isAccessibilityGranted: nativeStatus.isAccessibilityGranted,
      isBridgeAvailable: isBridgeAvailable,
      unlockUntil: nativeStatus.unlockUntil,
      isAccessActive: isAccessActive,
      remainingAccess: remainingAccess,
      rawNativeStatus: nativeStatus,
    );
  }

  /// Fallback state when the native bridge cannot be reached.
  factory FocusState.unavailable({
    String selectedTarget = ChannelConstants.defaultTarget,
  }) {
    return FocusState(
      selectedTarget: selectedTarget,
      isUserEnabled: false,
      isAccessibilityGranted: false,
      isBridgeAvailable: false,
      unlockUntil: null,
      isAccessActive: false,
      remainingAccess: Duration.zero,
      rawNativeStatus: null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'selectedTarget': selectedTarget,
      'isUserEnabled': isUserEnabled,
      'isAccessibilityGranted': isAccessibilityGranted,
      'isBridgeAvailable': isBridgeAvailable,
      'unlockUntil': unlockUntil?.millisecondsSinceEpoch,
      'isAccessActive': isAccessActive,
      'remainingAccessMs': remainingAccess.inMilliseconds,
      'isRestrictionEffective': isRestrictionEffective,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusState &&
          runtimeType == other.runtimeType &&
          selectedTarget == other.selectedTarget &&
          isUserEnabled == other.isUserEnabled &&
          isAccessibilityGranted == other.isAccessibilityGranted &&
          isBridgeAvailable == other.isBridgeAvailable &&
          unlockUntil == other.unlockUntil &&
          isAccessActive == other.isAccessActive &&
          remainingAccess == other.remainingAccess;

  @override
  int get hashCode => Object.hash(
        selectedTarget,
        isUserEnabled,
        isAccessibilityGranted,
        isBridgeAvailable,
        unlockUntil,
        isAccessActive,
        remainingAccess,
      );

  @override
  String toString() =>
      'FocusState(target: $selectedTarget, enabled: $isUserEnabled, a11y: $isAccessibilityGranted, bridge: $isBridgeAvailable, accessActive: $isAccessActive, effective: $isRestrictionEffective)';
}
