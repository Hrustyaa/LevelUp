import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/diagnostic_event.dart';

/// Thread-safe in-memory ring-buffer for developer diagnostic log events.
class DevLabLogService extends ChangeNotifier {
  final int maxEvents;
  final List<DiagnosticEvent> _events = [];
  final StreamController<DiagnosticEvent> _eventStream =
      StreamController<DiagnosticEvent>.broadcast();

  DevLabLogService({this.maxEvents = 200});

  /// All buffered events (newest last).
  List<DiagnosticEvent> get events => List.unmodifiable(_events);

  /// Reactive stream of newly emitted diagnostic events.
  Stream<DiagnosticEvent> get eventStream => _eventStream.stream;

  /// Records a new diagnostic event into the buffer.
  void log(DiagnosticEvent event) {
    if (_events.length >= maxEvents) {
      _events.removeAt(0);
    }
    _events.add(event);

    if (!_eventStream.isClosed) {
      _eventStream.add(event);
    }
    notifyListeners();
  }

  /// Convenience logging methods
  void info(BackendModuleId module, String message, [String? details]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.info,
      message: message,
      details: details,
    ));
  }

  void success(BackendModuleId module, String message, [String? details]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.success,
      message: message,
      details: details,
    ));
  }

  void warning(BackendModuleId module, String message, [String? details]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.warning,
      message: message,
      details: details,
    ));
  }

  void error(BackendModuleId module, String message, [String? details]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.error,
      message: message,
      details: details,
    ));
  }

  /// Exports all currently buffered logs as a formatted single string.
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== LevelUp Developer Lab Diagnostic Log ===');
    buffer.writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('Total events: ${_events.length}');
    buffer.writeln('--------------------------------------------');
    for (final event in _events) {
      buffer.writeln(event.toLogString());
    }
    buffer.writeln('=== End of Log ===');
    return buffer.toString();
  }

  /// Clears in-memory log buffer.
  void clear() {
    _events.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _eventStream.close();
    super.dispose();
  }
}
