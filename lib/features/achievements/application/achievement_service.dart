import 'dart:async';

import '../../progress/application/progress_service.dart';
import '../../progress/models/progress_state.dart';
import '../../statistics/application/statistics_service.dart';
import '../../statistics/models/statistics_snapshot.dart';
import '../data/achievement_catalog.dart';
import '../data/achievement_repository.dart';
import '../models/achievement_category.dart';
import '../models/achievement_definition.dart';
import '../models/achievement_progress.dart';
import '../models/achievement_state.dart';
import '../models/achievement_unlock_record.dart';

/// Application-level contract for LevelUp's Achievements Engine.
abstract class IAchievementService {
  AchievementState get currentState;

  Stream<AchievementState> get stateStream;

  Future<AchievementState> initialize();

  Future<AchievementState> evaluateAndRefresh();

  void dispose();
}

/// Serialized, exactly-once Achievements Engine evaluating milestones from
/// authoritative [IStatisticsService] and [IProgressService] state.
///
/// Achievements never award XP, never grant native app access, and never
/// trigger `StatisticsService.refresh()` or `ProgressService.refresh()`.
class AchievementService implements IAchievementService {
  final IAchievementRepository _repository;
  final IStatisticsService _statisticsService;
  final IProgressService _progressService;
  final List<AchievementDefinition> _definitions;
  final DateTime Function() _clock;

  final StreamController<AchievementState> _stateController =
      StreamController<AchievementState>.broadcast();

  AchievementState _currentState = AchievementState.initial();
  Future<void> _serialQueue = Future<void>.value();
  bool _disposed = false;

  AchievementService({
    required IAchievementRepository repository,
    required IStatisticsService statisticsService,
    required IProgressService progressService,
    List<AchievementDefinition>? definitions,
    DateTime Function()? clock,
  })  : _repository = repository,
        _statisticsService = statisticsService,
        _progressService = progressService,
        _definitions = definitions ?? AchievementCatalog.definitions,
        _clock = clock ?? DateTime.now;

  @override
  AchievementState get currentState => _currentState;

  @override
  Stream<AchievementState> get stateStream => _stateController.stream;

  @override
  Future<AchievementState> initialize() => evaluateAndRefresh();

  @override
  Future<AchievementState> evaluateAndRefresh() {
    return _enqueue(() async {
      if (_disposed) return _currentState;
      _emit(_currentState.copyWith(isLoading: true, clearError: true));

      try {
        final stats = _statisticsService.currentSnapshot;
        final progress = _progressService.currentState;
        final existingRecords = await _repository.getUnlockedRecords();

        if (_disposed) return _currentState;

        final unlockedById = <String, AchievementUnlockRecord>{
          for (final r in existingRecords) r.achievementId: r,
        };

        if (stats.hasError || progress.errorMessage != null) {
          final upstreamError = stats.errorMessage ?? progress.errorMessage!;
          final preserved = _buildProgressList(
            stats: stats,
            progress: progress,
            unlockedById: unlockedById,
            errorFallback: true,
          );
          final failed = _currentState.copyWith(
            achievements: preserved,
            isLoading: false,
            errorMessage: upstreamError,
          );
          _emit(failed);
          throw StateError(upstreamError);
        }

        final newlyUnlocked = <AchievementUnlockRecord>[];
        final nowUtc = _clock().toUtc();

        for (final def in _definitions) {
          if (unlockedById.containsKey(def.id)) continue;
          final observed = _extractObservedValue(
            def: def,
            stats: stats,
            progress: progress,
          );
          if (observed >= def.targetValue) {
            final record = AchievementUnlockRecord(
              achievementId: def.id,
              unlockedAt: nowUtc,
              category: def.category,
              targetValue: def.targetValue,
              observedValue: observed,
            );
            final inserted = await _repository.recordUnlockIfAbsent(record);
            if (inserted) {
              unlockedById[def.id] = record;
              newlyUnlocked.add(record);
            } else {
              // Concurrent/prior insert: reload authoritative timestamp
              final reloaded = await _repository.getUnlockedRecords();
              for (final r in reloaded) {
                unlockedById.putIfAbsent(r.achievementId, () => r);
              }
            }
          }
        }

        if (_disposed) return _currentState;

        final items = _buildProgressList(
          stats: stats,
          progress: progress,
          unlockedById: unlockedById,
          errorFallback: false,
        );

        final next = AchievementState(
          achievements: items,
          recentlyUnlocked: newlyUnlocked,
          isLoading: false,
          errorMessage: null,
        );
        _emit(next);
        return next;
      } catch (e) {
        if (_disposed) rethrow;
        final failed = _currentState.copyWith(
          isLoading: false,
          errorMessage: 'Failed to evaluate achievements: $e',
        );
        _emit(failed);
        rethrow;
      }
    });
  }

  List<AchievementProgress> _buildProgressList({
    required StatisticsSnapshot stats,
    required ProgressState progress,
    required Map<String, AchievementUnlockRecord> unlockedById,
    required bool errorFallback,
  }) {
    final sorted = [..._definitions]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return sorted.map((def) {
      final record = unlockedById[def.id];
      final isUnlocked = record != null;
      final raw = errorFallback
          ? (isUnlocked ? def.targetValue : 0)
          : _extractObservedValue(def: def, stats: stats, progress: progress);
      return AchievementProgress(
        definition: def,
        currentValue: raw < 0 ? 0 : raw,
        isUnlocked: isUnlocked,
        unlockedAt: record?.unlockedAt,
      );
    }).toList(growable: false);
  }

  int _extractObservedValue({
    required AchievementDefinition def,
    required StatisticsSnapshot stats,
    required ProgressState progress,
  }) {
    final raw = switch (def.category) {
      AchievementCategory.workouts => stats.workouts.allTimeCompleted,
      AchievementCategory.repetitions => stats.workouts.totalVerifiedRepetitions,
      AchievementCategory.unlocks => stats.unlocks.allTimeConfirmed,
      AchievementCategory.streaks => progress.longestStreak,
      AchievementCategory.levels => progress.level,
    };
    return raw < 0 ? 0 : raw;
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

  void _emit(AchievementState next) {
    _currentState = next;
    if (!_disposed && !_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stateController.close();
  }
}
