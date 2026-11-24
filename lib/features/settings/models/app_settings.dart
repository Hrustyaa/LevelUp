import 'package:flutter/foundation.dart';

import '../../../core/constants/channel_constants.dart';
import '../../../core/errors/settings_exceptions.dart';

/// Immutable application-level settings and user preferences for LevelUp.
@immutable
class AppSettings {
  /// Standard MVP reward duration fixed at exactly 300 seconds (5 minutes).
  static const int fixedUnlockDurationSeconds = 300;

  /// Default target application package selected for restriction.
  /// Must be one of [ChannelConstants.allowedTargets].
  final String defaultTargetPackage;

  /// Access grant reward duration in seconds.
  ///
  /// For MVP, this duration is strictly fixed at 300 seconds (5 minutes) across
  /// the Challenge Engine, Access Engine, and Android native gate.
  /// This field is reserved for future configurable challenge tiers and cannot
  /// be adjusted in MVP.
  final int defaultUnlockDurationSeconds;

  /// Stored user preference reserved for future configurable emergency prompts.
  ///
  /// Invariant: Under no circumstances can this preference disable the user's
  /// ability to leave or voluntarily turn off Focus (safety invariant).
  final bool emergencyPauseAllowed;

  /// Whether audio and haptic feedback triggers during pose repetitions and countdowns.
  ///
  /// Stored user preference reserved for upcoming audio/haptic modules.
  final bool soundFeedbackEnabled;

  /// Whether diagnostic events are logged to the Developer Lab buffer.
  ///
  /// Actively consumed by Developer Lab diagnostics.
  final bool diagnosticLoggingEnabled;

  const AppSettings({
    required this.defaultTargetPackage,
    this.defaultUnlockDurationSeconds = fixedUnlockDurationSeconds,
    required this.emergencyPauseAllowed,
    required this.soundFeedbackEnabled,
    required this.diagnosticLoggingEnabled,
  });

  /// Factory creating deterministic standard defaults.
  factory AppSettings.defaults() {
    return const AppSettings(
      defaultTargetPackage: ChannelConstants.targetYouTube,
      defaultUnlockDurationSeconds: fixedUnlockDurationSeconds,
      emergencyPauseAllowed: true,
      soundFeedbackEnabled: true,
      diagnosticLoggingEnabled: true,
    );
  }

  /// Validates settings values against domain invariants.
  /// Throws [InvalidSettingsException] if any property is invalid.
  void validate() {
    if (!ChannelConstants.allowedTargets.contains(defaultTargetPackage)) {
      throw InvalidSettingsException(
        'Target package "$defaultTargetPackage" is not in allowed target set: ${ChannelConstants.allowedTargets}',
        property: 'defaultTargetPackage',
        rejectedValue: defaultTargetPackage,
      );
    }

    // Invariant: MVP unlock duration is strictly fixed at 300 seconds.
    if (defaultUnlockDurationSeconds != fixedUnlockDurationSeconds) {
      throw InvalidSettingsException(
        'Configurable unlock duration is not supported in MVP; duration is strictly fixed at $fixedUnlockDurationSeconds seconds (5 minutes). Received: $defaultUnlockDurationSeconds',
        property: 'defaultUnlockDurationSeconds',
        rejectedValue: defaultUnlockDurationSeconds,
      );
    }
  }

  /// True if all settings strictly satisfy domain invariants.
  bool get isValid {
    try {
      validate();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates a copy with optionally updated fields.
  AppSettings copyWith({
    String? defaultTargetPackage,
    int? defaultUnlockDurationSeconds,
    bool? emergencyPauseAllowed,
    bool? soundFeedbackEnabled,
    bool? diagnosticLoggingEnabled,
  }) {
    return AppSettings(
      defaultTargetPackage: defaultTargetPackage ?? this.defaultTargetPackage,
      defaultUnlockDurationSeconds:
          defaultUnlockDurationSeconds ?? this.defaultUnlockDurationSeconds,
      emergencyPauseAllowed: emergencyPauseAllowed ?? this.emergencyPauseAllowed,
      soundFeedbackEnabled: soundFeedbackEnabled ?? this.soundFeedbackEnabled,
      diagnosticLoggingEnabled:
          diagnosticLoggingEnabled ?? this.diagnosticLoggingEnabled,
    );
  }

  /// Deserializes settings from a JSON-compatible map with graceful fallback to defaults.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final rawTarget = json['default_target_package'] as String?;
    final target = (rawTarget != null && ChannelConstants.allowedTargets.contains(rawTarget))
        ? rawTarget
        : ChannelConstants.targetYouTube;

    // Invariant: Duration is fixed at 300 seconds for MVP
    const duration = fixedUnlockDurationSeconds;

    return AppSettings(
      defaultTargetPackage: target,
      defaultUnlockDurationSeconds: duration,
      emergencyPauseAllowed: json['emergency_pause_allowed'] as bool? ?? true,
      soundFeedbackEnabled: json['sound_feedback_enabled'] as bool? ?? true,
      diagnosticLoggingEnabled: json['diagnostic_logging_enabled'] as bool? ?? true,
    );
  }

  /// Serializes settings to a JSON-compatible map for SQLite key-value persistence.
  Map<String, dynamic> toJson() {
    return {
      'default_target_package': defaultTargetPackage,
      'default_unlock_duration_seconds': defaultUnlockDurationSeconds,
      'emergency_pause_allowed': emergencyPauseAllowed,
      'sound_feedback_enabled': soundFeedbackEnabled,
      'diagnostic_logging_enabled': diagnosticLoggingEnabled,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          defaultTargetPackage == other.defaultTargetPackage &&
          defaultUnlockDurationSeconds == other.defaultUnlockDurationSeconds &&
          emergencyPauseAllowed == other.emergencyPauseAllowed &&
          soundFeedbackEnabled == other.soundFeedbackEnabled &&
          diagnosticLoggingEnabled == other.diagnosticLoggingEnabled;

  @override
  int get hashCode => Object.hash(
        defaultTargetPackage,
        defaultUnlockDurationSeconds,
        emergencyPauseAllowed,
        soundFeedbackEnabled,
        diagnosticLoggingEnabled,
      );

  @override
  String toString() =>
      'AppSettings(target: $defaultTargetPackage, duration: ${defaultUnlockDurationSeconds}s, '
      'emergencyPause: $emergencyPauseAllowed, sound: $soundFeedbackEnabled, diagLogs: $diagnosticLoggingEnabled)';
}
