import '../../core/constants/channel_constants.dart';
import '../../data/dashboard_data.dart';
import '../../data/repositories/access_attempt_repository.dart';
import '../../data/repositories/workout_history_repository.dart';
import '../../models/access_attempt_record.dart';
import '../../models/challenge_type.dart';
import '../../models/workout_result.dart';

/// Production adapter generating [DashboardInsights] from local SQLite repositories.
///
/// Reads verified workout history and confirmed unlock records.
/// Honestly reports [todayUsageMinutes] and [totalXp] as null because Android
/// UsageStatsManager and Module 09 (XP & Progress Engine) are not implemented yet.
class CoreInsightsAdapter {
  final IWorkoutHistoryRepository _historyRepo;
  final IAccessAttemptRepository _accessRepo;
  final DateTime Function() _clock;

  CoreInsightsAdapter({
    required IWorkoutHistoryRepository historyRepo,
    required IAccessAttemptRepository accessRepo,
    DateTime Function()? clock,
  })  : _historyRepo = historyRepo,
        _accessRepo = accessRepo,
        _clock = clock ?? DateTime.now;

  Future<DashboardInsights> loadInsights([Set<String>? packageIds]) async {
    final now = _clock().toLocal();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final results = await Future.wait<Object>([
      _historyRepo.getRecentWorkouts(limit: 50),
      _accessRepo.getRecentAttempts(limit: 50),
    ]);
    final rawWorkouts = results[0] as List<WorkoutResult>;
    final rawAttempts = results[1] as List<AccessAttemptRecord>;

    // Deduplicate by sessionId to guarantee zero double-counting.
    final workoutsBySession = <String, WorkoutResult>{};
    for (final w in rawWorkouts) {
      workoutsBySession.putIfAbsent(w.sessionId, () => w);
    }

    final confirmedBySession = <String, AccessAttemptRecord>{};
    for (final a in rawAttempts) {
      if (a.isConfirmed) {
        confirmedBySession.putIfAbsent(a.sessionId, () => a);
      }
    }

    bool isToday(DateTime dt) {
      final local = dt.toLocal();
      return !local.isBefore(startOfDay) && local.isBefore(endOfDay);
    }

    final todayUnlocks = confirmedBySession.values
        .where((a) => isToday(a.confirmedAt ?? a.attemptedAt))
        .length;

    final todayWorkouts = workoutsBySession.values
        .where((w) => isToday(w.completedAt))
        .length;

    final events = <ActivityEntry>[];
    final includedSessions = <String>{};

    for (final w in workoutsBySession.values) {
      includedSessions.add(w.sessionId);
      final targetName = _displayName(w.targetPackage);
      final confirmed = w.challengeContext == ChallengeType.unlockChallenge
          ? confirmedBySession[w.sessionId]
          : null;

      if (confirmed != null) {
        events.add(
          ActivityEntry(
            id: w.sessionId,
            kind: ActivityKind.temporaryAccess,
            at: (confirmed.confirmedAt ?? confirmed.attemptedAt).toLocal(),
            appName: targetName,
            minutes: (confirmed.durationSeconds / 60).round(),
            detail: '${w.completedRepetitions} squats',
            xp: null, // Module 09 XP & Progress Engine not implemented yet
          ),
        );
      } else {
        events.add(
          ActivityEntry(
            id: w.sessionId,
            kind: ActivityKind.movementCompleted,
            at: w.completedAt.toLocal(),
            appName: w.challengeContext == ChallengeType.unlockChallenge
                ? targetName
                : null,
            minutes: null,
            detail: '${w.completedRepetitions} squats',
            xp: null, // Module 09 XP & Progress Engine not implemented yet
          ),
        );
      }
    }

    // Include any confirmed unlock record whose workout row is outside the recent window.
    for (final a in confirmedBySession.values) {
      if (includedSessions.contains(a.sessionId)) continue;
      events.add(
        ActivityEntry(
          id: a.sessionId,
          kind: ActivityKind.temporaryAccess,
          at: (a.confirmedAt ?? a.attemptedAt).toLocal(),
          appName: _displayName(a.targetPackage),
          minutes: (a.durationSeconds / 60).round(),
          xp: null,
        ),
      );
    }

    events.sort((a, b) => b.at.compareTo(a.at));

    return DashboardInsights(
      todayUsageMinutes: null, // OS screen time honestly unavailable
      todayUnlocks: todayUnlocks,
      todayWorkouts: todayWorkouts,
      totalXp: null, // Module 09 XP & Progress Engine not implemented yet
      week: const [],
      events: events,
      usageByApp: const {},
      historyReady: true,
    );
  }

  static String? _displayName(String? packageId) {
    if (packageId == null || packageId.isEmpty) return null;
    return ChannelConstants.targetDisplayNames[packageId] ?? packageId;
  }
}
