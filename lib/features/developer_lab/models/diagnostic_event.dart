import 'package:flutter/foundation.dart';

/// Severity level for developer diagnostic log events.
enum DevLogLevel {
  info,
  warning,
  error,
  success,
}

/// Backend module identifier emitting a diagnostic event.
enum BackendModuleId {
  nativeBridge('Native Bridge'),
  focusEngine('Focus Engine'),
  challengeEngine('Challenge Engine'),
  poseEngine('Pose Engine'),
  sessionManager('Session Manager'),
  accessEngine('Access Engine'),
  localDatabase('Local Database'),
  coordinator('Coordinator'),
  developerLab('Developer Lab');

  final String title;
  const BackendModuleId(this.title);
}

/// Immutable record of an event in the Developer Lab diagnostic stream.
@immutable
class DiagnosticEvent {
  final DateTime timestamp;
  final BackendModuleId module;
  final DevLogLevel level;
  final String message;
  final String? details;
  final String? sessionId;
  final String? category;

  DiagnosticEvent({
    DateTime? timestamp,
    required this.module,
    this.level = DevLogLevel.info,
    required this.message,
    this.details,
    this.sessionId,
    this.category,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Formats the event for plain text copy / export.
  String toLogString() {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';
    final levelStr = level.name.toUpperCase().padRight(7);
    final moduleStr = module.title.padRight(16);
    final catStr = category != null ? '[$category] ' : '';
    final sessionStr = sessionId != null ? ' (sid: $sessionId)' : '';
    final detailStr = details != null ? ' | $details' : '';
    return '[$timeStr] [$levelStr] [$moduleStr] $catStr$message$sessionStr$detailStr';
  }

  @override
  String toString() => toLogString();
}
