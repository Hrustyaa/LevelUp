import '../../../data/database/database_constants.dart';
import '../../../data/database/levelup_database.dart';
import '../application/statistics_calendar.dart';
import '../models/access_duration_statistics.dart';
import '../models/daily_activity_stats.dart';
import '../models/unlock_statistics.dart';
import '../models/workout_statistics.dart';

/// Contract for read-only aggregate statistics queries over persisted data.
abstract class IStatisticsRepository {
  Future<WorkoutStatistics> loadWorkoutStatistics({required DateTime now});

  Future<UnlockStatistics> loadUnlockStatistics({required DateTime now});

  Future<AccessDurationStatistics> loadAccessDurationStatistics({
    required DateTime now,
  });

  Future<List<DailyActivityStats>> loadWeeklyActivity({required DateTime now});
}

/// SQLite-backed read-only implementation of [IStatisticsRepository].
///
/// Uses SQLite `COUNT(DISTINCT session_id)` and `SUM(...)` aggregates with
/// inclusive-start / exclusive-end UTC millisecond bounds derived from
/// [StatisticsCalendar] so all-time totals are never truncated by `limit: 50`
/// and lifetime rows are never loaded into Dart memory.
class SqliteStatisticsRepository implements IStatisticsRepository {
  final LevelUpDatabase _dbManager;

  SqliteStatisticsRepository({LevelUpDatabase? databaseManager})
      : _dbManager = databaseManager ?? LevelUpDatabase();

  static const String _trustedWorkoutFilter =
      "(${DatabaseConstants.colVerificationSource} IS NULL OR "
      "${DatabaseConstants.colVerificationSource} NOT IN ('simulated', 'preview', 'ui_only', 'mock'))";

