import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../features/achievements/models/achievement_state.dart';
import '../features/progress/models/level_info.dart';
import '../features/progress/models/streak_info.dart';
import '../features/progress/models/xp_reward_record.dart';
import '../features/statistics/models/statistics_snapshot.dart';
import 'levelup_permissions.dart';

enum DashboardLanguage { en, ru, kk }

enum DashboardTab { home, focus, challenge, progress, settings }

enum ActivityKind {
  focusOn,
  focusOff,
  temporaryAccess,
  breakCompleted,
  movementCompleted,
}

@immutable
class DashboardApp {
  const DashboardApp(this.id, this.name, {this.icon});
  final String id, name;
  final Uint8List? icon;
}

@immutable
class FocusSnapshot {
  const FocusSnapshot({
    required this.enabled,
    required this.serviceEnabled,
    this.targets = const [],
    this.accessUntil = const {},
  });
  final bool enabled, serviceEnabled;
  final List<String> targets;

  /// Actual absolute deadlines from the engine, never a UI countdown source.
  final Map<String, DateTime> accessUntil;
  bool get active => enabled && serviceEnabled;
  Duration remaining(String id, DateTime now) {
    final d = accessUntil[id]?.difference(now) ?? Duration.zero;
    return active && targets.contains(id) && d > Duration.zero
        ? d
        : Duration.zero;
  }
}

abstract class DashboardFocusGateway {
  Future<FocusSnapshot> read();
  Future<void> enable({String? target});
  Future<void> disable();
}

class FocusChallengeRequest {
  const FocusChallengeRequest({required this.id, required this.target});

  final String id;
  final String target;
}

/// Adapter for the existing SINGLE-target test kernel. No automatic activation,
/// exercise requirement, pause simulation or writes to native preferences.
class ExistingFocusGateway implements DashboardFocusGateway {
  const ExistingFocusGateway({this.notificationLanguage});

  final DashboardLanguage? notificationLanguage;
  static const channel = MethodChannel('levelup_test/control');
  static const _notifications = MethodChannel('levelup/focus_notifications');
  @override
  Future<FocusSnapshot> read() async {
    final m = await channel.invokeMapMethod<String, dynamic>('getState');
    if (m == null || m['enabled'] is! bool || m['serviceEnabled'] is! bool) {
      throw StateError('Unknown engine state');
    }
    final target = m['target'];
    final expiry = m['unlockUntil'];
    final ids = target is String && target.isNotEmpty ? [target] : <String>[];
    return FocusSnapshot(
      enabled: m['enabled'] as bool,
      serviceEnabled: m['serviceEnabled'] as bool,
      targets: ids,
      accessUntil: {
        if (ids.isNotEmpty && expiry is int && expiry > 0)
          ids.first: DateTime.fromMillisecondsSinceEpoch(expiry),
      },
    );
  }

  Future<FocusChallengeRequest?> claimChallenge() async {
    if (!await const AndroidPermissionGateway().isAvailable()) return null;
    try {
      final response = await channel.invokeMethod<Object?>(
        'consumeChallengeRequest',
      );
      if (response case {'id': final String id, 'target': final String target}
          when id.isNotEmpty && target.isNotEmpty) {
        return FocusChallengeRequest(id: id, target: target);
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> cancelChallenge(FocusChallengeRequest request) async {
    await channel.invokeMethod<bool>('cancelChallenge', {'id': request.id});
  }

  Future<DateTime> completeChallenge(
    FocusChallengeRequest request,
    int repetitions,
  ) async {
    final deadline = await channel.invokeMethod<int>('grantAccess', {
      'id': request.id,
      'target': request.target,
      'repetitions': repetitions,
    });
    if (deadline == null) {
      throw StateError('No Focus access deadline returned');
    }
    return DateTime.fromMillisecondsSinceEpoch(deadline);
  }

  @override
  Future<void> enable({String? target}) async {
    if (target != null && target.isNotEmpty) {
      final targetOk = await channel.invokeMethod<bool>('setTarget', {
        'target': target,
      });
      if (targetOk != true) {
        throw StateError('Failed to configure focus target package');
      }
    }
    await _setEnabled(true);
  }

  @override
  Future<void> disable() => _setEnabled(false);

  Future<void> _setEnabled(bool enabled) async {
    final language = notificationLanguage;
    final previous = language == null ? null : _readActive();
    final ok = await channel.invokeMethod<bool>('setEnabled', {
      'enabled': enabled,
    });
    if (ok != true) throw StateError('Focus change was not confirmed');
    if (language != null && previous != null) {
      unawaited(_notifyChange(previous, enabled, language));
    }
  }

  Future<bool?> _readActive() async {
    try {
      return (await read().timeout(const Duration(seconds: 2))).active;
    } catch (_) {
      return null;
    }
  }

  Future<void> _notifyChange(
    Future<bool?> previous,
    bool enabled,
    DashboardLanguage language,
  ) async {
    final wasActive = await previous;
    if (wasActive == null || wasActive == enabled) return;
    try {
      await _notifications.invokeMethod<void>('postManualChange', {
        'enabled': enabled,
        'language': language.name,
      });
    } catch (_) {
      // Focus has already changed even when notification delivery fails.
    }
  }
}

@immutable
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.kind,
    required this.at,
    this.appName,
    this.minutes,
    this.xp,
    this.detail,
  });
  final String id;
  final ActivityKind kind;
  final DateTime at;
  final String? appName, detail;
  final int? minutes, xp;
}

@immutable
class UsageDay {
  const UsageDay(this.date, this.minutes);
  final DateTime date;
  final int minutes;
}

@immutable
class DashboardInsights {
  const DashboardInsights({
    this.todayUsageMinutes,
    this.todayUnlocks,
    this.todayWorkouts,
    this.totalXp,
    this.levelInfo,
    this.streakInfo,
    this.completedWorkoutCount,
    this.recentRewards = const [],
    this.progressError,
    this.statistics,
    this.statisticsError,
    this.achievements,
    this.achievementsError,
    this.week = const [],
    this.events = const [],
    this.usageByApp = const {},
    this.historyReady = false,
  });

  /// null means unknown/unavailable, not zero. No estimated savings.
  final int? todayUsageMinutes, todayUnlocks, todayWorkouts, totalXp;
  final LevelInfo? levelInfo;
  final StreakInfo? streakInfo;
  final int? completedWorkoutCount;
  final List<XpRewardRecord> recentRewards;
  final String? progressError;
  final StatisticsSnapshot? statistics;
  final String? statisticsError;
  final AchievementState? achievements;
  final String? achievementsError;
  final List<UsageDay> week;
  final List<ActivityEntry> events;
  final Map<String, int> usageByApp;
  final bool historyReady;
}

/// Agreed cumulative thresholds: 0,100,300,600,1000,...
@immutable
class DashboardLevel {
  const DashboardLevel(this.level, this.floor, this.next, this.xp);
  final int level, floor, next, xp;
  static DashboardLevel fromXp(int total) {
    final xp = total < 0 ? 0 : total;
    var level = 1;
    while (50 * level * (level + 1) <= xp) {
      level++;
    }
    return DashboardLevel(
      level,
      50 * (level - 1) * level,
      50 * level * (level + 1),
      xp,
    );
  }

  double get fraction => (xp - floor) / (next - floor);
  int get remaining => next - xp;
}
