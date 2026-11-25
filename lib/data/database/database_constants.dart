/// Database and schema constants for LevelUp SQLite persistence.
abstract final class DatabaseConstants {
  /// Default file name for the SQLite database.
  static const String databaseFileName = 'levelup.db';

  /// Current schema version.
  static const int currentSchemaVersion = 3;

  // Table names
  static const String tableWorkoutSessions = 'workout_sessions';
  static const String tableAccessAttempts = 'access_attempts';
  static const String tableAppSettings = 'app_settings';
  static const String tableXpRewards = 'xp_rewards';

  // Columns: workout_sessions
  static const String colSessionId = 'session_id';
  static const String colRequestId = 'request_id';
  static const String colChallengeId = 'challenge_id';
  static const String colChallengeContext = 'challenge_context';
  static const String colExerciseType = 'exercise_type';
  static const String colTargetPackage = 'target_package';
  static const String colCompletedRepetitions = 'completed_repetitions';
  static const String colDurationSeconds = 'duration_seconds';
  static const String colCompletedAt = 'completed_at';
  static const String colVerificationSource = 'verification_source';

  // Columns: access_attempts
  static const String colState = 'state';
  static const String colAttemptedAt = 'attempted_at';
  static const String colConfirmedAt = 'confirmed_at';
  static const String colUnlockUntil = 'unlock_until';
  static const String colFailureReason = 'failure_reason';

  // Columns: app_settings
  static const String colSettingsKey = 'key';
  static const String colSettingsValue = 'value';
  static const String colSettingsUpdatedAt = 'updated_at';

  // Columns: xp_rewards
  static const String colXpAmount = 'xp_amount';
  static const String colAwardedAt = 'awarded_at';
  static const String colLocalDate = 'local_date';

  // DDL statements
  static const String createTableWorkoutSessions = '''
    CREATE TABLE IF NOT EXISTS $tableWorkoutSessions (
      $colSessionId TEXT PRIMARY KEY NOT NULL,
      $colRequestId TEXT,
      $colChallengeId TEXT NOT NULL,
      $colChallengeContext TEXT NOT NULL CHECK($colChallengeContext IN ('unlockChallenge', 'freeWorkout')),
      $colExerciseType TEXT NOT NULL CHECK($colExerciseType IN ('squats')),
      $colTargetPackage TEXT,
      $colCompletedRepetitions INTEGER NOT NULL CHECK($colCompletedRepetitions >= 0),
      $colDurationSeconds INTEGER NOT NULL CHECK($colDurationSeconds >= 0),
      $colCompletedAt INTEGER NOT NULL,
      $colVerificationSource TEXT
    );
  ''';

  static const String createIndexWorkoutSessionsCompletedAt = '''
    CREATE INDEX IF NOT EXISTS idx_workout_sessions_completed_at
    ON $tableWorkoutSessions ($colCompletedAt DESC);
  ''';

  static const String createTableAccessAttempts = '''
    CREATE TABLE IF NOT EXISTS $tableAccessAttempts (
      $colSessionId TEXT PRIMARY KEY NOT NULL,
      $colTargetPackage TEXT NOT NULL,
      $colDurationSeconds INTEGER NOT NULL CHECK($colDurationSeconds > 0),
      $colState TEXT NOT NULL CHECK($colState IN ('prepared', 'confirmed', 'uncertain', 'definitivelyRejected')),
      $colAttemptedAt INTEGER NOT NULL,
      $colConfirmedAt INTEGER,
      $colUnlockUntil INTEGER,
      $colFailureReason TEXT
    );
  ''';

  static const String createIndexAccessAttemptsAttemptedAt = '''
    CREATE INDEX IF NOT EXISTS idx_access_attempts_attempted_at
    ON $tableAccessAttempts ($colAttemptedAt DESC);
  ''';

  static const String createTableAppSettings = '''
    CREATE TABLE IF NOT EXISTS $tableAppSettings (
      $colSettingsKey TEXT PRIMARY KEY NOT NULL,
      $colSettingsValue TEXT NOT NULL,
      $colSettingsUpdatedAt INTEGER NOT NULL
    );
  ''';

  static const String createTableXpRewards = '''
    CREATE TABLE IF NOT EXISTS $tableXpRewards (
      $colSessionId TEXT PRIMARY KEY NOT NULL,
      $colChallengeId TEXT NOT NULL,
      $colChallengeContext TEXT NOT NULL CHECK($colChallengeContext IN ('unlockChallenge', 'freeWorkout')),
      $colXpAmount INTEGER NOT NULL CHECK($colXpAmount > 0),
      $colAwardedAt INTEGER NOT NULL,
      $colLocalDate TEXT NOT NULL,
      $colVerificationSource TEXT NOT NULL
    );
  ''';

  static const String createIndexXpRewardsAwardedAt = '''
    CREATE INDEX IF NOT EXISTS idx_xp_rewards_awarded_at
    ON $tableXpRewards ($colAwardedAt DESC);
  ''';

  static const String createIndexXpRewardsLocalDate = '''
    CREATE INDEX IF NOT EXISTS idx_xp_rewards_local_date
    ON $tableXpRewards ($colLocalDate DESC);
  ''';
}
