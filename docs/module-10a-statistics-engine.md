# LevelUp — Module 10A: Real Statistics Engine

**Document:** Module 10A Architecture & Implementation Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Implemented & Verified

---

## 1. Architecture

Module 10A introduces a read-only, serialized Statistics Engine under `lib/features/statistics/` that separates SQLite aggregation, local-calendar boundary arithmetic, service orchestration, and UI-consumable immutable models:

- **Calendar & Boundary Logic (`lib/features/statistics/application/statistics_calendar.dart`):**
  - `StatisticsCalendar` and `DateRange` with injectable `clock` support.
- **Immutable Models (`lib/features/statistics/models/`):**
  - `StatisticsPeriod` (`today`, `currentWeek`, `last7Days`, `allTime`)
  - `WorkoutStatistics`
  - `UnlockStatistics`
  - `AccessDurationStatistics`
  - `DailyActivityStats`
  - `StatisticsSnapshot`
- **SQLite Aggregation Repository (`lib/features/statistics/data/statistics_repository.dart`):**
  - `IStatisticsRepository` and `SqliteStatisticsRepository`.
- **Service Layer (`lib/features/statistics/application/statistics_service.dart`):**
  - `IStatisticsService` and `StatisticsService`.
- **Dependency Injection (`lib/app/di/app_scope.dart`):**
  - Registered `statisticsRepository` and `statisticsService` in `AppScope` and `AppScope.production(...)`, sharing the existing `LevelUpDatabase`, `progressService`, and `focusService`.

---

## 2. Authoritative Data Sources

| Category | Authoritative Source | Mutating? |
|---|---|---|
| Completed workouts, squats, Free Workout vs Unlock Challenge | SQLite `workout_sessions` (`SqliteStatisticsRepository`) | Read-only |
| Confirmed unlocks & authorized duration | SQLite `access_attempts` (`state = 'confirmed'`) | Read-only |
| Total XP, current level, current & longest streaks | `IProgressService.currentState` (Module 09A) | Read-only |
| Current Focus gate & temporary unlock state | `IFocusService.currentState` (Modules 01–08) | Read-only |

No SQLite schema changes were required; schema remains at version 3 (`DatabaseConstants.currentSchemaVersion = 3`), preserving all existing `workout_sessions`, `access_attempts`, `app_settings`, and `xp_rewards` data.

---

## 3. Supported Statistics & Metric Definitions

### A. Workout Statistics (`WorkoutStatistics`)
- `allTimeCompleted` (alias `totalCompleted`): `COUNT(DISTINCT session_id)` across `workout_sessions`.
- `todayCompleted`: distinct completed workouts in `[todayStart, tomorrowStart)`.
- `thisWeekCompleted`: distinct completed workouts in `[mondayStart, nextMondayStart)`.
- `totalVerifiedRepetitions`: `SUM(completed_repetitions)` for `exercise_type = 'squats'`.
- `unlockChallengesCompleted`: distinct completed workouts with `challenge_context = 'unlockChallenge'`.
- `freeWorkoutsCompleted`: distinct completed workouts with `challenge_context = 'freeWorkout'`.
- Cancelled or incomplete sessions never enter `workout_sessions` and are excluded.

### B. Unlock Statistics (`UnlockStatistics`)
- `todayConfirmed`, `thisWeekConfirmed`, `allTimeConfirmed`: `COUNT(DISTINCT session_id)` from `access_attempts` where `state = 'confirmed'`, bucketed by `COALESCE(confirmed_at, attempted_at)`.
- `prepared`, `uncertain`, `definitivelyRejected` attempts and `freeWorkout` sessions are strictly excluded.

### C. Access Duration Statistics (`AccessDurationStatistics`)
- `totalAuthorizedDuration`: `Duration(seconds: SUM(duration_seconds))` across confirmed unlocks.
- `todayAuthorizedDuration`: `Duration(seconds: SUM(duration_seconds))` across confirmed unlocks today.
- `averageAuthorizedDuration`: mean `Duration` per confirmed unlock, or `null` when `allTimeConfirmed == 0` (distinguishing unavailable from zero).
- **Important:** Represents **authorized unlock time granted** (e.g. 300 s per unlock), **not** foreground screen time.

### D. XP, Levels & Streaks (`StatisticsSnapshot`)
- `totalXp`, `levelInfo`, `currentLevel`, `streakInfo`, `currentStreak`, `longestStreak` are read directly from `IProgressService.currentState`.
- Never recalculated as `workoutCount * 50`.

### E. Focus State (`StatisticsSnapshot.focus`)
- Exposed via `IFocusService?.currentState` without duplicating the Focus state machine.

---

## 4. Timezone & Calendar Boundary Rules

