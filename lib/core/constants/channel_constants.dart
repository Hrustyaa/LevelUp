/// Platform channel and method constants for Flutter <-> Kotlin communication.
abstract final class ChannelConstants {
  /// The single active MethodChannel identifier used by MainActivity.kt.
  static const String controlChannel = 'levelup_test/control';

  // Method Names
  static const String methodGetState = 'getState';
  static const String methodSetTarget = 'setTarget';
  static const String methodSetEnabled = 'setEnabled';
  static const String methodOpenAccessibilitySettings = 'openAccessibilitySettings';
  static const String methodOpenAppSettings = 'openAppSettings';
  static const String methodCheckCameraPermission = 'checkCameraPermission';
  static const String methodConsumeChallengeRequest = 'consumeChallengeRequest';
  static const String methodGrantAccess = 'grantAccess';
  static const String methodResetAccess = 'resetAccess';

  // Argument Keys
  static const String argTarget = 'target';
  static const String argEnabled = 'enabled';
  static const String argMinutes = 'minutes';

  // Return Map Keys for getState
  static const String keyTarget = 'target';
  static const String keyEnabled = 'enabled';
  static const String keyUnlockUntil = 'unlockUntil';
  static const String keyServiceEnabled = 'serviceEnabled';

  // Target Packages supported by Blocker v3
  static const String targetYouTube = 'com.google.android.youtube';
  static const String targetInstagram = 'com.instagram.android';
  static const String targetTikTok = 'com.zhiliaoapp.musically';

  /// Default package selected on initial install.
  static const String defaultTarget = targetYouTube;

  /// Complete set of packages supported by native gate.
  static const Set<String> allowedTargets = {
    targetYouTube,
    targetInstagram,
    targetTikTok,
  };

  /// User-friendly display names for allowed target packages.
  static const Map<String, String> targetDisplayNames = {
    targetYouTube: 'YouTube',
    targetInstagram: 'Instagram',
    targetTikTok: 'TikTok',
  };
}
