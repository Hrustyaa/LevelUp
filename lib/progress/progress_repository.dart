import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/android_usage_gateway.dart';
import '../data/levelup_permissions.dart';
import '../data/repositories/workout_history_repository.dart';
import '../features/progress/application/xp_reward_policy.dart';
import '../models/exercise_type.dart';
import '../models/workout_result.dart' as core;
import '../free_workout/workout_history.dart';
import '../free_workout/workout_session.dart';
import 'progress_models.dart';

enum FocusUsageStatus {
  needsSelection,
  permissionDenied,
  unavailable,
  noData,
  ready,
}

class FocusUsageRead {
  const FocusUsageRead(this.status) : snapshot = null;
  const FocusUsageRead.ready(FocusUsageSnapshot data)
    : status = FocusUsageStatus.ready,
      snapshot = data;

  final FocusUsageStatus status;
  final FocusUsageSnapshot? snapshot;
}

typedef WorkoutHistoryPageData = ({List<WorkoutResult> workouts, bool hasMore});
typedef WorkoutHistoryLoader =
    Future<WorkoutHistoryPageData> Function(int limit);

abstract class ProgressRepository {
  Future<List<WorkoutResult>> loadWorkouts();
  Future<FocusUsageRead> loadFocusUsage(Set<String> packageIds, DateTime now);
}

class LocalProgressRepository implements ProgressRepository {
  const LocalProgressRepository({this.history});

  final IWorkoutHistoryRepository? history;

  @override
  Future<List<WorkoutResult>> loadWorkouts() async {
    final repository = history;
    if (repository == null) {
      return WorkoutHistory(await SharedPreferences.getInstance()).all();
    }
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, now.day - 29);
    final results = await repository.getWorkoutsByDateRange(firstDay, now);
    return _verifiedWorkouts(results);
  }

  WorkoutHistoryLoader? get historyLoader =>
      history == null ? null : _loadHistory;

  Future<WorkoutHistoryPageData> _loadHistory(int limit) async {
    final results = await history!.getRecentWorkouts(limit: limit + 1);
    return (
      workouts: _verifiedWorkouts(results.take(limit)),
      hasMore: results.length > limit,
    );
  }

  List<WorkoutResult> _verifiedWorkouts(Iterable<core.WorkoutResult> results) {
    const policy = XpRewardPolicy();
    return [
      for (final result in results)
        if (policy.evaluatePersistedWorkout(result).eligible)
          WorkoutResult(
            exercise: result.exerciseType == ExerciseType.pushUp
                ? 'push_up'
                : 'squat',
            startedAt: result.completedAt.subtract(result.duration),
            endedAt: result.completedAt,
            sets: [result.completedRepetitions],
          ),
    ];
  }

  @override
  Future<FocusUsageRead> loadFocusUsage(
    Set<String> packageIds,
    DateTime now,
  ) async {
    if (packageIds.isEmpty) {
      return const FocusUsageRead(FocusUsageStatus.needsSelection);
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const FocusUsageRead(FocusUsageStatus.unavailable);
    }
    Map<String, Object?>? raw;
    try {
      raw = await const AndroidUsageGateway().readUsageData(packageIds);
    } on MissingPluginException {
      return const FocusUsageRead(FocusUsageStatus.unavailable);
    }
    if (raw == null) {
      try {
        final permissions = await const AndroidPermissionGateway().read();
        if (permissions[LevelUpPermission.usage] == PermissionState.denied) {
          return const FocusUsageRead(FocusUsageStatus.permissionDenied);
        }
        if (permissions[LevelUpPermission.usage] ==
            PermissionState.unavailable) {
          return const FocusUsageRead(FocusUsageStatus.unavailable);
        }
      } on MissingPluginException {
        // The usage channel can exist without a separate permission-status bridge.
      }
      return const FocusUsageRead(FocusUsageStatus.noData);
    }
    if (raw['week'] is! List) throw const FormatException('Missing usage week');
    final snapshot = FocusUsageSnapshot.fromNative(raw, now: now);
    return snapshot.observedDays == 0
        ? const FocusUsageRead(FocusUsageStatus.noData)
        : FocusUsageRead.ready(snapshot);
  }
}
