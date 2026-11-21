import 'package:flutter/foundation.dart';

import 'access_attempt_state.dart';

/// Immutable domain model representing a journaled application access grant attempt.
@immutable
class AccessAttemptRecord {
  /// Session identifier associated with the workout earning this access.
  final String sessionId;

  /// Targeted application package identifier.
  final String targetPackage;

  /// Granted access duration in seconds.
  final int durationSeconds;

  /// Current lifecycle state of the access attempt.
  final AccessAttemptState state;

  /// Timestamp when the attempt was first prepared/journaled.
  final DateTime attemptedAt;

  /// Timestamp when the native layer confirmed access (null until confirmed).
  final DateTime? confirmedAt;

  /// Authoritative expiration timestamp returned by native (null if not confirmed).
  final DateTime? unlockUntil;

  /// Failure explanation if state is [AccessAttemptState.uncertain] or [AccessAttemptState.definitivelyRejected].
  final String? failureReason;

  const AccessAttemptRecord({
    required this.sessionId,
    required this.targetPackage,
    required this.durationSeconds,
    required this.state,
    required this.attemptedAt,
    this.confirmedAt,
    this.unlockUntil,
    this.failureReason,
  });

  /// True when this attempt has been confirmed by the native layer.
  bool get isConfirmed => state.isConfirmed;

  /// True when this attempt requires state reconciliation before any retry.
  bool get requiresReconciliation => state.requiresReconciliation;

  /// True when this attempt was definitively rejected prior to native execution.
  bool get isDefinitivelyRejected => state.isDefinitivelyRejected;

  /// Factory constructor parsing from SQLite row map.
  factory AccessAttemptRecord.fromMap(Map<String, dynamic> map) {
    return AccessAttemptRecord(
      sessionId: map['session_id'] as String,
      targetPackage: map['target_package'] as String,
      durationSeconds: map['duration_seconds'] as int,
      state: AccessAttemptState.values.byName(map['state'] as String),
      attemptedAt: DateTime.fromMillisecondsSinceEpoch(
        map['attempted_at'] as int,
        isUtc: true,
      ),
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['confirmed_at'] as int,
              isUtc: true,
            )
          : null,
      unlockUntil: map['unlock_until'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['unlock_until'] as int,
              isUtc: true,
            )
          : null,
      failureReason: map['failure_reason'] as String?,
    );
  }

  /// Serializes into SQLite column map.
  Map<String, dynamic> toMap() {
    return {
      'session_id': sessionId,
      'target_package': targetPackage,
      'duration_seconds': durationSeconds,
      'state': state.name,
      'attempted_at': attemptedAt.toUtc().millisecondsSinceEpoch,
      'confirmed_at': confirmedAt?.toUtc().millisecondsSinceEpoch,
      'unlock_until': unlockUntil?.toUtc().millisecondsSinceEpoch,
      'failure_reason': failureReason,
    };
  }

  /// Creates a copy with the provided fields replaced.
  AccessAttemptRecord copyWith({
    AccessAttemptState? state,
    DateTime? confirmedAt,
    DateTime? unlockUntil,
    String? failureReason,
  }) {
    return AccessAttemptRecord(
      sessionId: sessionId,
      targetPackage: targetPackage,
      durationSeconds: durationSeconds,
      state: state ?? this.state,
      attemptedAt: attemptedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      unlockUntil: unlockUntil ?? this.unlockUntil,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccessAttemptRecord &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          targetPackage == other.targetPackage &&
          durationSeconds == other.durationSeconds &&
          state == other.state &&
          attemptedAt == other.attemptedAt &&
          confirmedAt == other.confirmedAt &&
          unlockUntil == other.unlockUntil &&
          failureReason == other.failureReason;

  @override
  int get hashCode => Object.hash(
        sessionId,
        targetPackage,
        durationSeconds,
        state,
        attemptedAt,
        confirmedAt,
        unlockUntil,
        failureReason,
      );

  @override
  String toString() =>
      'AccessAttemptRecord(session: $sessionId, target: $targetPackage, state: ${state.name}, unlockUntil: $unlockUntil)';
}
