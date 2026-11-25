import 'dart:async';

import '../../../data/repositories/workout_history_repository.dart';
import '../../../models/workout_result.dart';
import '../data/progress_repository.dart';
import '../models/progress_state.dart';
import '../models/xp_reward_record.dart';
import 'level_calculator.dart';
import 'streak_calculator.dart';
import 'xp_reward_policy.dart';

/// Outcome of processing a completed workout for XP & progress.
class XpRewardOutcome {
  final bool awarded;
  final bool duplicate;
  final int xpAwarded;
  final String? reason;

  const XpRewardOutcome({
    required this.awarded,
    required this.duplicate,
    required this.xpAwarded,
    this.reason,
  });
}

/// Contract for the Module 09A Progress & XP Engine.
abstract class IProgressService {
  ProgressState get currentState;
  Stream<ProgressState> get stateStream;

  Future<ProgressState> initialize();
  Future<ProgressState> refresh();
  Future<XpRewardOutcome> recordCompletedWorkout(WorkoutResult result);
  void dispose();
}

/// Production implementation of [IProgressService].
///
/// Enforces:
/// - Centralized [XpRewardPolicy] eligibility checks.
/// - Serialized, transactional, exactly-once XP recording per `sessionId`.
/// - Deterministic [LevelCalculator] and [StreakCalculator] state derived from
///   the durable SQLite reward journal.
class ProgressService implements IProgressService {
  final IProgressRepository _repository;
  final IWorkoutHistoryRepository? _historyRepository;
  final XpRewardPolicy _policy;
  final LevelCalculator _levelCalculator;
  final StreakCalculator _streakCalculator;
  final DateTime Function() _clock;

  final StreamController<ProgressState> _stateController =
      StreamController<ProgressState>.broadcast();

  ProgressState _currentState = ProgressState.initial();
  Future<void> _serialQueue = Future<void>.value();
  bool _disposed = false;

  ProgressService({
    required IProgressRepository repository,
    IWorkoutHistoryRepository? historyRepository,
    XpRewardPolicy policy = const XpRewardPolicy(),
    LevelCalculator levelCalculator = const LevelCalculator(),
    StreakCalculator streakCalculator = const StreakCalculator(),
    DateTime Function()? clock,
  })  : _repository = repository,
        _historyRepository = historyRepository,
        _policy = policy,
        _levelCalculator = levelCalculator,
        _streakCalculator = streakCalculator,
        _clock = clock ?? DateTime.now;

  @override
  ProgressState get currentState => _currentState;

  @override
  Stream<ProgressState> get stateStream => _stateController.stream;

  @override
  Future<ProgressState> initialize() => refresh();

  @override
  Future<ProgressState> refresh() {
    return _enqueue(() async {
      if (_disposed) return _currentState;
      _emit(_currentState.copyWith(isLoading: true, clearError: true));
      try {
        final state = await _loadStateFromRepository();
        _emit(state);
        return state;
      } catch (e) {
        final failed = _currentState.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load progress state: $e',
        );
        _emit(failed);
        return failed;
      }
    });
  }

  @override
  Future<XpRewardOutcome> recordCompletedWorkout(WorkoutResult result) {
    return _enqueue(() async {
      if (_disposed) {
        return const XpRewardOutcome(
          awarded: false,
          duplicate: false,
          xpAwarded: 0,
          reason: 'ProgressService disposed',
        );
      }

      final decision = _policy.evaluate(result);
      if (!decision.eligible) {
        return XpRewardOutcome(
          awarded: false,
          duplicate: false,
          xpAwarded: 0,
          reason: decision.rejectionReason,
        );
      }

      try {
        final record = XpRewardRecord(
          sessionId: result.sessionId,
          challengeId: result.challengeId,
          challengeContext: result.challengeContext,
          xpAmount: decision.xpAmount,
          awardedAt: result.completedAt.toUtc(),
          localDate: StreakCalculator.formatLocalDate(result.completedAt),
          verificationSource: result.source,
        );

        final inserted = await _repository.recordRewardIfAbsent(record);
        final nextState = await _loadStateFromRepository();
        _emit(nextState);

        if (!inserted) {
          return const XpRewardOutcome(
            awarded: false,
            duplicate: true,
            xpAwarded: 0,
            reason: 'Reward already recorded for session',
          );
        }

        return XpRewardOutcome(
          awarded: true,
          duplicate: false,
          xpAwarded: decision.xpAmount,
        );
      } catch (e) {
        final failed = _currentState.copyWith(
          isLoading: false,
          errorMessage: 'Failed to record XP reward: $e',
        );
        _emit(failed);
        return XpRewardOutcome(
          awarded: false,
          duplicate: false,
          xpAwarded: 0,
          reason: '$e',
        );
      }
    });
  }

  Future<ProgressState> _loadStateFromRepository() async {
    await _reconcileMissingRewards();

    final rewards = await _repository.getAllRewards();
    final rawTotal = await _repository.getTotalXp();
    final safeTotal = rawTotal < 0 ? 0 : rawTotal;

    final levelInfo = _levelCalculator.calculate(safeTotal);
    final streakInfo = _streakCalculator.calculate(
      rewards.map((r) => r.localDate),
      now: _clock(),
    );

    return ProgressState(
      levelInfo: levelInfo,
      streakInfo: streakInfo,
      recentRewards: rewards.take(20).toList(growable: false),
      completedWorkoutCount: rewards.length,
      isLoading: false,
      errorMessage: null,
    );
  }

  /// Recovers any eligible Module-09A+ workouts persisted in `workout_sessions`
  /// whose XP reward previously failed transiently, without fabricating XP for
  /// pre-Module-09 historical sessions (`completedAt < progress_epoch_ms`).
  Future<void> _reconcileMissingRewards() async {
    final epochMs = await _repository.getOrCreateProgressEpochMs(
      _clock().toUtc().millisecondsSinceEpoch,
    );
    final historyRepo = _historyRepository;
    if (historyRepo == null) return;

    final existingRewards = await _repository.getAllRewards();
    final rewardedSessions = existingRewards.map((r) => r.sessionId).toSet();
    final recentWorkouts = await historyRepo.getRecentWorkouts(limit: 50);

    for (final workout in recentWorkouts) {
      if (rewardedSessions.contains(workout.sessionId)) continue;
      if (workout.completedAt.toUtc().millisecondsSinceEpoch < epochMs) {
        continue;
      }
      final decision = _policy.evaluatePersistedWorkout(workout);
      if (!decision.eligible) continue;

      await _repository.recordRewardIfAbsent(
        XpRewardRecord(
          sessionId: workout.sessionId,
          challengeId: workout.challengeId,
          challengeContext: workout.challengeContext,
          xpAmount: decision.xpAmount,
          awardedAt: workout.completedAt.toUtc(),
          localDate: StreakCalculator.formatLocalDate(workout.completedAt),
          verificationSource: workout.source,
        ),
      );
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _serialQueue = _serialQueue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _emit(ProgressState next) {
    _currentState = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stateController.close();
  }
}
