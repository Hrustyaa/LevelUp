/// Explicit lifecycle states for an Android application access attempt.
///
/// Designed to provide crash-safe tracking of platform channel grant requests
/// without assuming that an unconfirmed Future definitely failed on native.
enum AccessAttemptState {
  /// Attempt has been journaled immediately prior to calling native grantAccess.
  prepared,

  /// Native grantAccess returned an authoritative unlock expiration timestamp.
  confirmed,

  /// Platform channel invocation threw an exception or timed out; native state
  /// might or might not have updated. Cannot be safely auto-retried.
  uncertain,

  /// Request was rejected prior to native invocation due to precondition failure.
  definitivelyRejected;

  /// Returns true if this state is terminal and represents confirmed active access.
  bool get isConfirmed => this == confirmed;

  /// Returns true if this state requires reconciliation or user confirmation before retry.
  bool get requiresReconciliation => this == prepared || this == uncertain;

  /// Returns true if this state definitely did NOT grant native access.
  bool get isDefinitivelyRejected => this == definitivelyRejected;
}
