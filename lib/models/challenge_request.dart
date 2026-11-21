import 'package:flutter/foundation.dart';

import '../core/constants/channel_constants.dart';
import '../core/errors/challenge_exceptions.dart';
import 'challenge_type.dart';

/// Represents an instantiated request to begin a physical challenge.
@immutable
class ChallengeRequest {
  /// Unique identifier of this challenge session request.
  final String requestId;

  /// Identifier of the challenge definition to be performed.
  final String challengeId;

  /// Operational context of the challenge (unlockChallenge or freeWorkout).
  final ChallengeType context;

  /// The Android application targeted for unlocked access.
  /// Mandatory for [ChallengeType.unlockChallenge]; MUST be null for [ChallengeType.freeWorkout].
  final String? targetPackage;

  /// Timestamp when the request was initiated.
  final DateTime createdAt;

  const ChallengeRequest({
    required this.requestId,
    required this.challengeId,
    required this.context,
    this.targetPackage,
    required this.createdAt,
  });

  /// Validates the request against strict context and target rules.
  ///
  /// Throws [InvalidChallengeRequestException] or [UnsupportedChallengeTargetException].
  void validate() {
    if (requestId.trim().isEmpty) {
      throw const InvalidChallengeRequestException('requestId must not be empty.');
    }
    if (challengeId.trim().isEmpty) {
      throw const InvalidChallengeRequestException('challengeId must not be empty.');
    }

    switch (context) {
      case ChallengeType.unlockChallenge:
        if (targetPackage == null || targetPackage!.trim().isEmpty) {
          throw const InvalidChallengeRequestException(
            'Unlock challenge requires a valid, non-empty target package.',
          );
        }
        if (!ChannelConstants.allowedTargets.contains(targetPackage)) {
          throw UnsupportedChallengeTargetException(targetPackage!);
        }
        break;

      case ChallengeType.freeWorkout:
        if (targetPackage != null && targetPackage!.trim().isNotEmpty) {
          throw InvalidChallengeRequestException(
            'Free workout must not specify a target package, but had "$targetPackage".',
          );
        }
        break;
    }
  }

  /// Whether this request is an unlock challenge.
  bool get isUnlock => context == ChallengeType.unlockChallenge;

  /// Whether this request is a free workout.
  bool get isFreeWorkout => context == ChallengeType.freeWorkout;

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'challengeId': challengeId,
      'context': context.name,
      'targetPackage': targetPackage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChallengeRequest &&
          runtimeType == other.runtimeType &&
          requestId == other.requestId &&
          challengeId == other.challengeId &&
          context == other.context &&
          targetPackage == other.targetPackage &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(requestId, challengeId, context, targetPackage, createdAt);

  @override
  String toString() =>
      'ChallengeRequest(id: $requestId, challenge: $challengeId, context: $context, target: $targetPackage)';
}
