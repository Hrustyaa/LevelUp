import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/errors/persistence_exceptions.dart';
import 'database_constants.dart';

/// Database provider and lifecycle manager for LevelUp local SQLite persistence.
class LevelUpDatabase {
  final DatabaseFactory? _factory;
  final String? _customPath;

  Database? _db;
  Future<Database>? _opening;
  Future<void>? _closing;

  /// Creates a [LevelUpDatabase] manager.
  ///
  /// For production, defaults to platform `databaseFactory` and standard app directory.
  /// For testing, allows injecting an in-memory or FFI factory and custom path.
  LevelUpDatabase({
    DatabaseFactory? databaseFactory,
    String? customPath,
  })  : _factory = databaseFactory,
        _customPath = customPath;

  /// The database factory configured for this instance, if any.
  DatabaseFactory? get factory => _factory;

  /// True if a connection is currently open and active.
  bool get isOpen => _db != null && _db!.isOpen;

  /// Retrieves the active database connection, opening it if not yet open.
  Future<Database> get database async {
    final closing = _closing;
    if (closing != null) await closing;
    if (isOpen) return _db!;
    return _opening ??= _open().then((db) {
      _db = db;
      return db;
    }).whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final factory = _factory ?? databaseFactory;
    final String fullPath;

    if (_customPath != null) {
      fullPath = _customPath;
    } else {
      final databasesDir = await factory.getDatabasesPath();
      fullPath = p.join(databasesDir, DatabaseConstants.databaseFileName);
    }

    try {
      return await factory.openDatabase(
        fullPath,
        options: OpenDatabaseOptions(
          version: DatabaseConstants.currentSchemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onConfigure: _onConfigure,
        ),
      );
    } catch (e) {
      if (e is PersistenceException) rethrow;
      throw PersistenceException(
        message: 'Failed to open LevelUp SQLite database at "$fullPath": $e',
        cause: e,
      );
    }
  }

  Future<void> _onConfigure(Database db) async {
    // Enable SQLite foreign keys and WAL mode if supported
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    batch.execute(DatabaseConstants.createTableWorkoutSessions);
    batch.execute(DatabaseConstants.createIndexWorkoutSessionsCompletedAt);
    batch.execute(DatabaseConstants.createTableAccessAttempts);
    batch.execute(DatabaseConstants.createIndexAccessAttemptsAttemptedAt);
    batch.execute(DatabaseConstants.createTableAppSettings);
    batch.execute(DatabaseConstants.createTableXpRewards);
    batch.execute(DatabaseConstants.createIndexXpRewardsAwardedAt);
    batch.execute(DatabaseConstants.createIndexXpRewardsLocalDate);
    batch.execute(DatabaseConstants.createTableAchievements);
    batch.execute(DatabaseConstants.createIndexAchievementsUnlockedAt);
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    try {
      // Incremental non-destructive migrations.
      // Version 1: baseline schema (workout_sessions, access_attempts).
      // Version 2: adds app_settings key-value store (Module 08).
      // Version 3: adds xp_rewards durable journal (Module 09A).
      if (oldVersion < 1) {
        await _onCreate(db, newVersion);
        return;
      }
      if (oldVersion < 2) {
        await db.execute(DatabaseConstants.createTableAppSettings);
      }
      if (oldVersion < 3) {
        await db.execute(DatabaseConstants.createTableXpRewards);
        await db.execute(DatabaseConstants.createIndexXpRewardsAwardedAt);
        await db.execute(DatabaseConstants.createIndexXpRewardsLocalDate);
      }
      if (oldVersion < 4) {
        await db.execute(DatabaseConstants.createTableAchievements);
        await db.execute(DatabaseConstants.createIndexAchievementsUnlockedAt);
      }
      if (oldVersion < 5) {
        // SQLite does not support modifying CHECK constraints with ALTER TABLE.
        // Strategy: create v5 table with extended constraint, copy data, drop
        // old table, rename v5 → workout_sessions, recreate index.
        await db.execute(DatabaseConstants.createTableWorkoutSessionsV5);
        await db.execute(DatabaseConstants.migrateWorkoutSessionsV5CopyData);
        await db.execute(DatabaseConstants.dropTableWorkoutSessions);
        await db.execute(DatabaseConstants.renameWorkoutSessionsV5);
        await db.execute(DatabaseConstants.createIndexWorkoutSessionsCompletedAt);
      }
    } catch (e) {
      throw DatabaseMigrationException(
        fromVersion: oldVersion,
        toVersion: newVersion,
        message: 'Failed to migrate database from version $oldVersion to $newVersion: $e',
        cause: e,
      );
    }
  }

  /// Executes [action] inside an atomic SQLite transaction.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction<T>(action);
  }

  /// Closes the database connection if open.
  Future<void> close() => _closing ??= _closeAfterOpen()
      .whenComplete(() => _closing = null);

  Future<void> _closeAfterOpen() async {
    final opening = _opening;
    try {
      if (opening != null) await opening;
    } catch (_) {
      // The open caller observes the failure. There may be nothing to close.
    }
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }
}
