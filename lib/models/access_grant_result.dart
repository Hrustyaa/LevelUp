import 'package:flutter/foundation.dart';

import 'access_grant_status.dart';

/// Immutable result record detailing the outcome of an application access grant.
@immutable
class AccessGrantResult {
  /// Session identifier associated with the grant.
  final String sessionId;

  /// Targeted application package.
  final String targetPackage;

  /// Grant status outcome.
  final AccessGrantStatus status;

  /// Authoritative expiration timestamp confirmed by the Android native layer.
  final DateTime? unlockUntil;

  /// Timestamp when the grant operation occurred.
  final DateTime grantedAt;

  /// Optional error or rejection explanation if status is rejected or failed.
  final String? rejectionReason;

  const AccessGrantResult({
    required this.sessionId,
    required this.targetPackage,
    required this.status,
    this.unlockUntil,
    required this.grantedAt,
    this.rejectionReason,
  });

  /// True when access was successfully granted or was already active.
  bool get isSuccessful => status.isSuccessful;

  /// Whether the unlocked access is currently active relative to [now].
  bool isAccessActive([DateTime? now]) {
    final expiry = unlockUntil;
    if (expiry == null) return false;
    return expiry.isAfter(now ?? DateTime.now());
  }

  /// Remaining duration of unlocked access relative to [now].
  Duration remainingDuration([DateTime? now]) {
    if (!isAccessActive(now)) return Duration.zero;
    return unlockUntil!.difference(now ?? DateTime.now());
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'targetPackage': targetPackage,
      'status': status.name,
      'unlockUntil': unlockUntil?.toIso8601String(),
      'grantedAt': grantedAt.toIso8601String(),
      'rejectionReason': rejectionReason,
      'isSuccessful': isSuccessful,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccessGrantResult &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          targetPackage == other.targetPackage &&
          status == other.status &&
          unlockUntil == other.unlockUntil &&
          grantedAt == other.grantedAt &&
          rejectionReason == other.rejectionReason;

  @override
  int get hashCode => Object.hash(
        sessionId,
        targetPackage,
        status,
        unlockUntil,
        grantedAt,
        rejectionReason,
      );

  @override
  String toString() =>
      'AccessGrantResult(session: $sessionId, target: $targetPackage, status: $status, unlockUntil: $unlockUntil)';
}
