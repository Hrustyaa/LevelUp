import 'native_bridge_exception.dart';

/// Base exception for high-level Focus Engine errors.
class FocusEngineException implements Exception {
  final String message;
  final String? code;
  final Object? cause;

  const FocusEngineException({
    required this.message,
    this.code,
    this.cause,
  });

  @override
  String toString() {
    if (code != null) {
      return 'FocusEngineException[$code]: $message';
    }
    return 'FocusEngineException: $message';
  }
}

/// Thrown when enabling Focus is attempted but the Android Accessibility Service
/// permission has not been granted by the user.
class AccessibilityPermissionRequiredException extends FocusEngineException {
  const AccessibilityPermissionRequiredException({
    super.message =
        'Android Accessibility permission is required before voluntary Focus restriction can be activated.',
    super.cause,
  }) : super(code: 'PERMISSION_REQUIRED');
}

/// Thrown when the native platform bridge is unavailable, unresponsive, or running
/// on an unsupported platform.
class NativeBridgeUnavailableException extends FocusEngineException {
  const NativeBridgeUnavailableException({
    super.message = 'The native platform bridge is unavailable or not responding.',
    super.cause,
  }) : super(code: 'BRIDGE_UNAVAILABLE');
}

/// Thrown when an unsupported target package is supplied to the Focus Engine.
class UnsupportedTargetException extends FocusEngineException {
  final String packageName;

  const UnsupportedTargetException(
    this.packageName, {
    String? message,
    super.cause,
  }) : super(
          code: 'UNSUPPORTED_TARGET',
          message: message ??
              'Package "$packageName" is not supported by LevelUp Blocker v3.',
        );

  factory UnsupportedTargetException.fromBridge(
    UnsupportedTargetPackageException bridgeException,
  ) {
    return UnsupportedTargetException(
      bridgeException.targetPackage,
      message: bridgeException.message,
      cause: bridgeException,
    );
  }
}

/// Thrown when actual native state cannot be refreshed or does not match expected state.
class FocusStateSyncException extends FocusEngineException {
  const FocusStateSyncException({
    required super.message,
    super.cause,
  }) : super(code: 'SYNC_FAILED');
}
