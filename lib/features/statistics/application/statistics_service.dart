import 'dart:async';

import '../../focus/application/focus_service.dart';
import '../../progress/application/progress_service.dart';
import '../data/statistics_repository.dart';
import '../models/access_duration_statistics.dart';
import '../models/daily_activity_stats.dart';
import '../models/statistics_snapshot.dart';
import '../models/unlock_statistics.dart';
import '../models/workout_statistics.dart';

/// Application-level contract for authoritative LevelUp activity statistics.
abstract class IStatisticsService {
  StatisticsSnapshot get currentSnapshot;

  Stream<StatisticsSnapshot> get snapshotStream;

  Future<StatisticsSnapshot> initialize();

  Future<StatisticsSnapshot> refresh();

  void dispose();
}

/// Read-only serialized Statistics Engine aggregating SQLite workout & unlock
/// journals alongside Module 09 [IProgressService] and [IFocusService] state.
///
/// Statistics queries never award XP, never mutate SQLite tables, and never
/// grant native app access.
class StatisticsService implements IStatisticsService {
  final IStatisticsRepository _repository;
  final IProgressService _progressService;
  final IFocusService? _focusService;
  final DateTime Function() _clock;

  final StreamController<StatisticsSnapshot> _snapshotController =
      StreamController<StatisticsSnapshot>.broadcast();

  StatisticsSnapshot _currentSnapshot = StatisticsSnapshot.initial();
  Future<void> _serialQueue = Future<void>.value();
  bool _disposed = false;

  StatisticsService({
    required IStatisticsRepository repository,
    required IProgressService progressService,
    IFocusService? focusService,
    DateTime Function()? clock,
  })  : _repository = repository,
        _progressService = progressService,
        _focusService = focusService,
        _clock = clock ?? DateTime.now;

  @override
  StatisticsSnapshot get currentSnapshot => _currentSnapshot;

  @override
  Stream<StatisticsSnapshot> get snapshotStream => _snapshotController.stream;

  @override
  Future<StatisticsSnapshot> initialize() => refresh();

  @override
  Future<StatisticsSnapshot> refresh() {
    return _enqueue(() async {
      if (_disposed) return _currentSnapshot;
      _emit(_currentSnapshot.copyWith(isLoading: true, clearError: true));

      final now = _clock().toLocal();
      try {
        final results = await Future.wait<Object?>([
          _repository.loadWorkoutStatistics(now: now),
          _repository.loadUnlockStatistics(now: now),
          _repository.loadAccessDurationStatistics(now: now),
          _repository.loadWeeklyActivity(now: now),
        ]);

        if (_disposed) return _currentSnapshot;

        final workouts = results[0] as WorkoutStatistics;
        final unlocks = results[1] as UnlockStatistics;
        final accessDuration = results[2] as AccessDurationStatistics;
        final weeklyActivity = results[3] as List<DailyActivityStats>;
        final progressState = _progressService.currentState;
        final focusState = _focusService?.currentState;

        if (progressState.errorMessage != null) {
          final failed = StatisticsSnapshot.initial(now: now).copyWith(
            generatedAt: now,
            progress: progressState,
            focus: focusState,
            isLoading: false,
            errorMessage: progressState.errorMessage,
          );
          _emit(failed);
          throw StateError(progressState.errorMessage!);
        }

        final snapshot = StatisticsSnapshot(
          generatedAt: now,
          workouts: workouts,
          unlocks: unlocks,
          accessDuration: accessDuration,
          weeklyActivity: weeklyActivity,
          progress: progressState,
          focus: focusState,
          isLoading: false,
          errorMessage: null,
        );
        _emit(snapshot);
        return snapshot;
      } catch (e) {
        if (_disposed) rethrow;
        final failed = StatisticsSnapshot.initial(now: now).copyWith(
          generatedAt: now,
          progress: _progressService.currentState,
          focus: _focusService?.currentState,
          isLoading: false,
          errorMessage: 'Failed to load statistics: $e',
        );
        _emit(failed);
        rethrow;
      }
    });
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

  void _emit(StatisticsSnapshot next) {
    _currentSnapshot = next;
    if (!_disposed && !_snapshotController.isClosed) {
      _snapshotController.add(next);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _snapshotController.close();
  }
}
