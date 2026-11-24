import '../../data/dashboard_data.dart';
import '../../data/repositories/access_attempt_repository.dart';
import '../../data/repositories/workout_history_repository.dart';

/// Production adapter generating [DashboardInsights] from local SQLite repositories.
///
/// Reads verified workout history and confirmed unlock records.
/// Honestly reports [todayUsageMinutes] and [totalXp] as null because Android
/// UsageStatsManager and Module 09 (XP & Progress Engine) are not implemented yet.
class CoreInsightsAdapter {
  final IWorkoutHistoryRepository _historyRepo;
  final IAccessAttemptRepository _accessRepo;

  CoreInsightsAdapter({
    required IWorkoutHistoryRepository historyRepo,
    required IAccessAttemptRepository accessRepo,
  })  : _historyRepo = historyRepo,
        _accessRepo = accessRepo;

  Future<DashboardInsights> loadInsights([Set<String>? packageIds]) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final sevenDaysAgo = startOfDay.subtract(const Duration(days: 7));

      final workouts = await _historyRepo.getWorkoutsByDateRange(sevenDaysAgo, now);
      final attempts = await _accessRepo.getRecentAttempts();

      final todayUnlocks = attempts
          .where((a) => a.isConfirmed && a.attemptedAt.isAfter(startOfDay))
          .length;

      final events = workouts.map((w) {
        return ActivityEntry(
          id: w.sessionId,
          kind: ActivityKind.movementCompleted,
          at: w.completedAt,
          appName: w.targetPackage,
          minutes: (w.accessDurationSeconds / 60).round(),
          xp: null, // Module 09 XP & Progress Engine not implemented yet
        );
      }).toList(growable: false);

      return DashboardInsights(
        todayUsageMinutes: null, // OS screen time honestly unavailable
        todayUnlocks: todayUnlocks,
        totalXp: null, // Module 09 XP & Progress Engine not implemented yet
        week: const [],
        events: events,
        usageByApp: const {},
        historyReady: true,
      );
    } catch (_) {
      return const DashboardInsights(historyReady: false);
    }
  }
}
