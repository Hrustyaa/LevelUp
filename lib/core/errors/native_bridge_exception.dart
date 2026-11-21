/// Base exception thrown when communication with the Android native layer fails.
class NativeBridgeException implements Exception {
  /// Human-readable description of the failure.
  final String message;

  /// Error code returned by platform channel or bridge layer.
  final String? code;

  /// Optional platform details associated with the error.
  final dynamic details;

  /// Underlying exception or error cause, if any.
  final Object? cause;

  const NativeBridgeException({
    required this.message,
    this.code,
    this.details,
    this.cause,
  });

  @override
  String toString() {
    final buffer = StringBuffer('NativeBridgeException');
    if (code != null) {
      buffer.write('[$code]');
    }
    buffer.write(': $message');
    if (details != null) {
      buffer.write(' (details: $details)');
    }
    return buffer.toString();
  }
}

/// Thrown when the target package is rejected by native validation (code: "TARGET").
class UnsupportedTargetPackageException extends NativeBridgeException {
  /// The rejected target package identifier.
  final String targetPackage;

  UnsupportedTargetPackageException(
    this.targetPackage, {
    String? message,
    super.details,
    super.cause,
  }) : super(
          code: 'TARGET',
          message: message ?? 'Unsupported target package: $targetPackage',
        );
}

/// Thrown when a method call is not implemented by the native platform handler
/// or when running on an unsupported platform (wraps [MissingPluginException]).
class NativeBridgeNotImplementedException extends NativeBridgeException {
  /// The method identifier that was not found or implemented.
  final String method;

  NativeBridgeNotImplementedException(
    this.method, {
    String? message,
    super.details,
    super.cause,
  }) : super(
          code: 'NOT_IMPLEMENTED',
          message: message ?? 'Method "$method" is not implemented on this platform',
        );
}

/// Thrown when the native response cannot be parsed or contains invalid data.
class MalformedNativeResponseException extends NativeBridgeException {
  MalformedNativeResponseException(
    String message, {
    super.details,
    super.cause,
  }) : super(
          code: 'MALFORMED_RESPONSE',
          message: message,
        );
}
