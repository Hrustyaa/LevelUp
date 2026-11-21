/// Status outcome of an application access grant request.
enum AccessGrantStatus {
  /// Temporary access was successfully authorized and confirmed by the native layer.
  granted,

  /// Access was already granted and active for this completed session (idempotent duplicate).
  alreadyActive,

  /// Preconditions failed (e.g. wrong target, missing permission, focus disabled).
  rejected,

  /// Platform or IPC failure during the native grantAccess invocation.
  failed;

  /// True when access was successfully granted or recognized as already active.
  bool get isSuccessful => this == granted || this == alreadyActive;
}
