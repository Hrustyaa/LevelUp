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
      // Step 1: Explicitly create a genuine Version 1 database fixture
      final v1Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            final batch = db.batch();
            batch.execute(DatabaseConstants.createTableWorkoutSessions);
            batch.execute(DatabaseConstants.createIndexWorkoutSessionsCompletedAt);
            batch.execute(DatabaseConstants.createTableAccessAttempts);
            batch.execute(DatabaseConstants.createIndexAccessAttemptsAttemptedAt);
            await batch.commit(noResult: true);
          },
        ),
      );

      await v1Db.insert(
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
      await v1Db.close();

      // Step 2: Open with LevelUpDatabase at current Version 2 (triggers non-destructive migration)
      final v2Manager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final v2Db = await v2Manager.database;
      expect(await v2Db.getVersion(), equals(DatabaseConstants.currentSchemaVersion));

      // Step 3: Verify existing v1 workout data was completely preserved through migration
      final rows = await v2Db.query(
        DatabaseConstants.tableWorkoutSessions,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: ['session_pre_migration'],
      );
      expect(rows.length, equals(1));
      expect(rows.first[DatabaseConstants.colSessionId], equals('session_pre_migration'));

      // Step 4: Verify the newly migrated v2 app_settings table is operational
      await v2Db.insert(
        DatabaseConstants.tableAppSettings,
        {
          DatabaseConstants.colSettingsKey: 'test_key',
          DatabaseConstants.colSettingsValue: '{"migrated": true}',
          DatabaseConstants.colSettingsUpdatedAt: 1700000000000,
        },
      );
      final settingsRows = await v2Db.query(
        DatabaseConstants.tableAppSettings,
        where: '${DatabaseConstants.colSettingsKey} = ?',
        whereArgs: ['test_key'],
      );
      expect(settingsRows.length, equals(1));
      expect(settingsRows.first[DatabaseConstants.colSettingsValue], equals('{"migrated": true}'));

      // Step 5: Verify reopening preserves both v1 and v2 records
      await v2Manager.close();
      final v2Reopen = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final reopenedDb = await v2Reopen.database;
      expect(await reopenedDb.getVersion(), equals(DatabaseConstants.currentSchemaVersion));
      final reopenedWorkouts = await reopenedDb.query(
        DatabaseConstants.tableWorkoutSessions,
        where: '${DatabaseConstants.colSessionId} = ?',
        whereArgs: ['session_pre_migration'],
      );
      expect(reopenedWorkouts.length, equals(1));
      await v2Reopen.close();
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

    test('21. v2 to v3 migration preserves workouts, access attempts, and app_settings without fabricating XP', () async {
      final v2Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            final batch = db.batch();
            batch.execute(DatabaseConstants.createTableWorkoutSessions);
            batch.execute(DatabaseConstants.createIndexWorkoutSessionsCompletedAt);
            batch.execute(DatabaseConstants.createTableAccessAttempts);
            batch.execute(DatabaseConstants.createIndexAccessAttemptsAttemptedAt);
            batch.execute(DatabaseConstants.createTableAppSettings);
            await batch.commit(noResult: true);
          },
        ),
      );

      await v2Db.insert(DatabaseConstants.tableWorkoutSessions, {
        DatabaseConstants.colSessionId: 'v2_workout_1',
        DatabaseConstants.colChallengeId: 'squats_unlock_5',
        DatabaseConstants.colChallengeContext: 'unlockChallenge',
        DatabaseConstants.colExerciseType: 'squats',
        DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
        DatabaseConstants.colCompletedRepetitions: 5,
        DatabaseConstants.colDurationSeconds: 30,
        DatabaseConstants.colCompletedAt: 1700000000000,
      });
      await v2Db.insert(DatabaseConstants.tableAccessAttempts, {
        DatabaseConstants.colSessionId: 'v2_workout_1',
        DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
        DatabaseConstants.colDurationSeconds: 300,
        DatabaseConstants.colState: 'confirmed',
        DatabaseConstants.colAttemptedAt: 1700000000000,
        DatabaseConstants.colConfirmedAt: 1700000000500,
        DatabaseConstants.colUnlockUntil: 1700000300500,
      });
      await v2Db.insert(DatabaseConstants.tableAppSettings, {
        DatabaseConstants.colSettingsKey: 'app_settings',
        DatabaseConstants.colSettingsValue: '{"sound_feedback_enabled": false}',
        DatabaseConstants.colSettingsUpdatedAt: 1700000000000,
      });
      await v2Db.close();

      final v3Manager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final v3Db = await v3Manager.database;
      expect(
        await v3Db.getVersion(),
        equals(DatabaseConstants.currentSchemaVersion),
      );

      expect(
        (await v3Db.query(DatabaseConstants.tableWorkoutSessions)).length,
        1,
      );
      expect(
        (await v3Db.query(DatabaseConstants.tableAccessAttempts)).length,
        1,
      );
      final settings = await v3Db.query(DatabaseConstants.tableAppSettings);
      expect(settings.length, 1);
      expect(
        settings.first[DatabaseConstants.colSettingsValue],
        '{"sound_feedback_enabled": false}',
      );

      // xp_rewards exists and does NOT fabricate historical XP on migration
      final rewards = await v3Db.query(DatabaseConstants.tableXpRewards);
      expect(rewards, isEmpty);

      await v3Manager.close();
    });

    test('22. v3 to v4 migration preserves workouts, access attempts, app_settings, progress_epoch_ms, and xp_rewards', () async {
      final v3Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            final batch = db.batch();
            batch.execute(DatabaseConstants.createTableWorkoutSessions);
            batch.execute(DatabaseConstants.createIndexWorkoutSessionsCompletedAt);
            batch.execute(DatabaseConstants.createTableAccessAttempts);
            batch.execute(DatabaseConstants.createIndexAccessAttemptsAttemptedAt);
            batch.execute(DatabaseConstants.createTableAppSettings);
            batch.execute(DatabaseConstants.createTableXpRewards);
            batch.execute(DatabaseConstants.createIndexXpRewardsAwardedAt);
            batch.execute(DatabaseConstants.createIndexXpRewardsLocalDate);
            await batch.commit(noResult: true);
          },
        ),
      );

      await v3Db.insert(DatabaseConstants.tableWorkoutSessions, {
        DatabaseConstants.colSessionId: 'v3_workout_1',
        DatabaseConstants.colChallengeId: 'squats_unlock_5',
        DatabaseConstants.colChallengeContext: 'unlockChallenge',
        DatabaseConstants.colExerciseType: 'squats',
        DatabaseConstants.colTargetPackage: 'com.google.android.youtube',
        DatabaseConstants.colCompletedRepetitions: 5,
        DatabaseConstants.colDurationSeconds: 30,
        DatabaseConstants.colCompletedAt: 1700000000000,
      });
      await v3Db.insert(DatabaseConstants.tableAppSettings, {
        DatabaseConstants.colSettingsKey: 'progress_epoch_ms',
        DatabaseConstants.colSettingsValue: '1700000000000',
        DatabaseConstants.colSettingsUpdatedAt: 1700000000000,
      });
      await v3Db.insert(DatabaseConstants.tableXpRewards, {
        DatabaseConstants.colSessionId: 'v3_workout_1',
        DatabaseConstants.colChallengeId: 'squats_unlock_5',
        DatabaseConstants.colChallengeContext: 'unlockChallenge',
        DatabaseConstants.colXpAmount: 50,
        DatabaseConstants.colAwardedAt: 1700000000000,
        DatabaseConstants.colLocalDate: '2023-11-14',
        DatabaseConstants.colVerificationSource: 'camera',
      });
      await v3Db.close();

      final v4Manager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final v4Db = await v4Manager.database;
      expect(await v4Db.getVersion(), equals(4));

      expect(
        (await v4Db.query(DatabaseConstants.tableWorkoutSessions)).length,
        1,
      );
      expect(
        (await v4Db.query(DatabaseConstants.tableXpRewards)).length,
        1,
      );
      final epochRows = await v4Db.query(
        DatabaseConstants.tableAppSettings,
        where: '${DatabaseConstants.colSettingsKey} = ?',
        whereArgs: ['progress_epoch_ms'],
      );
      expect(epochRows.length, 1);
      expect(epochRows.first[DatabaseConstants.colSettingsValue], '1700000000000');

      final achievements = await v4Db.query(DatabaseConstants.tableAchievements);
      expect(achievements, isEmpty);

      await v4Manager.close();
    });
  });
}
