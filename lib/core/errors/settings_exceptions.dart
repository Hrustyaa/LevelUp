/// Exceptions thrown by Module 08 — Settings & Permissions Engine.
library;

/// Base exception for all settings-related errors.
class SettingsException implements Exception {
  final String message;
  final Object? cause;

  const SettingsException(this.message, {this.cause});

  @override
  String toString() => 'SettingsException: $message${cause != null ? " (cause: $cause)" : ""}';
}

/// Thrown when attempting to save settings that fail domain validation.
class InvalidSettingsException extends SettingsException {
  final String property;
  final dynamic rejectedValue;

  const InvalidSettingsException(
    super.message, {
    required this.property,
    required this.rejectedValue,
    super.cause,
  });

  @override
  String toString() =>
      'InvalidSettingsException on "$property" with value "$rejectedValue": $message';
}

/// Thrown when persistence operations fail (e.g. disk full, SQLite I/O error).
class SettingsPersistenceException extends SettingsException {
  const SettingsPersistenceException(super.message, {super.cause});
}

/// Thrown when permission prerequisites are missing or cannot be checked.
class PermissionException extends SettingsException {
  final String permissionName;

  const PermissionException(
    super.message, {
    required this.permissionName,
    super.cause,
  });

  @override
  String toString() => 'PermissionException ($permissionName): $message';
}
