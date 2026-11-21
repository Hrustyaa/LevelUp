import 'package:flutter/foundation.dart';

/// Represents the status of temporary access unlocked after completing exercise.
@immutable
class NativeAccessStatus {
  /// Expiration timestamp in calendar time, or null if access is not granted.
  final DateTime? unlockUntil;

  const NativeAccessStatus({
    this.unlockUntil,
  });

  /// Factory constructor that parses epoch milliseconds from native storage.
  /// Treats 0, negative values, and null as no active access grant.
  factory NativeAccessStatus.fromEpochMs(dynamic epochMs) {
    if (epochMs == null) {
      return const NativeAccessStatus(unlockUntil: null);
    }

    final int? ms;
    if (epochMs is int) {
      ms = epochMs;
    } else if (epochMs is num) {
      ms = epochMs.toInt();
    } else {
      ms = null;
    }

    if (ms == null || ms <= 0) {
      return const NativeAccessStatus(unlockUntil: null);
    }

    return NativeAccessStatus(
      unlockUntil: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// Whether unlocked access is currently active relative to the given [now] (defaults to DateTime.now()).
  bool isAccessActive([DateTime? now]) {
    final expiry = unlockUntil;
    if (expiry == null) return false;
    return expiry.isAfter(now ?? DateTime.now());
  }

  /// Remaining duration of temporary access relative to [now].
  /// Returns [Duration.zero] if expired or not unlocked.
  Duration remainingAccess([DateTime? now]) {
    final expiry = unlockUntil;
    if (expiry == null) return Duration.zero;
    final diff = expiry.difference(now ?? DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeAccessStatus &&
          runtimeType == other.runtimeType &&
          unlockUntil == other.unlockUntil;

  @override
  int get hashCode => unlockUntil.hashCode;

  @override
  String toString() => 'NativeAccessStatus(unlockUntil: $unlockUntil)';
}