- **First day of the week:** Monday (`DateTime.monday == 1`, ISO-8601).
- **Boundaries:** Inclusive start, exclusive end (`[start, end)`), converted from local `DateTime(year, month, day)` to UTC milliseconds for indexed SQLite range predicates.
- **Calendar arithmetic:** Uses `DateTime(year, month, day + delta)` rather than adding fixed 24-hour `Duration`s, ensuring exact handling across midnight, month/year rollovers, and 23h/25h Daylight Saving Time transitions.
- **Rolling 7 days vs Current Week:** `thisWeekCompleted` / `thisWeekConfirmed` use `[Monday 00:00, next Monday 00:00)`, while `weeklyActivity` covers the rolling 7 local calendar days `[today - 6 days, tomorrow 00:00)`.

---

## 5. SQLite Aggregation Queries

- Single-pass aggregate `rawQuery` calls using `COUNT(DISTINCT session_id)`, `COALESCE(SUM(...), 0)`, and `CASE WHEN ts >= ? AND ts < ?` avoid `limit: 50` truncation and avoid loading lifetime rows into Dart memory.
- `loadWeeklyActivity` queries only the 7-day window `[sevenDaysStartMs, todayEndMs)` using existing indexes (`idx_workout_sessions_completed_at`, `idx_access_attempts_attempted_at`) and buckets timestamps in Dart via `DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal()` for exact OS DST accuracy.

---

## 6. Deduplication Guarantees

- Both `workout_sessions` and `access_attempts` enforce `session_id TEXT PRIMARY KEY NOT NULL`.
- All SQLite aggregate queries use `COUNT(DISTINCT session_id)`.
- `loadWeeklyActivity` maintains `seenWorkouts` and `seenUnlocks` sets keyed by `session_id`.
- A completed challenge with a failed/rejected unlock increments `workouts` but never `unlocks`.
- A Free Workout increments `freeWorkoutsCompleted` and `totalVerifiedRepetitions` but never `unlocks`.

---

## 7. Weekly Activity Data Format (`DailyActivityStats`)

`StatisticsSnapshot.weeklyActivity` always contains 7 entries ordered oldest → newest:
- `localDate`: local midnight `DateTime`
- `dateKey`: `'YYYY-MM-DD'`
- `completedWorkouts`: distinct completed workouts on that local day (genuine `0` if none)
- `confirmedUnlocks`: distinct confirmed unlocks on that local day (genuine `0` if none)
- `verifiedRepetitions`: total verified squat repetitions on that local day (genuine `0` if none)

---

## 8. Error Handling & Concurrency

- `StatisticsService.refresh()` serializes calls through `_enqueue` so concurrent refreshes cannot deadlock or interleave out-of-order.
- Read-only queries never open write `db.transaction` blocks, avoiding SQLite lock contention with `SettingsService` or `ProgressService`.
- On repository error or `progressState.errorMessage != null`, `StatisticsService` emits a `StatisticsSnapshot` with `hasError == true` (`errorMessage` set) and rethrows — never silently returning `0`s as valid statistics.

---

## 9. XP Engine Compatibility

- `StatisticsService` reads `IProgressService.currentState` without calling `recordCompletedWorkout` or mutating `xp_rewards`.
- Respects Module 09A's `progress_epoch_ms` and verification source allowlist.

---

## 10. Unsupported Metrics

- **`foregroundUsageMinutes` (`null`) & `screenTimeSaved` (`null`):**
  Android `UsageStatsManager` (`PACKAGE_USAGE_STATS`) is not implemented. An authorized 5-minute unlock only proves permission was granted for 300 seconds — not how long the user spent inside the target app or how much screen time was "saved". Therefore `Screen Time Saved` and `Foreground Usage` are explicitly unsupported and exposed as `null`.

---

## 11. Module 10B UI Handoff

Module 10B can consume `AppScope.statisticsService.currentSnapshot` and `snapshotStream` directly in `CoreInsightsAdapter` / `LevelUpHomeScreen` for:
- Dashboard summary cards (`workouts.todayCompleted`, `workouts.totalVerifiedRepetitions`, `unlocks.todayConfirmed`)
- All-time statistics (`workouts.allTimeCompleted`, `unlocks.allTimeConfirmed`, `accessDuration.totalAuthorizedDuration`)
- 7-day Progress activity chart (`weeklyActivity`)
- XP, level, and streak summaries (`totalXp`, `levelInfo`, `streakInfo`)

---

## 12. Known Limitations

- `AppScope.statisticsService` relies on `ProgressService` and `FocusService` being refreshed by `AppScope.refresh()` / `AppScope.initialize()` or callers calling `statisticsService.refresh()`.
- Foreground app usage and screen time saved remain `null` until a future Android `UsageStatsManager` module is approved.

---

## 13. Tests & Validation Results

Added `test/features/statistics/statistics_engine_test.dart` (9 test groups covering empty DB, completed/cancelled/failed sessions, squat totals, Free Workout isolation, confirmed-only unlocks, session deduplication, local calendar / midnight / week / month / year / DST boundaries, 65-record (>50) all-time aggregation, read-only XP compatibility, error propagation, concurrent refreshes, and `AppScope.production` integration).

- `flutter pub get`: Succeeded.
- `flutter analyze --no-pub`: `No issues found!`
- `flutter test --no-pub`: **462 passed, 0 failed** (453 existing + 9 Module 10A test groups).
