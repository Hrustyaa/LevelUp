import '../../../core/constants/channel_constants.dart';
import '../../../core/errors/challenge_exceptions.dart';
import '../../../models/challenge_definition.dart';
import '../../../models/challenge_request.dart';
import '../../../models/challenge_type.dart';
import '../../../models/exercise_type.dart';
import '../data/challenge_catalog.dart';
import 'push_up_verification.dart';

export '../../../core/errors/challenge_exceptions.dart';
export '../../../models/challenge_definition.dart';
export '../../../models/challenge_request.dart';
export '../../../models/challenge_reward.dart';
export '../../../models/challenge_type.dart';
export '../../../models/exercise_type.dart';

/// Contract for managing physical challenge definitions, requests, and catalog lookups.
abstract class IChallengeService {
  /// Returns all challenge configurations currently supported in the catalog.
  List<ChallengeDefinition> getAvailableChallenges();

  /// Returns the default 5-squat app unlock challenge definition.
  ChallengeDefinition getDefaultUnlockChallenge();

  /// Returns the default 5-squat free workout challenge definition.
  ChallengeDefinition getDefaultFreeWorkout();

  /// Retrieves a specific challenge definition by [challengeId].
  ///
  /// Throws [UnknownChallengeException] if [challengeId] is not found in the catalog.
  ChallengeDefinition getChallengeDefinition(String challengeId);

  /// Creates and validates a new unlock challenge request targeting [targetPackage].
  ///
  /// [targetPackage] must be in [ChannelConstants.allowedTargets].
  /// Throws [UnsupportedChallengeTargetException] if [targetPackage] is invalid.
  ChallengeRequest createUnlockChallengeRequest(
    String targetPackage, {
    ExerciseType exerciseType = ExerciseType.squats,
  });

  /// Creates and validates a new free workout challenge request.
  ChallengeRequest createFreeWorkoutRequest({
    ExerciseType exerciseType = ExerciseType.squats,
  });

  /// Validates a [ChallengeRequest] against catalog definitions and context rules.
  ///
  /// Throws [UnknownChallengeException] if [request.challengeId] does not exist.
  /// Throws [InvalidChallengeRequestException] or [UnsupportedChallengeTargetException] on invalid parameters.
  void validateChallengeRequest(ChallengeRequest request);
}

/// Production implementation of [IChallengeService].
class ChallengeService implements IChallengeService {
  final Map<String, ChallengeDefinition> _catalog;
  final String Function() _idGenerator;
  final DateTime Function() _clock;
  static int _sequence = 0;

  /// Creates a [ChallengeService].
  ///
  /// Allows injection of custom catalog, id generator, and clock for deterministic testing.
  ChallengeService({
    Map<String, ChallengeDefinition>? catalog,
    String Function()? idGenerator,
    DateTime Function()? clock,
  })  : _catalog = catalog ?? ChallengeCatalog.byId,
        _idGenerator = idGenerator ?? _defaultIdGenerator,
        _clock = clock ?? DateTime.now;

  static String _defaultIdGenerator() {
    _sequence++;
    return 'req_${DateTime.now().microsecondsSinceEpoch}_$_sequence';
  }

  @override
  List<ChallengeDefinition> getAvailableChallenges() {
    return List.unmodifiable(_catalog.values);
  }

  @override
  ChallengeDefinition getDefaultUnlockChallenge() {
    return getChallengeDefinition(ChallengeCatalog.squatUnlockId);
  }

  @override
  ChallengeDefinition getDefaultFreeWorkout() {
    return getChallengeDefinition(ChallengeCatalog.squatFreeWorkoutId);
  }

  @override
  ChallengeDefinition getChallengeDefinition(String challengeId) {
    final def = _catalog[challengeId];
    if (def == null) {
      throw UnknownChallengeException(challengeId);
    }
    def.validate();
    return def;
  }

  @override
  ChallengeRequest createUnlockChallengeRequest(
    String targetPackage, {
    ExerciseType exerciseType = ExerciseType.squats,
  }) {
    if (!ChannelConstants.allowedTargets.contains(targetPackage)) {
      throw UnsupportedChallengeTargetException(targetPackage);
    }

    if (exerciseType == ExerciseType.pushUp && !PushUpVerification.unlockEnabled) {
      throw const InvalidChallengeRequestException('Push-up unlocking is disabled.');
    }

    final challenge = exerciseType == ExerciseType.pushUp
        ? getChallengeDefinition(ChallengeCatalog.pushUpUnlockId)
        : getDefaultUnlockChallenge();
    final request = ChallengeRequest(
      requestId: _idGenerator(),
      challengeId: challenge.challengeId,
      context: ChallengeType.unlockChallenge,
      targetPackage: targetPackage,
      createdAt: _clock(),
    );

    validateChallengeRequest(request);
    return request;
  }

  @override
  ChallengeRequest createFreeWorkoutRequest({
    ExerciseType exerciseType = ExerciseType.squats,
  }) {
    final challengeDef = exerciseType == ExerciseType.pushUp
        ? getChallengeDefinition(ChallengeCatalog.pushUpFreeWorkoutId)
        : getDefaultFreeWorkout();
    final request = ChallengeRequest(
      requestId: _idGenerator(),
      challengeId: challengeDef.challengeId,
      context: ChallengeType.freeWorkout,
      targetPackage: null,
      createdAt: _clock(),
    );

    validateChallengeRequest(request);
    return request;
  }

  @override
  void validateChallengeRequest(ChallengeRequest request) {
    // 1. Verify definition exists and is valid
    final definition = getChallengeDefinition(request.challengeId);

    // 2. Validate request properties
    request.validate();

    // 3. Verify context alignment
    if (request.isUnlock &&
        definition.exerciseType == ExerciseType.pushUp &&
        !PushUpVerification.unlockEnabled) {
      throw const InvalidChallengeRequestException('Push-up unlocking is disabled.');
    }

    if (request.isUnlock && definition.accessDurationSeconds <= 0) {
      throw InvalidChallengeRequestException(
        'Challenge "${definition.challengeId}" has 0 access duration and cannot be used as an unlock challenge.',
      );
    }
  }
}