  @override
  Future<WorkoutStatistics> loadWorkoutStatistics({
    required DateTime now,
  }) async {
    final day = StatisticsCalendar.localDayRange(now);
    final week = StatisticsCalendar.currentWeekRange(now);

    final db = await _dbManager.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT ${DatabaseConstants.colSessionId}) AS all_time_completed,
        COUNT(DISTINCT CASE
          WHEN ${DatabaseConstants.colCompletedAt} >= ?
           AND ${DatabaseConstants.colCompletedAt} < ?
          THEN ${DatabaseConstants.colSessionId}
        END) AS today_completed,
        COUNT(DISTINCT CASE
          WHEN ${DatabaseConstants.colCompletedAt} >= ?
           AND ${DatabaseConstants.colCompletedAt} < ?
          THEN ${DatabaseConstants.colSessionId}
        END) AS week_completed,
        COALESCE(SUM(CASE
          WHEN ${DatabaseConstants.colExerciseType} = 'squats'
          THEN ${DatabaseConstants.colCompletedRepetitions}
          ELSE 0
        END), 0) AS total_reps,
        COUNT(DISTINCT CASE
          WHEN ${DatabaseConstants.colChallengeContext} = 'unlockChallenge'
          THEN ${DatabaseConstants.colSessionId}
        END) AS unlock_challenges,
        COUNT(DISTINCT CASE
          WHEN ${DatabaseConstants.colChallengeContext} = 'freeWorkout'
          THEN ${DatabaseConstants.colSessionId}
        END) AS free_workouts
      FROM ${DatabaseConstants.tableWorkoutSessions}
      WHERE $_trustedWorkoutFilter
      ''',
      [
        day.startUtcMs,
        day.endUtcMs,
        week.startUtcMs,
        week.endUtcMs,
      ],
    );

    if (rows.isEmpty) return WorkoutStatistics.empty;
    final row = rows.first;
    return WorkoutStatistics(
      allTimeCompleted: _asInt(row['all_time_completed']),
      todayCompleted: _asInt(row['today_completed']),
      thisWeekCompleted: _asInt(row['week_completed']),
      totalVerifiedRepetitions: _asInt(row['total_reps']),
      unlockChallengesCompleted: _asInt(row['unlock_challenges']),
      freeWorkoutsCompleted: _asInt(row['free_workouts']),
    );
  }

  @override
  Future<UnlockStatistics> loadUnlockStatistics({
    required DateTime now,
  }) async {
    final day = StatisticsCalendar.localDayRange(now);
    final week = StatisticsCalendar.currentWeekRange(now);

    const effectiveTs =
        'COALESCE(${DatabaseConstants.colConfirmedAt}, ${DatabaseConstants.colAttemptedAt})';

    final db = await _dbManager.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT CASE
          WHEN $effectiveTs >= ? AND $effectiveTs < ?
          THEN ${DatabaseConstants.colSessionId}
        END) AS today_confirmed,
        COUNT(DISTINCT CASE
          WHEN $effectiveTs >= ? AND $effectiveTs < ?
          THEN ${DatabaseConstants.colSessionId}
        END) AS week_confirmed,
        COUNT(DISTINCT ${DatabaseConstants.colSessionId}) AS all_time_confirmed
      FROM ${DatabaseConstants.tableAccessAttempts}
      WHERE ${DatabaseConstants.colState} = 'confirmed'
      ''',
      [
        day.startUtcMs,
        day.endUtcMs,
        week.startUtcMs,
        week.endUtcMs,
      ],
    );

    if (rows.isEmpty) return UnlockStatistics.empty;
    final row = rows.first;
    return UnlockStatistics(
      todayConfirmed: _asInt(row['today_confirmed']),
      thisWeekConfirmed: _asInt(row['week_confirmed']),
      allTimeConfirmed: _asInt(row['all_time_confirmed']),
    );
  }

  @override
  Future<AccessDurationStatistics> loadAccessDurationStatistics({
    required DateTime now,
  }) async {
    final day = StatisticsCalendar.localDayRange(now);
    const effectiveTs =
        'COALESCE(${DatabaseConstants.colConfirmedAt}, ${DatabaseConstants.colAttemptedAt})';

    final db = await _dbManager.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(${DatabaseConstants.colDurationSeconds}), 0) AS total_seconds,
        COALESCE(SUM(CASE
          WHEN $effectiveTs >= ? AND $effectiveTs < ?
          THEN ${DatabaseConstants.colDurationSeconds}
          ELSE 0
        END), 0) AS today_seconds,
        COUNT(DISTINCT ${DatabaseConstants.colSessionId}) AS confirmed_count
      FROM ${DatabaseConstants.tableAccessAttempts}
      WHERE ${DatabaseConstants.colState} = 'confirmed'
      ''',
      [
        day.startUtcMs,
        day.endUtcMs,
      ],
    );

    if (rows.isEmpty) return AccessDurationStatistics.empty;
    final row = rows.first;
    final totalSeconds = _asInt(row['total_seconds']);
    final todaySeconds = _asInt(row['today_seconds']);
    final confirmedCount = _asInt(row['confirmed_count']);

    return AccessDurationStatistics(
      totalAuthorizedDuration: Duration(seconds: totalSeconds),
      todayAuthorizedDuration: Duration(seconds: todaySeconds),
      averageAuthorizedDuration: confirmedCount > 0
          ? Duration(seconds: (totalSeconds / confirmedCount).round())
          : null,
    );
  }

  @override
  Future<List<DailyActivityStats>> loadWeeklyActivity({
    required DateTime now,
  }) async {
    final range = StatisticsCalendar.last7DaysRange(now);
    final days = StatisticsCalendar.last7LocalDays(now);
    const effectiveTs =
        'COALESCE(${DatabaseConstants.colConfirmedAt}, ${DatabaseConstants.colAttemptedAt})';

    final db = await _dbManager.database;
    final results = await Future.wait([
      db.rawQuery(
        '''
        SELECT
          ${DatabaseConstants.colSessionId},
          ${DatabaseConstants.colCompletedAt},
          ${DatabaseConstants.colExerciseType},
          ${DatabaseConstants.colCompletedRepetitions}
        FROM ${DatabaseConstants.tableWorkoutSessions}
        WHERE ${DatabaseConstants.colCompletedAt} >= ?
          AND ${DatabaseConstants.colCompletedAt} < ?
          AND $_trustedWorkoutFilter
        ''',
        [range.startUtcMs, range.endUtcMs],
      ),
      db.rawQuery(
        '''
        SELECT
          ${DatabaseConstants.colSessionId},
          $effectiveTs AS effective_at
        FROM ${DatabaseConstants.tableAccessAttempts}
        WHERE ${DatabaseConstants.colState} = 'confirmed'
          AND $effectiveTs >= ?
          AND $effectiveTs < ?
        ''',
        [range.startUtcMs, range.endUtcMs],
      ),
    ]);

    final workoutRows = results[0];
    final unlockRows = results[1];

    final workoutCounts = <String, int>{};
    final repCounts = <String, int>{};
    final seenWorkouts = <String>{};

    for (final row in workoutRows) {
      final sessionId = row[DatabaseConstants.colSessionId] as String;
      if (!seenWorkouts.add(sessionId)) continue;
      final completedAtMs = _asInt(row[DatabaseConstants.colCompletedAt]);
      final localDate = DateTime.fromMillisecondsSinceEpoch(
        completedAtMs,
        isUtc: true,
      ).toLocal();
      final key = StatisticsCalendar.formatLocalDate(localDate);
      workoutCounts[key] = (workoutCounts[key] ?? 0) + 1;
      if (row[DatabaseConstants.colExerciseType] == 'squats') {
        final reps = _asInt(row[DatabaseConstants.colCompletedRepetitions]);
        repCounts[key] = (repCounts[key] ?? 0) + reps;
      }
    }

    final unlockCounts = <String, int>{};
    final seenUnlocks = <String>{};

    for (final row in unlockRows) {
      final sessionId = row[DatabaseConstants.colSessionId] as String;
      if (!seenUnlocks.add(sessionId)) continue;
      final effectiveAtMs = _asInt(row['effective_at']);
      final localDate = DateTime.fromMillisecondsSinceEpoch(
        effectiveAtMs,
        isUtc: true,
      ).toLocal();
      final key = StatisticsCalendar.formatLocalDate(localDate);
      unlockCounts[key] = (unlockCounts[key] ?? 0) + 1;
    }

    return days.map((day) {
      final key = StatisticsCalendar.formatLocalDate(day);
      return DailyActivityStats(
        localDate: day,
        dateKey: key,
        completedWorkouts: workoutCounts[key] ?? 0,
        confirmedUnlocks: unlockCounts[key] ?? 0,
        verifiedRepetitions: repCounts[key] ?? 0,
      );
    }).toList(growable: false);
  }

  static int _asInt(Object? value) => (value as num?)?.toInt() ?? 0;
}
