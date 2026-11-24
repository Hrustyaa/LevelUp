import 'package:camera/camera.dart';

import '../../../services/native_bridge.dart';
import '../models/camera_permission_status.dart';

/// Contract for checking and requesting device camera permissions.
abstract class ICameraPermissionChecker {
  /// Queries the current camera permission status safely without showing a prompt.
  Future<CameraPermissionStatus> checkCameraPermission();

  /// Requests camera permission from the operating system (triggered by explicit user action).
  Future<CameraPermissionStatus> requestCameraPermission();
}

/// Production implementation of [ICameraPermissionChecker] wrapping native Android check
/// and Flutter Camera plugin.
class DefaultCameraPermissionChecker implements ICameraPermissionChecker {
  final INativeBridge? _nativeBridge;
  final Future<List<CameraDescription>> Function()? _availableCameras;

  DefaultCameraPermissionChecker({
    INativeBridge? nativeBridge,
    Future<List<CameraDescription>> Function()? availableCamerasOverride,
  })  : _nativeBridge = nativeBridge,
        _availableCameras = availableCamerasOverride;

  @override
  Future<CameraPermissionStatus> checkCameraPermission() async {
    // 1. Authoritative runtime OS check via NativeBridge without prompting user
    if (_nativeBridge != null) {
      try {
        final raw = await _nativeBridge.checkCameraPermission();
        if (raw == 'granted') return CameraPermissionStatus.granted;
        if (raw == 'denied') return CameraPermissionStatus.denied;
        if (raw == 'permanentlyDenied') return CameraPermissionStatus.permanentlyDenied;
      } catch (_) {}
    }
    return CameraPermissionStatus.unknown;
  }

  @override
  Future<CameraPermissionStatus> requestCameraPermission() async {
    // User-triggered action: attempt hardware acquisition which triggers OS dialog if needed
    try {
      if (_availableCameras != null) {
        await _availableCameras();
      } else {
        await availableCameras();
      }
      return await checkCameraPermission();
    } on CameraException catch (e) {
      return _mapCameraException(e);
    } catch (_) {
      return CameraPermissionStatus.unknown;
    }
  }

  CameraPermissionStatus _mapCameraException(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return CameraPermissionStatus.denied;
      case 'CameraAccessDeniedWithoutPrompt':
        return CameraPermissionStatus.permanentlyDenied;
      case 'CameraAccessRestricted':
        return CameraPermissionStatus.restricted;
      default:
        return CameraPermissionStatus.unknown;
    }
  }
}

/// Mock implementation of [ICameraPermissionChecker] for deterministic testing and simulation.
class MockCameraPermissionChecker implements ICameraPermissionChecker {
  CameraPermissionStatus status;
  int checkCount = 0;
  int requestCount = 0;

  MockCameraPermissionChecker({
    this.status = CameraPermissionStatus.granted,
  });

  @override
  Future<CameraPermissionStatus> checkCameraPermission() async {
    checkCount++;
    return status;
  }

  @override
  Future<CameraPermissionStatus> requestCameraPermission() async {
    requestCount++;
    return status;
  }

  /// Simulates external permission revocation by the user in Android OS Settings.
  void revokePermission() {
    status = CameraPermissionStatus.denied;
  }

  /// Simulates user granting permission in Android OS Settings.
  void grantPermission() {
    status = CameraPermissionStatus.granted;
  }
}
