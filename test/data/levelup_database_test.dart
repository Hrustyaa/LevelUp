import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/database/database_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('levelup_db_test_');
    dbPath = p.join(tempDir.path, 'test_levelup.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LevelUpDatabase Lifecycle & Initialization', () {
    test('1. initializes database and creates schema tables and indices', () async {
      final dbManager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );

      final db = await dbManager.database;
      expect(db.isOpen, isTrue);

      // Verify tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;",
      );
      final tableNames = tables.map((t) => t['name']).toList();
      expect(tableNames, contains(DatabaseConstants.tableWorkoutSessions));
      expect(tableNames, contains(DatabaseConstants.tableAccessAttempts));

      // Verify indices exist
      final indices = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' ORDER BY name;",
      );
      final indexNames = indices.map((i) => i['name']).toList();
      expect(indexNames, contains('idx_workout_sessions_completed_at'));
      expect(indexNames, contains('idx_access_attempts_attempted_at'));

      await dbManager.close();
      expect(dbManager.isOpen, isFalse);
    });

    test('4. closing and reopening the same database file preserves existing data', () async {
      // Open connection 1, insert a row
      final dbManager1 = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final db1 = await dbManager1.database;

      await db1.insert(
        DatabaseConstants.tableWorkoutSessions,
        {
          DatabaseConstants.colSessionId: 'session_persist_test',
          DatabaseConstants.colRequestId: 'req_1',
          DatabaseConstants.colChallengeId: 'squats_unlock_5',
          DatabaseConstants.colChallengeContext: 'unlockChallenge',
          DatabaseConstants.colExerciseType: 'squats',
          DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
          DatabaseConstants.colCompletedRepetitions: 5,
          DatabaseConstants.colDurationSeconds: 45,
          DatabaseConstants.colCompletedAt: 1700000000000,
          DatabaseConstants.colVerificationSource: 'camera',
        },
      );

      await dbManager1.close();
      expect(dbManager1.isOpen, isFalse);

      // Open connection 2 with the same file path
      final dbManager2 = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final db2 = await dbManager2.database;
      expect(db2.isOpen, isTrue);

      final rows = await db2.query(
        DatabaseConstants.tableWorkoutSessions,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: ['session_persist_test'],
      );

      expect(rows.length, equals(1));
      expect(rows.first[DatabaseConstants.colChallengeId], equals('squats_unlock_5'));
      expect(rows.first[DatabaseConstants.colCompletedRepetitions], equals(5));

      await dbManager2.close();
    });

    test('20. database version migration retains existing user data', () async {
      // Step 1: Create a database at Version 1 and insert data
      final dbManager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final db = await dbManager.database;

      await db.insert(
        DatabaseConstants.tableWorkoutSessions,
        {
          DatabaseConstants.colSessionId: 'session_pre_migration',
          DatabaseConstants.colChallengeId: 'squats_unlock_5',
          DatabaseConstants.colChallengeContext: 'unlockChallenge',
          DatabaseConstants.colExerciseType: 'squats',
          DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
          DatabaseConstants.colCompletedRepetitions: 5,
          DatabaseConstants.colDurationSeconds: 40,
          DatabaseConstants.colCompletedAt: 1700000000000,
        },
      );
      await dbManager.close();

      // Step 2: Open with higher version (simulating future v2 upgrade)
      final v2Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              // Simulated v2 non-destructive migration: add new column
              await db.execute(
                'ALTER TABLE ${DatabaseConstants.tableWorkoutSessions} '
                'ADD COLUMN notes TEXT;',
              );
            }
          },
        ),
      );

      // Step 3: Verify existing data was preserved through migration
      final rows = await v2Db.query(
        DatabaseConstants.tableWorkoutSessions,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: ['session_pre_migration'],
      );
      expect(rows.length, equals(1));
      expect(rows.first[DatabaseConstants.colSessionId], equals('session_pre_migration'));

      // Verify the new v2 column is available
      await v2Db.update(
        DatabaseConstants.tableWorkoutSessions,
        {'notes': 'migrated_successfully'},
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: ['session_pre_migration'],
      );
      final updated = await v2Db.query(
        DatabaseConstants.tableWorkoutSessions,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: ['session_pre_migration'],
      );
      expect(updated.first['notes'], equals('migrated_successfully'));

      await v2Db.close();
    });

    test('enforces SQL CHECK constraints on direct database inserts', () async {
      final dbManager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final db = await dbManager.database;

      // Inserting negative repetitions violates SQL CHECK(completed_repetitions >= 0)
      expect(
        () => db.insert(
          DatabaseConstants.tableWorkoutSessions,
          {
            DatabaseConstants.colSessionId: 'sess_sql_check_1',
            DatabaseConstants.colChallengeId: 'squats_unlock_5',
            DatabaseConstants.colChallengeContext: 'unlockChallenge',
            DatabaseConstants.colExerciseType: 'squats',
            DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
            DatabaseConstants.colCompletedRepetitions: -5, // Violates CHECK
            DatabaseConstants.colDurationSeconds: 30,
            DatabaseConstants.colCompletedAt: 1700000000000,
          },
        ),
        throwsA(isA<DatabaseException>()),
      );

      // Inserting invalid state string violates SQL CHECK(state IN (...))
      expect(
        () => db.insert(
          DatabaseConstants.tableAccessAttempts,
          {
            DatabaseConstants.colSessionId: 'sess_sql_check_2',
            DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
            DatabaseConstants.colDurationSeconds: 300,
            DatabaseConstants.colState: 'maliciousState', // Violates CHECK
            DatabaseConstants.colAttemptedAt: 1700000000000,
          },
        ),
        throwsA(isA<DatabaseException>()),
      );

      await dbManager.close();
    });
  });
}
