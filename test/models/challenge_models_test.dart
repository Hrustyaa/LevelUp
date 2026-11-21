import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/challenge_exceptions.dart';
import 'package:levelup_test/models/challenge_definition.dart';
import 'package:levelup_test/models/challenge_request.dart';
import 'package:levelup_test/models/challenge_reward.dart';
import 'package:levelup_test/models/challenge_type.dart';
import 'package:levelup_test/models/exercise_type.dart';

void main() {
  group('ExerciseType', () {
    test('supports squats with correct metadata', () {
      expect(ExerciseType.squats.displayName, equals('Squats'));
      expect(ExerciseType.squats.description, contains('Bodyweight squats'));
    });
  });

  group('ChallengeReward', () {
    test('unlock factory creates access-eligible reward metadata', () {
      final reward = ChallengeReward.unlock(accessDurationSeconds: 300, xpAmount: 50);

      expect(reward.eligibleForAccess, isTrue);
      expect(reward.accessDurationSeconds, equals(300));
      expect(reward.accessDuration, equals(const Duration(minutes: 5)));
      expect(reward.xpAmount, equals(50));
    });

    test('freeWorkout factory creates non-access reward metadata', () {
      final reward = ChallengeReward.freeWorkout(xpAmount: 50);

      expect(reward.eligibleForAccess, isFalse);
      expect(reward.accessDurationSeconds, equals(0));
      expect(reward.accessDuration, equals(Duration.zero));
      expect(reward.xpAmount, equals(50));
    });

    test('implements equality, toMap, and toString', () {
      final a = ChallengeReward.unlock();
      final b = ChallengeReward.unlock();
      final c = ChallengeReward.freeWorkout();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));

      final map = a.toMap();
      expect(map['eligibleForAccess'], isTrue);
      expect(map['accessDurationSeconds'], equals(300));
      expect(a.toString(), contains('accessSec: 300'));
    });
  });

  group('ChallengeDefinition', () {
    test('valid definition passes validation', () {
      const def = ChallengeDefinition(
        challengeId: 'test_challenge',
        exerciseType: ExerciseType.squats,
        title: 'Test Title',
        description: 'Test Description',
        targetRepetitions: 5,
        accessDurationSeconds: 300,
        optionalXpReward: 50,
      );

      expect(() => def.validate(), returnsNormally);
      expect(def.accessDuration, equals(const Duration(minutes: 5)));
    });

    test('rejects empty challengeId', () {
      const def = ChallengeDefinition(
        challengeId: '   ',
        exerciseType: ExerciseType.squats,
        title: 'Title',
        description: 'Desc',
        targetRepetitions: 5,
      );

      expect(
        () => def.validate(),
        throwsA(isA<InvalidChallengeDefinitionException>()),
      );
    });

    test('rejects empty title', () {
      const def = ChallengeDefinition(
        challengeId: 'valid_id',
        exerciseType: ExerciseType.squats,
        title: '',
        description: 'Desc',
        targetRepetitions: 5,
      );

      expect(
        () => def.validate(),
        throwsA(isA<InvalidChallengeDefinitionException>()),
      );
    });

    test('rejects zero or negative target repetitions', () {
      const defZero = ChallengeDefinition(
        challengeId: 'valid_id',
        exerciseType: ExerciseType.squats,
        title: 'Title',
        description: 'Desc',
        targetRepetitions: 0,
      );
      expect(() => defZero.validate(), throwsA(isA<InvalidChallengeDefinitionException>()));

      const defNeg = ChallengeDefinition(
        challengeId: 'valid_id',
        exerciseType: ExerciseType.squats,
        title: 'Title',
        description: 'Desc',
        targetRepetitions: -5,
      );
      expect(() => defNeg.validate(), throwsA(isA<InvalidChallengeDefinitionException>()));
    });

    test('rejects negative access duration', () {
      const def = ChallengeDefinition(
        challengeId: 'valid_id',
        exerciseType: ExerciseType.squats,
        title: 'Title',
        description: 'Desc',
        targetRepetitions: 5,
        accessDurationSeconds: -10,
      );

      expect(() => def.validate(), throwsA(isA<InvalidChallengeDefinitionException>()));
    });

    test('toReward generates appropriate metadata based on context', () {
      const def = ChallengeDefinition(
        challengeId: 'test_def',
        exerciseType: ExerciseType.squats,
        title: 'Title',
        description: 'Desc',
        targetRepetitions: 5,
        accessDurationSeconds: 300,
        optionalXpReward: 75,
      );

      final unlockReward = def.toReward(isUnlockContext: true);
      expect(unlockReward.eligibleForAccess, isTrue);
      expect(unlockReward.accessDurationSeconds, equals(300));
      expect(unlockReward.xpAmount, equals(75));

      final freeReward = def.toReward(isUnlockContext: false);
      expect(freeReward.eligibleForAccess, isFalse);
      expect(freeReward.accessDurationSeconds, equals(0));
      expect(freeReward.xpAmount, equals(75));
    });

    test('implements equality and toMap', () {
      const a = ChallengeDefinition(
        challengeId: 'id_1',
        exerciseType: ExerciseType.squats,
        title: 'T',
        description: 'D',
        targetRepetitions: 5,
      );
      const b = ChallengeDefinition(
        challengeId: 'id_1',
        exerciseType: ExerciseType.squats,
        title: 'T',
        description: 'D',
        targetRepetitions: 5,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final map = a.toMap();
      expect(map['challengeId'], equals('id_1'));
      expect(map['exerciseType'], equals('squats'));
    });
  });

  group('ChallengeRequest', () {
    test('valid unlock request passes validation', () {
      final req = ChallengeRequest(
        requestId: 'req_123',
        challengeId: 'squats_unlock_5',
        context: ChallengeType.unlockChallenge,
        targetPackage: ChannelConstants.targetYouTube,
        createdAt: DateTime(2026, 11, 21),
      );

      expect(() => req.validate(), returnsNormally);
      expect(req.isUnlock, isTrue);
      expect(req.isFreeWorkout, isFalse);
    });

    test('valid free workout request passes validation without target', () {
      final req = ChallengeRequest(
        requestId: 'req_124',
        challengeId: 'squats_free_5',
        context: ChallengeType.freeWorkout,
        targetPackage: null,
        createdAt: DateTime(2026, 11, 21),
      );

      expect(() => req.validate(), returnsNormally);
      expect(req.isUnlock, isFalse);
      expect(req.isFreeWorkout, isTrue);
    });

    test('unlock request rejects empty or null targetPackage', () {
      final reqNull = ChallengeRequest(
        requestId: 'req_1',
        challengeId: 'squats_unlock_5',
        context: ChallengeType.unlockChallenge,
        targetPackage: null,
        createdAt: DateTime(2026, 11, 21),
      );
      expect(() => reqNull.validate(), throwsA(isA<InvalidChallengeRequestException>()));

      final reqEmpty = ChallengeRequest(
        requestId: 'req_2',
        challengeId: 'squats_unlock_5',
        context: ChallengeType.unlockChallenge,
        targetPackage: '   ',
        createdAt: DateTime(2026, 11, 21),
      );
      expect(() => reqEmpty.validate(), throwsA(isA<InvalidChallengeRequestException>()));
    });

    test('unlock request rejects unsupported target package', () {
      final req = ChallengeRequest(
        requestId: 'req_3',
        challengeId: 'squats_unlock_5',
        context: ChallengeType.unlockChallenge,
        targetPackage: 'com.unsupported.game',
        createdAt: DateTime(2026, 11, 21),
      );

      expect(
        () => req.validate(),
        throwsA(
          isA<UnsupportedChallengeTargetException>()
              .having((e) => e.targetPackage, 'targetPackage', equals('com.unsupported.game')),
        ),
      );
    });

    test('free workout rejects target package when provided', () {
      final req = ChallengeRequest(
        requestId: 'req_4',
        challengeId: 'squats_free_5',
        context: ChallengeType.freeWorkout,
        targetPackage: ChannelConstants.targetYouTube,
        createdAt: DateTime(2026, 11, 21),
      );

      expect(
        () => req.validate(),
        throwsA(
          isA<InvalidChallengeRequestException>()
              .having((e) => e.message, 'message', contains('must not specify a target package')),
        ),
      );
    });

    test('rejects empty requestId or challengeId', () {
      final reqEmptyId = ChallengeRequest(
        requestId: '',
        challengeId: 'squats_free_5',
        context: ChallengeType.freeWorkout,
        createdAt: DateTime(2026, 11, 21),
      );
      expect(() => reqEmptyId.validate(), throwsA(isA<InvalidChallengeRequestException>()));

      final reqEmptyDef = ChallengeRequest(
        requestId: 'req_5',
        challengeId: '',
        context: ChallengeType.freeWorkout,
        createdAt: DateTime(2026, 11, 21),
      );
      expect(() => reqEmptyDef.validate(), throwsA(isA<InvalidChallengeRequestException>()));
    });

    test('implements equality, toMap, and toString', () {
      final time = DateTime(2026, 11, 21, 16, 0);
      final a = ChallengeRequest(
        requestId: 'req_10',
        challengeId: 'def_1',
        context: ChallengeType.freeWorkout,
        createdAt: time,
      );
      final b = ChallengeRequest(
        requestId: 'req_10',
        challengeId: 'def_1',
        context: ChallengeType.freeWorkout,
        createdAt: time,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      final map = a.toMap();
      expect(map['requestId'], equals('req_10'));
      expect(map['context'], equals('freeWorkout'));
      expect(a.toString(), contains('req_10'));
    });
  });
}
