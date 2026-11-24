/// Authoritative status of the Android Camera permission for LevelUp pose detection.
enum CameraPermissionStatus {
  /// Camera is accessible and usable for pose tracking.
  granted('Granted'),

  /// User denied camera permission or permission has not been requested yet.
  denied('Denied'),

  /// Permission denied with "Don't ask again" or blocked by OS settings.
  permanentlyDenied('Permanently Denied'),

  /// Camera access is restricted by device policy or parental controls.
  restricted('Restricted'),

  /// Status could not be determined or platform check is pending.
  unknown('Unknown');

  final String label;
  const CameraPermissionStatus(this.label);

  bool get isGranted => this == CameraPermissionStatus.granted;
}
