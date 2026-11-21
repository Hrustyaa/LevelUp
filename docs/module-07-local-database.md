# Module 07 — Local Database / Persistence Engine

> **Status:** Implemented and unit-tested  
> **Branch:** `feature/core`  
> **Dependencies:** Module 03 (Challenge Catalog), Module 05 (Workout Models), `sqflite`, `sqflite_common_ffi`

---

## 1. Overview & Separation of Concerns

The Local Database / Persistence Engine provides reliable, offline-first SQLite persistence for LevelUp on Android. It serves two distinct purposes:
1. **Workout History Repository (`workout_sessions`):** Immutable historical records of verified physical exercises performed by the user, providing the data foundation for Module 09 (Progress Engine, streaks, statistics, and XP rewards).
2. **Access Attempt Journal (`access_attempts`):** Audit tracking of application access grants across their complete lifecycle (`prepared`, `confirmed`, `uncertain`, `definitively_rejected`) to prevent duplicate rewards and enable safe state reconciliation.

**Strict Architectural Invariant:**  
This module **never** connects to cloud services (Supabase/Firebase), never calculates arbitrary XP/achievements, never stores fake screen-time metrics, and does not claim crash-safe exactly-once platform execution until native Kotlin updates are introduced in future releases.

---

## 2. SQLite Schema & Constraints

Database file: `levelup.db`  
Current schema version: `1`

### 2.1 Table: `workout_sessions`

Stores completed physical workout sessions produced by `WorkoutSessionManager`.

```sql
CREATE TABLE workout_sessions (
  session_id TEXT PRIMARY KEY NOT NULL,
  request_id TEXT,
  challenge_id TEXT NOT NULL,
  challenge_context TEXT NOT NULL,
  exercise_type TEXT NOT NULL,
  target_package TEXT,
  completed_repetitions INTEGER NOT NULL,
  duration_seconds INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  verification_source TEXT
);

CREATE INDEX idx_workout_sessions_completed_at 
ON workout_sessions (completed_at DESC);
```

#### SQL & Domain Constraints:
- `session_id TEXT PRIMARY KEY NOT NULL`: Enforces unique session identity at the storage level.
- `completed_repetitions >= 0` and `duration_seconds >= 0`: Non-negative performance metrics.
- `completed_at`: Stored as UTC epoch milliseconds (`DateTime.toUtc().millisecondsSinceEpoch`).
- **Free Workout Rule:** When `challenge_context == 'freeWorkout'`, `target_package` must be `NULL`.
- **Unlock Workout Rule:** When `challenge_context == 'unlockChallenge'`, `target_package` must be non-null and belong to `ChannelConstants.allowedTargets`.

### 2.2 Table: `access_attempts`

Audit journal for application access authorization attempts.

```sql
CREATE TABLE access_attempts (
  session_id TEXT PRIMARY KEY NOT NULL,
  target_package TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  state TEXT NOT NULL,
  attempted_at INTEGER NOT NULL,
  confirmed_at INTEGER,
  unlock_until INTEGER,
  failure_reason TEXT
);

CREATE INDEX idx_access_attempts_attempted_at 
ON access_attempts (attempted_at DESC);
```

#### Lifecycle States (`AccessAttemptState`):
- `prepared`: Recorded immediately prior to invoking native `grantAccess`.
- `confirmed`: Native `grantAccess` returned an authoritative `unlock_until` timestamp.
- `uncertain`: Platform channel or IPC failure occurred during/after the call; native state may or may not have changed.
- `definitively_rejected`: Rejected prior to native invocation due to missing permissions, disabled gate, or invalid parameters.

---

## 3. Repositories & Public APIs

### 3.1 `IWorkoutHistoryRepository`

```dart
abstract class IWorkoutHistoryRepository {
  Future<void> saveCompletedWorkout(WorkoutResult result);
  Future<WorkoutResult?> getWorkoutBySessionId(String sessionId);
  Future<List<WorkoutResult>> getRecentWorkouts({int limit = 20});
  Future<List<WorkoutResult>> getWorkoutsByDateRange(DateTime start, DateTime end);
  Future<int> countCompletedWorkouts();
  Future<int> getTotalVerifiedRepetitions({ExerciseType? exerciseType});
}
```

