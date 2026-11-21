import 'package:flutter/foundation.dart';

/// Metadata description of potential rewards earned upon completing a challenge.
///
/// This model is strictly descriptive metadata.
/// The Challenge Engine does NOT grant Android access or persist XP awards.
@immutable
class ChallengeReward {
  /// Base experience points associated with the challenge (0 if none).
  final int xpAmount;

  /// Duration of screen-time access in seconds if eligible (0 if none).
  final int accessDurationSeconds;

  /// Whether completing this challenge qualifies the user for temporary app access.
  final bool eligibleForAccess;

  const ChallengeReward({
    this.xpAmount = 0,
    this.accessDurationSeconds = 0,
    required this.eligibleForAccess,
  })  : assert(xpAmount >= 0, 'xpAmount must be non-negative'),
        assert(accessDurationSeconds >= 0, 'accessDurationSeconds must be non-negative');

  /// Creates a reward descriptor for an app unlock challenge (e.g. 5 minutes access).
  factory ChallengeReward.unlock({
    int accessDurationSeconds = 300,
    int xpAmount = 50,
  }) {
    return ChallengeReward(
      xpAmount: xpAmount,
      accessDurationSeconds: accessDurationSeconds,
      eligibleForAccess: true,
    );
  }

  /// Creates a reward descriptor for a free workout (no app unlock).
  factory ChallengeReward.freeWorkout({
    int xpAmount = 50,
  }) {
    return ChallengeReward(
      xpAmount: xpAmount,
      accessDurationSeconds: 0,
      eligibleForAccess: false,
    );
  }

  /// Access duration represented as [Duration].
  Duration get accessDuration => Duration(seconds: accessDurationSeconds);

  Map<String, dynamic> toMap() {
    return {
      'xpAmount': xpAmount,
      'accessDurationSeconds': accessDurationSeconds,
      'eligibleForAccess': eligibleForAccess,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeReward &&
          runtimeType == other.runtimeType &&
          xpAmount == other.xpAmount &&
          accessDurationSeconds == other.accessDurationSeconds &&
          eligibleForAccess == other.eligibleForAccess;

  @override
  int get hashCode => Object.hash(xpAmount, accessDurationSeconds, eligibleForAccess);

  @override
  String toString() =>
      'ChallengeReward(xp: $xpAmount, accessSec: $accessDurationSeconds, eligible: $eligibleForAccess)';
}
