import '../../../data/database/database_constants.dart';
import '../../../data/database/levelup_database.dart';
import '../models/xp_reward_record.dart';

/// Contract for durable XP reward journal persistence.
abstract class IProgressRepository {
  /// Atomically inserts [record] if [record.sessionId] does not already exist.
  /// Returns `true` if inserted, `false` if already present (idempotent).
  Future<bool> recordRewardIfAbsent(XpRewardRecord record);

  /// Retrieves a reward record by [sessionId], or `null` if absent.
  Future<XpRewardRecord?> getRewardBySessionId(String sessionId);

  /// Retrieves all reward records ordered by `awarded_at DESC`.
  Future<List<XpRewardRecord>> getAllRewards();

  /// Returns the sum of all persisted `xp_amount` entries (clamped `>= 0`).
  Future<int> getTotalXp();

  /// Returns the persisted Module 09A baseline epoch (UTC ms), or stores
  /// [defaultEpochMs] atomically on first initialization so pre-Module-09
  /// historical workouts are never retroactively fabricated with XP.
  Future<int> getOrCreateProgressEpochMs(int defaultEpochMs);
}

/// SQLite implementation of [IProgressRepository] backed by [LevelUpDatabase].
class SqliteProgressRepository implements IProgressRepository {
  static const String _epochKey = 'progress_epoch_ms';

  final LevelUpDatabase _dbManager;
  int? _cachedEpochMs;

  SqliteProgressRepository({LevelUpDatabase? databaseManager})
      : _dbManager = databaseManager ?? LevelUpDatabase();

  @override
  Future<bool> recordRewardIfAbsent(XpRewardRecord record) async {
    final db = await _dbManager.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        DatabaseConstants.tableXpRewards,
        columns: [DatabaseConstants.colSessionId],
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: [record.sessionId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return false;
      }
      await txn.insert(
        DatabaseConstants.tableXpRewards,
        record.toMap(),
      );
      return true;
    });
  }

  @override
  Future<XpRewardRecord?> getRewardBySessionId(String sessionId) async {
    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableXpRewards,
      where: '${DatabaseConstants.colSessionId} = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return XpRewardRecord.fromMap(rows.first);
  }

  @override
  Future<List<XpRewardRecord>> getAllRewards() async {
    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableXpRewards,
      orderBy: '${DatabaseConstants.colAwardedAt} DESC',
    );
    return rows.map(XpRewardRecord.fromMap).toList(growable: false);
  }

  @override
  Future<int> getTotalXp() async {
    final db = await _dbManager.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${DatabaseConstants.colXpAmount}), 0) AS total '
      'FROM ${DatabaseConstants.tableXpRewards}',
    );
    if (rows.isEmpty) return 0;
    final raw = (rows.first['total'] as num?)?.toInt() ?? 0;
    return raw < 0 ? 0 : raw;
  }

  @override
  Future<int> getOrCreateProgressEpochMs(int defaultEpochMs) async {
    if (_cachedEpochMs != null) return _cachedEpochMs!;
    final db = await _dbManager.database;
    final existing = await db.query(
      DatabaseConstants.tableAppSettings,
      columns: [DatabaseConstants.colSettingsValue],
      where: '${DatabaseConstants.colSettingsKey} = ?',
      whereArgs: [_epochKey],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final parsed =
          int.tryParse(existing.first[DatabaseConstants.colSettingsValue] as String);
      if (parsed != null) {
        _cachedEpochMs = parsed;
        return parsed;
      }
    }
    return db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseConstants.tableAppSettings,
        columns: [DatabaseConstants.colSettingsValue],
        where: '${DatabaseConstants.colSettingsKey} = ?',
        whereArgs: [_epochKey],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final parsed =
            int.tryParse(rows.first[DatabaseConstants.colSettingsValue] as String);
        if (parsed != null) {
          _cachedEpochMs = parsed;
          return parsed;
        }
      }
      await txn.insert(
        DatabaseConstants.tableAppSettings,
        {
          DatabaseConstants.colSettingsKey: _epochKey,
          DatabaseConstants.colSettingsValue: defaultEpochMs.toString(),
          DatabaseConstants.colSettingsUpdatedAt: defaultEpochMs,
        },
      );
      _cachedEpochMs = defaultEpochMs;
      return defaultEpochMs;
    });
  }
}

/// In-memory implementation of [IProgressRepository] for unit tests.
class InMemoryProgressRepository implements IProgressRepository {
  final Map<String, XpRewardRecord> _records = {};
  int? _epochMs;

  @override
  Future<bool> recordRewardIfAbsent(XpRewardRecord record) async {
    if (_records.containsKey(record.sessionId)) {
      return false;
    }
    _records[record.sessionId] = record;
    return true;
  }

  @override
  Future<XpRewardRecord?> getRewardBySessionId(String sessionId) async =>
      _records[sessionId];

  @override
  Future<List<XpRewardRecord>> getAllRewards() async {
    final list = _records.values.toList()
      ..sort((a, b) => b.awardedAt.compareTo(a.awardedAt));
    return list;
  }

  @override
  Future<int> getTotalXp() async {
    final sum = _records.values.fold<int>(0, (acc, r) => acc + r.xpAmount);
    return sum < 0 ? 0 : sum;
  }

  @override
  Future<int> getOrCreateProgressEpochMs(int defaultEpochMs) async {
    return _epochMs ??= defaultEpochMs;
  }
}
