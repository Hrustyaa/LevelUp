import 'package:sqflite/sqflite.dart';

import '../../core/constants/channel_constants.dart';
import '../../core/errors/persistence_exceptions.dart';
import '../../models/access_attempt_record.dart';
import '../../models/access_attempt_state.dart';
import '../database/database_constants.dart';
import '../database/levelup_database.dart';

/// Contract for managing the access attempt audit journal.
abstract class IAccessAttemptRepository {
  /// Records a new access attempt in [AccessAttemptState.prepared] state if absent.
  /// If an attempt for [sessionId] already exists, returns the existing record without overwriting.
  ///
  /// Throws [InvalidWorkoutDataException] if parameters are invalid.
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  });

  /// Retrieves an access attempt record by [sessionId], or null if not found.
  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId);

  /// Transitions an attempt to [AccessAttemptState.confirmed] upon authoritative platform confirmation.
  ///
  /// Throws [RecordNotFoundException] if the session ID does not exist.
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  });

  /// Transitions an attempt to [AccessAttemptState.uncertain] following an unconfirmed platform or IPC error.
  ///
  /// Safe Invariant: A previously [AccessAttemptState.confirmed] attempt is never downgraded.
  /// Throws [RecordNotFoundException] if the session ID does not exist.
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  });

  /// Transitions an attempt to [AccessAttemptState.definitivelyRejected] before native invocation.
  ///
  /// Safe Invariant: A previously [AccessAttemptState.confirmed] attempt is never downgraded.
  /// Throws [RecordNotFoundException] if the session ID does not exist.
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  });

  /// Retrieves recent access attempts ordered by attempt date descending, up to [limit].
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50});
}

/// Production SQLite implementation of [IAccessAttemptRepository].
class AccessAttemptRepository implements IAccessAttemptRepository {
  final LevelUpDatabase _dbManager;

  /// Creates an [AccessAttemptRepository] with dependency injection of [LevelUpDatabase].
  AccessAttemptRepository({
    LevelUpDatabase? databaseManager,
  }) : _dbManager = databaseManager ?? LevelUpDatabase();

