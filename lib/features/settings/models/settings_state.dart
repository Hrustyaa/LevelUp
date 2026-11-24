import 'package:flutter/foundation.dart';

import 'app_settings.dart';
import 'camera_permission_status.dart';
import 'permissions_state.dart';

/// Combined, immutable state of application settings, permissions, and native synchronization.
@immutable
class SettingsState {
  /// User-configurable application preferences.
  final AppSettings settings;

  /// Hardware and OS permissions snapshot.
  final PermissionsState permissions;

  /// Package name currently restricted by native gate (authoritative from Focus Engine).
  final String activeTargetPackage;

  /// Whether voluntary Focus restriction is currently active in native gate.
  final bool isFocusEnabled;

  /// True when an asynchronous load or refresh operation is in flight.
  final bool isLoading;

  /// Error message from the last failed operation, if any.
  final String? errorMessage;

  const SettingsState({
    required this.settings,
    required this.permissions,
    required this.activeTargetPackage,
    required this.isFocusEnabled,
    this.isLoading = false,
    this.errorMessage,
  });

  /// Factory creating uninitialized baseline state.
  factory SettingsState.initial() {
    return SettingsState(
      settings: AppSettings.defaults(),
      permissions: PermissionsState.initial(),
      activeTargetPackage: AppSettings.defaults().defaultTargetPackage,
      isFocusEnabled: false,
      isLoading: true,
      errorMessage: null,
    );
  }

  /// Convenience getters delegating to permissions state.
  bool get isAccessibilityGranted => permissions.isAccessibilityGranted;
  bool get isCameraGranted => permissions.isCameraGranted;
  CameraPermissionStatus get cameraStatus => permissions.cameraStatus;
  bool get isReadyForChallenges => permissions.isReadyForChallenges;

  /// True if voluntary Focus restriction can be activated.
  /// Precondition: Accessibility permission must be granted.
  bool get canEnableFocus => isAccessibilityGranted;

  /// True if state is initialized and free of errors.
  bool get isReady => !isLoading && errorMessage == null;

  SettingsState copyWith({
    AppSettings? settings,
    PermissionsState? permissions,
    String? activeTargetPackage,
    bool? isFocusEnabled,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      permissions: permissions ?? this.permissions,
      activeTargetPackage: activeTargetPackage ?? this.activeTargetPackage,
      isFocusEnabled: isFocusEnabled ?? this.isFocusEnabled,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsState &&
          runtimeType == other.runtimeType &&
          settings == other.settings &&
          permissions == other.permissions &&
          activeTargetPackage == other.activeTargetPackage &&
          isFocusEnabled == other.isFocusEnabled &&
          isLoading == other.isLoading &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        settings,
        permissions,
        activeTargetPackage,
        isFocusEnabled,
        isLoading,
        errorMessage,
      );

  @override
  String toString() =>
      'SettingsState(target: $activeTargetPackage, enabled: $isFocusEnabled, '
      'loading: $isLoading, error: $errorMessage, permissions: $permissions)';
}
