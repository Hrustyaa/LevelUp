import 'package:flutter/foundation.dart';

import '../../../data/database/database_constants.dart';
import '../../../models/challenge_type.dart';

/// Immutable durable XP reward journal entry persisted in SQLite.
@immutable
class XpRewardRecord {
  final String sessionId;
  final String challengeId;
  final ChallengeType challengeContext;
  final int xpAmount;
  final DateTime awardedAt;
  final String localDate;
  final String verificationSource;

  const XpRewardRecord({
    required this.sessionId,
    required this.challengeId,
    required this.challengeContext,
    required this.xpAmount,
    required this.awardedAt,
    required this.localDate,
    required this.verificationSource,
  });

  Map<String, dynamic> toMap() => {
        DatabaseConstants.colSessionId: sessionId,
        DatabaseConstants.colChallengeId: challengeId,
        DatabaseConstants.colChallengeContext: challengeContext.name,
        DatabaseConstants.colXpAmount: xpAmount,
        DatabaseConstants.colAwardedAt: awardedAt.toUtc().millisecondsSinceEpoch,
        DatabaseConstants.colLocalDate: localDate,
        DatabaseConstants.colVerificationSource: verificationSource,
      };

  factory XpRewardRecord.fromMap(Map<String, dynamic> map) {
    final contextName = map[DatabaseConstants.colChallengeContext] as String;
    return XpRewardRecord(
      sessionId: map[DatabaseConstants.colSessionId] as String,
      challengeId: map[DatabaseConstants.colChallengeId] as String,
      challengeContext: ChallengeType.values.byName(contextName),
      xpAmount: (map[DatabaseConstants.colXpAmount] as num).toInt(),
      awardedAt: DateTime.fromMillisecondsSinceEpoch(
        (map[DatabaseConstants.colAwardedAt] as num).toInt(),
        isUtc: true,
      ),
      localDate: map[DatabaseConstants.colLocalDate] as String,
      verificationSource:
          (map[DatabaseConstants.colVerificationSource] as String?) ?? 'camera',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XpRewardRecord &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          challengeId == other.challengeId &&
          challengeContext == other.challengeContext &&
          xpAmount == other.xpAmount &&
          awardedAt == other.awardedAt &&
          localDate == other.localDate &&
          verificationSource == other.verificationSource;

  @override
  int get hashCode => Object.hash(
        sessionId,
        challengeId,
        challengeContext,
        xpAmount,
        awardedAt,
        localDate,
        verificationSource,
      );
}
