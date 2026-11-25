/// Source labels stored in workout history. Only the live pose adapter can
/// supply the completion evidence required to write the verified source.
abstract final class PushUpVerification {
  static const experimentalSource = 'experimental_unverified';
  static const verifiedSource = 'camera_pushup_verified';
}
