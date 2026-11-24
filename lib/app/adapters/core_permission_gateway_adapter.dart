import '../../data/levelup_permissions.dart';
import '../../features/settings/application/camera_permission_checker.dart';
import '../../features/settings/application/settings_service.dart';
import '../../features/settings/models/camera_permission_status.dart';
import '../../services/native_bridge.dart';

/// Production adapter implementing [LevelUpPermissionGateway] using real Core services.
///
/// Binds UI permission screens to [ISettingsService], [INativeBridge], and [ICameraPermissionChecker].
/// Honestly reports unsupported optional capabilities (Usage, Notifications) as [PermissionState.unavailable],
/// never pretending they are granted or supported by the native gate.
class CorePermissionGatewayAdapter implements LevelUpPermissionGateway {
  final ISettingsService _settingsService;
  final INativeBridge _nativeBridge;
  final ICameraPermissionChecker _cameraChecker;

  CorePermissionGatewayAdapter({
    required ISettingsService settingsService,
    required INativeBridge nativeBridge,
    ICameraPermissionChecker? cameraChecker,
  })  : _settingsService = settingsService,
        _nativeBridge = nativeBridge,
        _cameraChecker = cameraChecker ??
            DefaultCameraPermissionChecker(nativeBridge: nativeBridge);

  @override
  Future<Map<LevelUpPermission, PermissionState>> read() async {
    final settingsState = await _settingsService.refresh();
    final cameraStatus = await _cameraChecker.checkCameraPermission();

    return {
      LevelUpPermission.accessibility: settingsState.isAccessibilityGranted
          ? PermissionState.granted
          : PermissionState.denied,
      LevelUpPermission.camera: switch (cameraStatus) {
        CameraPermissionStatus.granted => PermissionState.granted,
        CameraPermissionStatus.permanentlyDenied => PermissionState.unavailable,
        CameraPermissionStatus.unknown => PermissionState.unknown,
        CameraPermissionStatus.denied ||
        CameraPermissionStatus.restricted => PermissionState.denied,
      },
      // Unsupported by native gate: honestly reported as unavailable, never fake-granted
      LevelUpPermission.usage: PermissionState.unavailable,
      LevelUpPermission.notifications: PermissionState.unavailable,
    };
  }

  @override
  Future<void> request(LevelUpPermission permission) async {
    switch (permission) {
      case LevelUpPermission.accessibility:
        await _nativeBridge.openAccessibilitySettings();
      case LevelUpPermission.camera:
        await _cameraChecker.requestCameraPermission();
      case LevelUpPermission.usage:
      case LevelUpPermission.notifications:
        // Do not request or pretend to grant unsupported permissions
        break;
    }
  }

  @override
  Future<void> openAppSettings() async {
    await _nativeBridge.openAppSettings();
  }

  /// Dispatches system settings intent for the requested permission.
  Future<void> openPermissionSettings(LevelUpPermission permission) async {
    switch (permission) {
      case LevelUpPermission.accessibility:
        await _nativeBridge.openAccessibilitySettings();
      case LevelUpPermission.camera:
        await _nativeBridge.openAppSettings();
      case LevelUpPermission.usage:
      case LevelUpPermission.notifications:
        break;
    }
  }
}
