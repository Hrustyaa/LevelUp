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
  void info(
    BackendModuleId module,
    String message, [
    String? details,
    String? sessionId,
    String? category,
  ]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.info,
      message: message,
      details: details,
      sessionId: sessionId,
      category: category,
    ));
  }

  void success(
    BackendModuleId module,
    String message, [
    String? details,
    String? sessionId,
    String? category,
  ]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.success,
      message: message,
      details: details,
      sessionId: sessionId,
      category: category,
    ));
  }

  void warning(
    BackendModuleId module,
    String message, [
    String? details,
    String? sessionId,
    String? category,
  ]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.warning,
      message: message,
      details: details,
      sessionId: sessionId,
      category: category,
    ));
  }

  void error(
    BackendModuleId module,
    String message, [
    String? details,
    String? sessionId,
    String? category,
  ]) {
    log(DiagnosticEvent(
      module: module,
      level: DevLogLevel.error,
      message: message,
      details: details,
      sessionId: sessionId,
      category: category,
    ));
  }

  /// Returns filtered events based on module, severity, query or session ID.
  List<DiagnosticEvent> getFilteredEvents({
    BackendModuleId? module,
    DevLogLevel? level,
    String? query,
    String? sessionId,
  }) {
    return _events.where((e) {
      if (module != null && e.module != module) return false;
      if (level != null && e.level != level) return false;
      if (sessionId != null && e.sessionId != sessionId) return false;
      if (query != null && query.trim().isNotEmpty) {
        final q = query.toLowerCase();
        final matchMsg = e.message.toLowerCase().contains(q);
        final matchDetail = e.details?.toLowerCase().contains(q) ?? false;
        final matchModule = e.module.title.toLowerCase().contains(q);
        if (!matchMsg && !matchDetail && !matchModule) return false;
      }
      return true;
    }).toList();
  }

  /// Exports all currently buffered logs as a formatted single string with optional filters.
  String exportLogs({
    BackendModuleId? module,
    DevLogLevel? minLevel,
    String? sessionId,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('=== LevelUp Developer Lab Diagnostic Log ===');
    buffer.writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}');
    if (module != null) buffer.writeln('Filter Module: ${module.title}');
    if (sessionId != null) buffer.writeln('Filter Session: $sessionId');

    final eventsToExport = getFilteredEvents(
      module: module,
      level: minLevel,
      sessionId: sessionId,
    );

    buffer.writeln('Exported events: ${eventsToExport.length} (out of ${_events.length} total)');
    buffer.writeln('--------------------------------------------');
    for (final event in eventsToExport) {
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