#### Idempotency & Overwrite Protection:
- If `saveCompletedWorkout(result)` is called for an existing `sessionId` with **identical** data, it succeeds idempotently without creating duplicate records.
- If called with **conflicting** data (e.g. altered repetitions or duration), it throws `ConflictingWorkoutRecordException` and leaves the original historical record untouched.
- `INSERT OR REPLACE` is deliberately **not used** on historical records to prevent silent tampering or corruption.

### 3.2 `IAccessAttemptRepository`

```dart
abstract class IAccessAttemptRepository {
  Future<AccessAttemptRecord> createAttemptIfAbsent({
    required String sessionId,
    required String targetPackage,
    required int durationSeconds,
    required DateTime attemptedAt,
  });

  Future<AccessAttemptRecord?> getAttemptBySessionId(String sessionId);

  Future<AccessAttemptRecord> markConfirmed({
    required String sessionId,
    required DateTime confirmedAt,
    required DateTime unlockUntil,
  });

  Future<AccessAttemptRecord> markUncertain({
    required String sessionId,
    required String reason,
  });

  Future<AccessAttemptRecord> markDefinitivelyRejected({
    required String sessionId,
    required String reason,
  });
}
```

#### State Protection Invariants:
- A record that is already `confirmed` **can never be downgraded** to `uncertain` or `definitively_rejected` by late callbacks or error events.
- `createAttemptIfAbsent` returns the existing attempt if one already exists, preventing prepared states from overwriting confirmed states.

---

## 4. Database Lifecycle & Migrations

`LevelUpDatabase` encapsulates SQLite connection handling:
- **Dependency Injection:** Accepts custom `DatabaseFactory` and database path. In development/testing, `databaseFactoryFfi` is injected for headless desktop execution. In production Android runtime, standard platform `databaseFactory` is used.
- **Connection Reuse:** Employs an asynchronous `Completer` lock to prevent multiple simultaneous connection opens.
- **Migration Strategy:** The `onUpgrade` hook receives `oldVersion` and `newVersion`. Migrations are strictly incremental and non-destructive (executing `ALTER TABLE ADD COLUMN` or creating new tables/indices). Existing user data is **never** dropped or cleared during schema version increments.

---

## 5. Crash / Restart Limitations & Recovery Guidance

### Native Platform Constraint
The current Android Kotlin `grantAccess` contract accepts only `{'minutes': Int}`. It does **not** accept `sessionId` or `targetPackage`, and native `SharedPreferences("levelup_gate")` does not persist `sessionId`.

### Safe Recovery Rules
1. **Confirmed:** Authoritatively recorded as granted.
2. **Uncertain:** If the app crashes or times out during IPC, native `unlock_until` might have been written. The system must **never** automatically retry or extend access upon restart. Reconciliation requires reading `bridge.getState()`.
3. **Prepared after crash:** If a session remains in `prepared` state across process restart, native execution may have commenced. It must be treated with the same caution as `uncertain`.
4. **Authority:** Native `SharedPreferences` remains the single source of truth for whether the Android Accessibility barrier is currently open (`unlock_until > System.currentTimeMillis()`).

---

## 6. Planned Integration

- **WorkoutSessionManager (Module 05):** Upon session completion, `WorkoutResult` is written to `WorkoutHistoryRepository`.
- **AccessService (Module 06):** Prior to native `grantAccess`, an attempt is journaled via `createAttemptIfAbsent`. Following native response, it is transitioned to `markConfirmed`, `markUncertain`, or `markDefinitivelyRejected`.
- **Progress Engine (Module 09):** Queries `getWorkoutsByDateRange` and `getTotalVerifiedRepetitions` to calculate daily streaks, charts, and XP ledgers.

---

## 7. Test Suite

Unit and integration tests are verified in `test/data/`:
1. `levelup_database_test.dart`: Table/index creation, close/reopen data retention, version upgrade data preservation.
2. `workout_history_repository_test.dart`: CRUD, idempotency, conflict rejection, free workout null target, unlock target preservation, validation rules, empty history handling, date range filtering, repetition sums, concurrent writes.
3. `access_attempt_repository_test.dart`: State creation, duplicate suppression, state transitions, downgrade prevention, missing record handling, input validation.

Total Module 07 Tests: **23 passing tests**.
