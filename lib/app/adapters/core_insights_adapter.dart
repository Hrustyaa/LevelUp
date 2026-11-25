import '../../core/constants/channel_constants.dart';
import '../../data/dashboard_data.dart';
import '../../data/repositories/access_attempt_repository.dart';
import '../../data/repositories/workout_history_repository.dart';
import '../../features/achievements/application/achievement_service.dart';
import '../../features/achievements/models/achievement_state.dart';
import '../../features/progress/application/progress_service.dart';
import '../../features/progress/application/xp_reward_policy.dart';
import '../../features/progress/models/level_info.dart';
import '../../features/progress/models/progress_state.dart';
import '../../features/progress/models/streak_info.dart';
import '../../features/progress/models/xp_reward_record.dart';
import '../../features/statistics/application/statistics_service.dart';
import '../../features/statistics/models/statistics_snapshot.dart';
import '../../models/access_attempt_record.dart';
import '../../models/challenge_type.dart';
import '../../models/exercise_type.dart';
import '../../models/workout_result.dart';

/// Production adapter generating [DashboardInsights] from local SQLite repositories
/// and the authoritative [IProgressService] (Module 09A).
///
/// Honestly reports [todayUsageMinutes] as null because Android UsageStatsManager
/// is not implemented yet.
class CoreInsightsAdapter {
  final IWorkoutHistoryRepository _historyRepo;
  final IAccessAttemptRepository _accessRepo;
  final IProgressService? _progressService;
  final IStatisticsService? _statisticsService;
  final IAchievementService? _achievementService;
  final DateTime Function() _clock;

  CoreInsightsAdapter({
    required IWorkoutHistoryRepository historyRepo,
    required IAccessAttemptRepository accessRepo,
    IProgressService? progressService,
    IStatisticsService? statisticsService,
    IAchievementService? achievementService,
    DateTime Function()? clock,
  })  : _historyRepo = historyRepo,
        _accessRepo = accessRepo,
        _progressService = progressService,
        _statisticsService = statisticsService,
        _achievementService = achievementService,
        _clock = clock ?? DateTime.now;

  Future<DashboardInsights> loadInsights([Set<String>? packageIds]) async {
    final now = _clock().toLocal();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final results = await Future.wait<Object?>([
      _historyRepo.getRecentWorkouts(limit: 50),
      _accessRepo.getRecentAttempts(limit: 50),
      if (_progressService != null) _progressService.refresh() else Future.value(null),
    ]);
    final rawWorkouts = results[0] as List<WorkoutResult>;
    final rawAttempts = results[1] as List<AccessAttemptRecord>;
    final progressState = results[2] as ProgressState?;

    StatisticsSnapshot? statisticsSnapshot;
    String? statisticsError;
    if (_statisticsService != null) {
      try {
        statisticsSnapshot = await _statisticsService.refresh();
      } catch (e) {
        statisticsError = '$e';
      }
    }

    AchievementState? achievementState;
    String? achievementsError;
    if (_achievementService != null) {
      try {
        achievementState = await _achievementService.evaluateAndRefresh();
      } catch (e) {
        achievementsError = '$e';
      }
    }

    // Deduplicate by sessionId to guarantee zero double-counting.
    final workoutsBySession = <String, WorkoutResult>{};
    final excludedSessions = <String>{};
    const rewardPolicy = XpRewardPolicy();
    for (final w in rawWorkouts) {
      if ((w.exerciseType == ExerciseType.pushUp && !rewardPolicy.evaluate(w).eligible) ||
          const {'simulated', 'preview', 'ui_only', 'mock'}.contains(w.source)) {
        excludedSessions.add(w.sessionId);
        continue;
      }
      workoutsBySession.putIfAbsent(w.sessionId, () => w);
    }

    final confirmedBySession = <String, AccessAttemptRecord>{};
    for (final a in rawAttempts) {
      if (a.isConfirmed && !excludedSessions.contains(a.sessionId)) {
        confirmedBySession.putIfAbsent(a.sessionId, () => a);
      }
    }

    final hasProgressError = progressState?.errorMessage != null;
    final List<XpRewardRecord> recentRewards =
        (progressState != null && !hasProgressError)
            ? progressState.recentRewards
            : const [];
    final rewardsBySession = <String, XpRewardRecord>{};
    for (final r in recentRewards) {
      rewardsBySession.putIfAbsent(r.sessionId, () => r);
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
      final rewardXp = rewardsBySession[w.sessionId]?.xpAmount;
      final exercise = w.exerciseType == ExerciseType.pushUp ? 'push-ups' : 'squats';

      if (confirmed != null) {
        events.add(
          ActivityEntry(
            id: w.sessionId,
            kind: ActivityKind.temporaryAccess,
            at: (confirmed.confirmedAt ?? confirmed.attemptedAt).toLocal(),
            appName: targetName,
            minutes: (confirmed.durationSeconds / 60).round(),
            detail: '${w.completedRepetitions} $exercise',
            xp: rewardXp,
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
            detail: '${w.completedRepetitions} $exercise',
            xp: rewardXp,
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
          xp: rewardsBySession[a.sessionId]?.xpAmount,
        ),
      );
    }

    events.sort((a, b) => b.at.compareTo(a.at));

    final int? totalXp;
    final LevelInfo? levelInfo;
    final StreakInfo? streakInfo;
    final int? completedWorkoutCount;

    if (progressState != null && !hasProgressError) {
      totalXp = progressState.totalXp;
      levelInfo = progressState.levelInfo;
      streakInfo = progressState.streakInfo;
      completedWorkoutCount = progressState.completedWorkoutCount;
    } else {
      totalXp = null;
      levelInfo = null;
      streakInfo = null;
      completedWorkoutCount = null;
    }

    return DashboardInsights(
      todayUsageMinutes: null, // OS screen time honestly unavailable
      todayUnlocks: statisticsSnapshot?.unlocks.todayConfirmed ?? todayUnlocks,
      todayWorkouts: statisticsSnapshot?.workouts.todayCompleted ?? todayWorkouts,
      totalXp: totalXp,
      levelInfo: levelInfo,
      streakInfo: streakInfo,
      completedWorkoutCount: completedWorkoutCount,
      recentRewards: recentRewards,
      progressError: progressState?.errorMessage,
      statistics: statisticsSnapshot,
      statisticsError: statisticsError ?? statisticsSnapshot?.errorMessage,
      achievements: achievementState,
      achievementsError: achievementsError ?? achievementState?.errorMessage,
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
