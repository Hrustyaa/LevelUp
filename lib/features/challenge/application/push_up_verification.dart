import 'package:flutter/foundation.dart';

/// Enable the experiment with --dart-define=LEVELUP_TEST_PUSH_UP_UNLOCK=true
/// in a debug build. Promotion requires review of physical-device evidence.
abstract final class PushUpVerification {
  static const bool physicallyValidated = false;
  static const bool testUnlockEnabled =
      kDebugMode && bool.fromEnvironment('LEVELUP_TEST_PUSH_UP_UNLOCK');
  static const bool unlockEnabled = physicallyValidated || testUnlockEnabled;

  static const String experimentalSource = 'experimental_unverified';
  static const String verifiedSource = 'camera_pushup_verified';

  static bool canGrantAccess(String source) =>
      (testUnlockEnabled && source == experimentalSource) ||
      (physicallyValidated && source == verifiedSource);
}
