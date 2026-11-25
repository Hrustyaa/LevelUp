import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/android_usage_gateway.dart';
import '../data/levelup_permissions.dart';
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

abstract class ProgressRepository {
  Future<List<WorkoutResult>> loadWorkouts();
  Future<FocusUsageRead> loadFocusUsage(Set<String> packageIds, DateTime now);
}

class LocalProgressRepository implements ProgressRepository {
  const LocalProgressRepository();

  @override
  Future<List<WorkoutResult>> loadWorkouts() async =>
      WorkoutHistory(await SharedPreferences.getInstance()).all();

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