  @override
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  }) async {
    _validateAttemptInput(sessionId, targetPackage, durationSeconds);

    final db = await _dbManager.database;

    return db.transaction((txn) async {
      final existingRows = await txn.query(
        DatabaseConstants.tableAccessAttempts,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      if (existingRows.isNotEmpty) {
        final existing = AccessAttemptRecord.fromMap(existingRows.first);

        // Detect conflicting payloads for the same session
        if (existing.targetPackage != targetPackage ||
            existing.durationSeconds != durationSeconds) {
          throw ConflictingAccessAttemptException(
            sessionId,
            message:
                'Access attempt for session "$sessionId" already exists with '
                'different payload (targetPackage: ${existing.targetPackage} vs $targetPackage, '
                'durationSeconds: ${existing.durationSeconds} vs $durationSeconds).',
          );
        }

        return existing;
      }

      final record = AccessAttemptRecord(
        sessionId: sessionId,
        targetPackage: targetPackage,
        durationSeconds: durationSeconds,
        state: AccessAttemptState.prepared,
        attemptedAt: attemptedAt,
      );

      await txn.insert(
        DatabaseConstants.tableAccessAttempts,
        record.toMap(),
      );

      return record;
    });
  }

  @override
  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableAccessAttempts,
      where: '${DatabaseConstants.colSessionId} = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return AccessAttemptRecord.fromMap(rows.first);
  }

  @override
  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  }) async {
    final db = await _dbManager.database;

    return db.transaction((txn) async {
      final existing = await _requireAttempt(txn, sessionId);

      // Cannot confirm an attempt that was definitively rejected pre-invocation
      if (existing.state == AccessAttemptState.definitivelyRejected) {
        throw InvalidStateTransitionException(
          sessionId: sessionId,
          from: existing.state,
          to: AccessAttemptState.confirmed,
          message:
              'Cannot transition from definitivelyRejected to confirmed: '
              'a request rejected before native invocation cannot be confirmed.',
        );
      }

      // Idempotent duplicate confirmation
      if (existing.state == AccessAttemptState.confirmed &&
          existing.confirmedAt == confirmedAt &&
          existing.unlockUntil == unlockUntil) {
        return existing;
      }

      final updated = existing.copyWith(
        state: AccessAttemptState.confirmed,
        confirmedAt: confirmedAt,
        unlockUntil: unlockUntil,
      );

      await txn.update(
        DatabaseConstants.tableAccessAttempts,
        updated.toMap(),
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: [sessionId],
      );

      return updated;
    });
  }

  @override
  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  }) async {
    final db = await _dbManager.database;

    return db.transaction((txn) async {
      final existing = await _requireAttempt(txn, sessionId);

      // Never downgrade an already confirmed grant
      if (existing.state == AccessAttemptState.confirmed) {
        return existing;
      }

      // Cannot mark as uncertain after definitive pre-invocation rejection
      if (existing.state == AccessAttemptState.definitivelyRejected) {
        throw InvalidStateTransitionException(
          sessionId: sessionId,
          from: existing.state,
          to: AccessAttemptState.uncertain,
          message:
              'Cannot transition from definitivelyRejected to uncertain: '
              'a request rejected before native invocation cannot become uncertain.',
        );
      }

      // Idempotent duplicate transition
      if (existing.state == AccessAttemptState.uncertain &&
          existing.failureReason == reason) {
        return existing;
      }

      final updated = existing.copyWith(
        state: AccessAttemptState.uncertain,
        failureReason: reason,
      );

      await txn.update(
        DatabaseConstants.tableAccessAttempts,
        updated.toMap(),
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: [sessionId],
      );

      return updated;
    });
  }

  @override
  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  }) async {
    final db = await _dbManager.database;

    return db.transaction((txn) async {
      final existing = await _requireAttempt(txn, sessionId);

      // Never downgrade an already confirmed grant
      if (existing.state == AccessAttemptState.confirmed) {
        return existing;
      }

      // Cannot definitively reject after uncertain native invocation:
      // "uncertain" means native may or may not have granted access,
      // so we cannot claim it was definitively rejected pre-invocation.
      if (existing.state == AccessAttemptState.uncertain) {
        throw InvalidStateTransitionException(
          sessionId: sessionId,
          from: existing.state,
          to: AccessAttemptState.definitivelyRejected,
          message:
              'Cannot transition from uncertain to definitivelyRejected: '
              'uncertain means native may have executed; use markConfirmed or leave as uncertain.',
        );
      }

      // Idempotent duplicate transition
      if (existing.state == AccessAttemptState.definitivelyRejected &&
          existing.failureReason == reason) {
        return existing;
      }

      final updated = existing.copyWith(
        state: AccessAttemptState.definitivelyRejected,
        failureReason: reason,
      );

      await txn.update(
        DatabaseConstants.tableAccessAttempts,
        updated.toMap(),
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: [sessionId],
      );

      return updated;
    });
  }

  @override
  Future<List<AccessAttemptRecord>> getRecentAttempts({int limit = 50}) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableAccessAttempts,
      orderBy: '${DatabaseConstants.colAttemptedAt} DESC',
      limit: limit,
    );
    return rows.map((r) => AccessAttemptRecord.fromMap(r)).toList();
  }

  Future<AccessAttemptRecord> _requireAttempt(DatabaseExecutor executor, String sessionId) async {
    final rows = await executor.query(
      DatabaseConstants.tableAccessAttempts,
      where: '${DatabaseConstants.colSessionId} = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw RecordNotFoundException(
        sessionId,
        message: 'No access attempt record found for session "$sessionId".',
      );
    }

    return AccessAttemptRecord.fromMap(rows.first);
  }

  void _validateAttemptInput(String sessionId, String targetPackage, int durationSeconds) {
    if (sessionId.trim().isEmpty) {
      throw const InvalidWorkoutDataException('sessionId must not be empty.');
    }
    if (targetPackage.trim().isEmpty) {
      throw const InvalidWorkoutDataException('targetPackage must not be empty.');
    }
    if (!ChannelConstants.allowedTargets.contains(targetPackage)) {
      throw InvalidWorkoutDataException(
        'targetPackage "$targetPackage" is not in the allowed targets set.',
      );
    }
    if (durationSeconds <= 0) {
      throw InvalidWorkoutDataException(
        'durationSeconds must be positive, but was $durationSeconds.',
      );
    }
  }
}
