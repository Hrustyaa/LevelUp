import '../../core/errors/persistence_exceptions.dart';
import '../../features/challenge/data/challenge_catalog.dart';
import '../../models/challenge_type.dart';
import '../../models/exercise_type.dart';
import '../../models/workout_result.dart';
import '../database/database_constants.dart';
import '../database/levelup_database.dart';

/// Contract for persisting and querying verified workout history records.
abstract class IWorkoutHistoryRepository {
  /// Saves a verified workout outcome record to SQLite storage.
  ///
  /// Enforces idempotency:
  /// - If a record with the same [result.sessionId] already exists with identical
  ///   data, the operation succeeds idempotently without duplicate inserts.
  /// - If an existing record conflicts with the incoming payload, throws
  ///   [ConflictingWorkoutRecordException].
  ///
  /// Throws [InvalidWorkoutDataException] if payload invariants are violated.
  Future<void> saveCompletedWorkout(WorkoutResult result);

  /// Retrieves a workout result by its unique [sessionId], or null if not found.
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId);

  /// Retrieves recent workouts ordered by completion date descending, up to [limit].
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20});

  /// Retrieves workouts completed within the [start] and [end] timestamps (inclusive).
  Future<List<WorkoutResult>> getWorkoutsByDateRange(DateTime start, DateTime end);

  /// Returns total count of completed workouts in history.
  Future<int> countCompletedWorkouts();

  /// Returns total verified repetitions accumulated across all workouts,
  /// optionally filtered by [exerciseType].
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType});
}

/// Production SQLite implementation of [IWorkoutHistoryRepository].
class WorkoutHistoryRepository implements IWorkoutHistoryRepository {
  final LevelUpDatabase _dbManager;

  /// Creates a [WorkoutHistoryRepository] with dependency injection of [LevelUpDatabase].
  WorkoutHistoryRepository({
    LevelUpDatabase? databaseManager,
  }) : _dbManager = databaseManager ?? LevelUpDatabase();

  @override
  Future<void> saveCompletedWorkout(WorkoutResult result) async {
    _validateWorkoutResult(result);

    final db = await _dbManager.database;

    await db.transaction((txn) async {
      // Check if session ID already exists
      final existingRows = await txn.query(
        DatabaseConstants.tableWorkoutSessions,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: [result.sessionId],
        limit: 1,
      );

      if (existingRows.isNotEmpty) {
        final existing = _rowToWorkoutResult(existingRows.first);
        if (_isEquivalent(existing, result)) {
          return; // Idempotent duplicate: already stored accurately
        }
        throw ConflictingWorkoutRecordException(result.sessionId);
      }

      // Insert new record using parameterized values
      await txn.insert(
        DatabaseConstants.tableWorkoutSessions,
        {
          DatabaseConstants.colSessionId: result.sessionId,
          DatabaseConstants.colRequestId: result.requestId,
          DatabaseConstants.colChallengeId: result.challengeId,
          DatabaseConstants.colChallengeContext: result.challengeContext.name,
          DatabaseConstants.colExerciseType: result.exerciseType.name,
          DatabaseConstants.colTargetPackage: result.targetPackage,
          DatabaseConstants.colCompletedRepetitions: result.completedRepetitions,
          DatabaseConstants.colDurationSeconds: result.duration.inSeconds,
          DatabaseConstants.colCompletedAt:
              result.completedAt.toUtc().millisecondsSinceEpoch,
          DatabaseConstants.colVerificationSource: result.source,
        },
      );
    });
  }

