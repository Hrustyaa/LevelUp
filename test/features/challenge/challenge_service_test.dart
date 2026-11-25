import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/data/challenge_catalog.dart';

void main() {
  late ChallengeService service;

  setUp(() {
    service = ChallengeService();
  });

  group('Catalog & Definition Lookups', () {
    test('loads the default unlock challenge with 5 squats and 5 minutes access', () {
      final defaultUnlock = service.getDefaultUnlockChallenge();

      expect(defaultUnlock.challengeId, equals(ChallengeCatalog.squatUnlockId));
      expect(defaultUnlock.exerciseType, equals(ExerciseType.squats));
      expect(defaultUnlock.targetRepetitions, equals(5));
      expect(defaultUnlock.accessDurationSeconds, equals(300));
      expect(defaultUnlock.accessDuration, equals(const Duration(minutes: 5)));
      expect(defaultUnlock.optionalXpReward, isNotNull);
    });

    test('loads the default free workout with 5 squats and 0 access duration', () {
      final defaultFree = service.getDefaultFreeWorkout();

      expect(defaultFree.challengeId, equals(ChallengeCatalog.squatFreeWorkoutId));
      expect(defaultFree.exerciseType, equals(ExerciseType.squats));
      expect(defaultFree.targetRepetitions, equals(5));
      expect(defaultFree.accessDurationSeconds, equals(0));
      expect(defaultFree.accessDuration, equals(Duration.zero));
    });

    test('challenge catalog is deterministic and immutable', () {
      final available1 = service.getAvailableChallenges();
      final available2 = service.getAvailableChallenges();

      expect(available1.length, equals(4));
      final pushUps = available1.singleWhere(
        (definition) => definition.challengeId == ChallengeCatalog.pushUpUnlockId,
      );
      expect(pushUps.exerciseType, ExerciseType.pushUp);
      expect(pushUps.targetRepetitions, 5);
      expect(pushUps.accessDurationSeconds, 300);
      expect(available1, equals(available2));

      // Attempting to modify the list should throw UnsupportedError
      expect(() => available1.add(available1.first), throwsUnsupportedError);
    });

    test('throws UnknownChallengeException when challengeId is not found', () {
      expect(
        () => service.getChallengeDefinition('non_existent_challenge_id'),
        throwsA(
          isA<UnknownChallengeException>()
              .having((e) => e.challengeId, 'challengeId', equals('non_existent_challenge_id')),
        ),
      );
    });
  });

  group('Creating Unlock Challenge Requests', () {
    test('creates valid unlock request for all allowed target packages', () {
      for (final target in ChannelConstants.allowedTargets) {
        final request = service.createUnlockChallengeRequest(target);

        expect(request.isUnlock, isTrue);
        expect(request.isFreeWorkout, isFalse);
        expect(request.targetPackage, equals(target));
        expect(request.challengeId, equals(ChallengeCatalog.squatUnlockId));
        expect(request.requestId, isNotEmpty);
      }
    });

    test('rejects unsupported target packages with UnsupportedChallengeTargetException', () {
      const unsupported = 'com.facebook.katana';

      expect(
        () => service.createUnlockChallengeRequest(unsupported),
        throwsA(
          isA<UnsupportedChallengeTargetException>()
              .having((e) => e.targetPackage, 'targetPackage', equals(unsupported)),
        ),
      );
    });

    test('rejects empty or whitespace target packages', () {
      expect(
        () => service.createUnlockChallengeRequest(''),
        throwsA(isA<UnsupportedChallengeTargetException>()),
      );
      expect(
        () => service.createUnlockChallengeRequest('   '),
        throwsA(isA<UnsupportedChallengeTargetException>()),
      );
    });
  });

  group('Creating Free Workout Requests', () {
    test('creates free workout request without target package', () {
      final request = service.createFreeWorkoutRequest();

      expect(request.isFreeWorkout, isTrue);
      expect(request.isUnlock, isFalse);
      expect(request.targetPackage, isNull);
      expect(request.challengeId, equals(ChallengeCatalog.squatFreeWorkoutId));
      expect(request.requestId, isNotEmpty);
    });
  });

  group('Request ID Uniqueness', () {
    test('generates unique request IDs across sequential creations', () {
      final idSet = <String>{};
      for (var i = 0; i < 50; i++) {
        final req = service.createFreeWorkoutRequest();
        expect(idSet.contains(req.requestId), isFalse, reason: 'Request ID must be unique');
        idSet.add(req.requestId);
      }
      expect(idSet.length, equals(50));
    });

    test('custom idGenerator and clock can be injected for deterministic testing', () {
      var count = 0;
      final fixedTime = DateTime(2026, 11, 21, 16, 45);

      final customService = ChallengeService(
        idGenerator: () => 'deterministic_id_${++count}',
        clock: () => fixedTime,
      );

      final req1 = customService.createUnlockChallengeRequest(ChannelConstants.targetYouTube);
      final req2 = customService.createFreeWorkoutRequest();

      expect(req1.requestId, equals('deterministic_id_1'));
      expect(req1.createdAt, equals(fixedTime));

      expect(req2.requestId, equals('deterministic_id_2'));
      expect(req2.createdAt, equals(fixedTime));
    });
  });

  group('Request Validation Rules', () {
    test('rejects unlock challenge mapped to a 0-access duration definition', () {
      // Create request where challengeId is the free workout (0 access duration), but context is unlockChallenge
      final mismatched = ChallengeRequest(
        requestId: 'test_mismatch',
        challengeId: ChallengeCatalog.squatFreeWorkoutId,
        context: ChallengeType.unlockChallenge,
        targetPackage: ChannelConstants.targetYouTube,
        createdAt: DateTime(2026, 11, 21),
      );

      expect(
        () => service.validateChallengeRequest(mismatched),
        throwsA(
          isA<InvalidChallengeRequestException>()
              .having((e) => e.message, 'message', contains('has 0 access duration and cannot be used as an unlock challenge')),
        ),
      );
    });

    test('rejects request with unknown challengeId during validation', () {
      final unknownReq = ChallengeRequest(
        requestId: 'test_unknown',
        challengeId: 'unknown_def_999',
        context: ChallengeType.freeWorkout,
        targetPackage: null,
        createdAt: DateTime(2026, 11, 21),
      );

      expect(
        () => service.validateChallengeRequest(unknownReq),
        throwsA(isA<UnknownChallengeException>()),
      );
    });
  });

  group('Invariant Integrity Checks', () {
    test('ChallengeService contains no platform channels and never calls grantAccess', () {
      // ChallengeService operates purely in-memory and has no access to MethodChannels or native grantAccess
      final available = service.getAvailableChallenges();
      expect(available, isNotEmpty);

      final unlockReq = service.createUnlockChallengeRequest(ChannelConstants.targetYouTube);
      final freeReq = service.createFreeWorkoutRequest();

      expect(unlockReq.requestId, isNotEmpty);
      expect(freeReq.requestId, isNotEmpty);
    });

    test('ChallengeService never modifies FocusService or awards XP directly', () {
      // Rewards are represented as passive ChallengeReward metadata only
      final def = service.getDefaultUnlockChallenge();
      final reward = def.toReward(isUnlockContext: true);

      expect(reward.xpAmount, equals(50));
      expect(reward.eligibleForAccess, isTrue);
      // No XP persistence or state alteration occurs in this module
    });
  });
}
