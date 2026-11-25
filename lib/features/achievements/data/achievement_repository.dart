import '../../../data/database/database_constants.dart';
import '../../../data/database/levelup_database.dart';
import '../models/achievement_unlock_record.dart';

/// Contract for durable, exactly-once achievement unlock persistence.
abstract class IAchievementRepository {
  /// Returns all unlocked achievement records ordered by `unlocked_at DESC`.
  Future<List<AchievementUnlockRecord>> getUnlockedRecords();

  /// Atomically persists [record] if [record.achievementId] is not already
  /// present. Returns `true` if newly inserted, `false` if already unlocked.
  Future<bool> recordUnlockIfAbsent(AchievementUnlockRecord record);
}

/// SQLite implementation of [IAchievementRepository] backed by [LevelUpDatabase].
class SqliteAchievementRepository implements IAchievementRepository {
  final LevelUpDatabase _dbManager;

  SqliteAchievementRepository({LevelUpDatabase? databaseManager})
      : _dbManager = databaseManager ?? LevelUpDatabase();

  @override
  Future<List<AchievementUnlockRecord>> getUnlockedRecords() async {
    final db = await _dbManager.database;
    final rows = await db.query(
      DatabaseConstants.tableAchievements,
      orderBy: '${DatabaseConstants.colUnlockedAt} DESC',
    );
    return rows.map(AchievementUnlockRecord.fromMap).toList(growable: false);
  }

  @override
  Future<bool> recordUnlockIfAbsent(AchievementUnlockRecord record) async {
    final db = await _dbManager.database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        DatabaseConstants.tableAchievements,
        columns: [DatabaseConstants.colAchievementId],
        where: '${DatabaseConstants.colAchievementId} = ?',
        whereArgs: [record.achievementId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return false;
      }
      await txn.insert(
        DatabaseConstants.tableAchievements,
        record.toMap(),
      );
      return true;
    });
  }
}

/// In-memory implementation of [IAchievementRepository] for unit tests.
class InMemoryAchievementRepository implements IAchievementRepository {
  final Map<String, AchievementUnlockRecord> _records = {};

  @override
  Future<List<AchievementUnlockRecord>> getUnlockedRecords() async {
    final list = _records.values.toList()
      ..sort((a, b) => b.unlockedAt.compareTo(a.unlockedAt));
    return list;
  }

  @override
  Future<bool> recordUnlockIfAbsent(AchievementUnlockRecord record) async {
    if (_records.containsKey(record.achievementId)) {
      return false;
    }
    _records[record.achievementId] = record;
    return true;
  }
}
