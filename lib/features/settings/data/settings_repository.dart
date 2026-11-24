import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/errors/settings_exceptions.dart';
import '../../../data/database/database_constants.dart';
import '../../../data/database/levelup_database.dart';
import '../models/app_settings.dart';

/// Contract for persistent storage of user application settings.
abstract class ISettingsRepository {
  /// Loads persisted settings from storage.
  /// Falls back to [AppSettings.defaults] if uninitialized or corrupted.
  Future<AppSettings> loadSettings();

  /// Persists [settings] to storage.
  /// Throws [InvalidSettingsException] if [settings] fails validation.
  /// Throws [SettingsPersistenceException] if write fails.
  Future<void> saveSettings(AppSettings settings);

  /// Resets persisted settings to [AppSettings.defaults].
  Future<void> resetToDefaults();
}

/// SQLite-backed persistent implementation of [ISettingsRepository].
class SqliteSettingsRepository implements ISettingsRepository {
  static const String _settingsRowKey = 'app_settings';

  final LevelUpDatabase _databaseManager;
  final DateTime Function() _clock;

  SqliteSettingsRepository({
    required LevelUpDatabase databaseManager,
    DateTime Function()? clock,
  })  : _databaseManager = databaseManager,
        _clock = clock ?? DateTime.now;

  @override
  Future<AppSettings> loadSettings() async {
    try {
      final db = await _databaseManager.database;
      final rows = await db.query(
        DatabaseConstants.tableAppSettings,
        where: '${DatabaseConstants.colSettingsKey} = ?',
        whereArgs: [_settingsRowKey],
        limit: 1,
      );

      if (rows.isEmpty) {
        return AppSettings.defaults();
      }

      final rawValue = rows.first[DatabaseConstants.colSettingsValue] as String?;
      if (rawValue == null || rawValue.isEmpty) {
        return AppSettings.defaults();
      }

      final decoded = jsonDecode(rawValue) as Map<String, dynamic>;
      final parsed = AppSettings.fromJson(decoded);
      return parsed.isValid ? parsed : AppSettings.defaults();
    } catch (_) {
      // Graceful recovery from uninitialized tables, corrupted JSON, or SQLite errors.
      return AppSettings.defaults();
    }
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    // 1. Enforce domain validation
    settings.validate();

    try {
      final db = await _databaseManager.database;
      final jsonString = jsonEncode(settings.toJson());
      final nowMs = _clock().millisecondsSinceEpoch;

      await db.insert(
        DatabaseConstants.tableAppSettings,
        {
          DatabaseConstants.colSettingsKey: _settingsRowKey,
          DatabaseConstants.colSettingsValue: jsonString,
          DatabaseConstants.colSettingsUpdatedAt: nowMs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (e is InvalidSettingsException) rethrow;
      throw SettingsPersistenceException(
        'Failed to persist settings to SQLite: $e',
        cause: e,
      );
    }
  }

  @override
  Future<void> resetToDefaults() async {
    await saveSettings(AppSettings.defaults());
  }
}

/// In-memory implementation of [ISettingsRepository] for unit testing and simulation.
class InMemorySettingsRepository implements ISettingsRepository {
  AppSettings _settings;
  bool shouldFailLoad = false;
  bool shouldFailSave = false;

  InMemorySettingsRepository({AppSettings? initialSettings})
      : _settings = initialSettings ?? AppSettings.defaults();

  @override
  Future<AppSettings> loadSettings() async {
    if (shouldFailLoad) {
      // Graceful fallback on simulated load failure
      return AppSettings.defaults();
    }
    return _settings;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    if (shouldFailSave) {
      throw const SettingsPersistenceException('Simulated storage write failure.');
    }
    settings.validate();
    _settings = settings;
  }

  @override
  Future<void> resetToDefaults() async {
    _settings = AppSettings.defaults();
  }
}