  @override
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableWorkoutSessions,
      where: '${DatabaseConstants.colSessionId} = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return _rowToWorkoutResult(rows.first);
  }

  @override
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20}) async {
    if (limit <= 0) return const [];

    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableWorkoutSessions,
      orderBy: '${DatabaseConstants.colCompletedAt} DESC',
      limit: limit,
    );

    return rows.map(_rowToWorkoutResult).toList();
  }

  @override
  Future<List<WorkoutResult>> getWorkoutsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final startMs = start.toUtc().millisecondsSinceEpoch;
    final endMs = end.toUtc().millisecondsSinceEpoch;

    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableWorkoutSessions,
      where:
          '${DatabaseConstants.colCompletedAt} >= ? AND ${DatabaseConstants.colCompletedAt} <= ?',
      whereArgs: [startMs, endMs],
      orderBy: '${DatabaseConstants.colCompletedAt} ASC',
    );

    return rows.map(_rowToWorkoutResult).toList();
  }

  @override
  Future<int> countCompletedWorkouts() async {
    final db = await _dbManager.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as total FROM ${DatabaseConstants.tableWorkoutSessions}',
    );

    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType}) async {
    final db = await _dbManager.database;
    final List<Map<String, dynamic>> result;

    if (exerciseType != null) {
      result = await db.rawQuery(
        'SELECT SUM(${DatabaseConstants.colCompletedRepetitions}) as total '
        'FROM ${DatabaseConstants.tableWorkoutSessions} '
        'WHERE ${DatabaseConstants.colExerciseType} = ?',
        [exerciseType.name],
      );
    } else {
      result = await db.rawQuery(
        'SELECT SUM(${DatabaseConstants.colCompletedRepetitions}) as total '
        'FROM ${DatabaseConstants.tableWorkoutSessions}',
      );
    }

    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  void _validateWorkoutResult(WorkoutResult result) {
    if (result.sessionId.trim().isEmpty) {
      throw const InvalidWorkoutDataException('sessionId must not be empty.');
    }
    if (result.challengeId.trim().isEmpty) {
      throw const InvalidWorkoutDataException('challengeId must not be empty.');
    }
    if (result.completedRepetitions < 0) {
      throw InvalidWorkoutDataException(
        'completedRepetitions must not be negative: ${result.completedRepetitions}',
      );
    }
    if (result.duration.isNegative) {
      throw InvalidWorkoutDataException(
        'duration must not be negative: ${result.duration}',
      );
    }

    // Context & target invariants
    if (result.challengeContext == ChallengeType.freeWorkout) {
      if (result.targetPackage != null ||
          result.eligibleForAccess ||
          result.accessDurationSeconds != 0) {
        throw const InvalidWorkoutDataException(
          'Free workout must not have a target package or access authorization.',
        );
      }
    } else if (result.challengeContext == ChallengeType.unlockChallenge) {
      if (result.targetPackage == null || result.targetPackage!.trim().isEmpty) {
        throw const InvalidWorkoutDataException(
          'Unlock challenge must have a non-empty target package.',
        );
      }
    }
  }

  WorkoutResult _rowToWorkoutResult(Map<String, dynamic> row) {
    final contextName = row[DatabaseConstants.colChallengeContext] as String;
    final context = ChallengeType.values.byName(contextName);
    final isUnlock = context == ChallengeType.unlockChallenge;
    final challengeId = row[DatabaseConstants.colChallengeId] as String;
    final definition = ChallengeCatalog.byId[challengeId];

    return WorkoutResult(
      sessionId: row[DatabaseConstants.colSessionId] as String,
      requestId: (row[DatabaseConstants.colRequestId] as String?) ?? '',
      challengeId: challengeId,
      challengeContext: context,
      exerciseType: ExerciseType.values.byName(
        row[DatabaseConstants.colExerciseType] as String,
      ),
      targetPackage: row[DatabaseConstants.colTargetPackage] as String?,
      completedRepetitions:
          row[DatabaseConstants.colCompletedRepetitions] as int,
      duration: Duration(
        seconds: row[DatabaseConstants.colDurationSeconds] as int,
      ),
      completedAt: DateTime.fromMillisecondsSinceEpoch(
        row[DatabaseConstants.colCompletedAt] as int,
        isUtc: true,
      ),
      eligibleForAccess: isUnlock,
      accessDurationSeconds:
          isUnlock ? (definition?.accessDurationSeconds ?? 300) : 0,
      earnedXp: definition?.optionalXpReward ?? 50,
      source:
          (row[DatabaseConstants.colVerificationSource] as String?) ?? 'camera',
    );
  }

  bool _isEquivalent(WorkoutResult a, WorkoutResult b) {
    return a.sessionId == b.sessionId &&
        a.challengeId == b.challengeId &&
        a.challengeContext == b.challengeContext &&
        a.exerciseType == b.exerciseType &&
        a.targetPackage == b.targetPackage &&
        a.completedRepetitions == b.completedRepetitions &&
        a.duration.inSeconds == b.duration.inSeconds &&
        a.completedAt.toUtc().millisecondsSinceEpoch ==
            b.completedAt.toUtc().millisecondsSinceEpoch;
  }
}
