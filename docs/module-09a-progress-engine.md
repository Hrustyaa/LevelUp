# LevelUp — Module 09A: XP, Levels & Progress Engine

**Document:** Module 09A Architecture & Implementation Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Completed (Backend logic, SQLite v3 migration, coordinator integration, and automated tests verified)

---

## 1. Architecture

Module 09A implements the authoritative XP, level, and streak engine under `lib/features/progress/`:

- **`XpRewardPolicy`** (`lib/features/progress/application/xp_reward_policy.dart`) — Centralized, configurable eligibility evaluator.
- **`LevelCalculator`** (`lib/features/progress/application/level_calculator.dart`) — Deterministic level, floor, next-level requirement, and progress fraction calculator.
- **`StreakCalculator`** (`lib/features/progress/application/streak_calculator.dart`) — Deterministic local-calendar daily streak calculator.
- **`IProgressRepository` / `SqliteProgressRepository` / `InMemoryProgressRepository`** (`lib/features/progress/data/progress_repository.dart`) — Transactional, exactly-once SQLite reward journal.
- **`IProgressService` / `ProgressService`** (`lib/features/progress/application/progress_service.dart`) — Serialized state engine exposing `ProgressState` and `stateStream` for Module 09B.
- **Models (`lib/features/progress/models/`):** `XpRewardRecord`, `LevelInfo`, `StreakInfo`, `ProgressState`.

---

## 2. XP Reward Rules (`XpRewardPolicy`)

- **Base reward:** `50 XP` per genuinely completed, verified `5`-repetition workout (`baseWorkoutXp = 50`, `minimumRepetitions = 5`).
- **Eligible contexts:** Both `ChallengeType.unlockChallenge` and `ChallengeType.freeWorkout`.
- **Ineligible sessions (0 XP):**
  - Incomplete, cancelled, or failed workouts (`completedRepetitions < 5`, or never reaching `WorkoutSessionStatus.completed`).
  - Simulated, preview-only, UI-only, or mock sources (`source` in `{'simulated', 'preview', 'ui_only', 'mock'}` or empty).
  - Empty `sessionId`.
- **Security invariant:** XP and streaks are purely motivational; they never influence `AccessService` or native `grantAccess`.

---

## 3. Level Calculation Rules (`LevelCalculator`)

- Initial level: **Level 1** at `0 XP`, requiring `100 XP` (`stepXp = 100`) to reach Level 2.
- Each subsequent level requires `100` additional XP:
  - Level 1 → 2: `100 XP` (cumulative `100`)
  - Level 2 → 3: `200 XP` (cumulative `300`)
  - Level 3 → 4: `300 XP` (cumulative `600`)
  - Cumulative floor for level $L$: $\frac{100 \cdot (L - 1) \cdot L}{2} = 50 \cdot (L - 1) \cdot L$.
- Matches `DashboardLevel.fromXp` thresholds in `lib/data/dashboard_data.dart`.
- Negative or corrupted persisted totals are clamped to `0`.

---

## 4. Streak Calculation Rules (`StreakCalculator`)

- Each reward stores `local_date` as `'YYYY-MM-DD'` in the user's local calendar at workout completion.
- `StreakCalculator` parses `'YYYY-MM-DD'` into UTC-midnight `DateTime` values so daylight-saving transitions (23h / 25h days) never skew 1-day differences.
- Multiple workouts on the same `local_date` collapse to a single distinct calendar day.
- `currentStreak` counts consecutive days ending on `today` or `yesterday` (in `now.toLocal()`); missed days reset `currentStreak` to `0` while preserving `longestStreak`.
- **Timezone changes:** Rewards retain the local calendar date recorded when the workout completed; `completedToday` and `currentStreak` evaluate relative to the device's current local date.

---

## 5. Database Migration & Backfill Policy

- **Schema Version:** `2` → `3` (`DatabaseConstants.currentSchemaVersion = 3`).
- **New table (`xp_rewards`):**
  - `session_id TEXT PRIMARY KEY NOT NULL`
  - `challenge_id TEXT NOT NULL`
  - `challenge_context TEXT NOT NULL CHECK(challenge_context IN ('unlockChallenge', 'freeWorkout'))`
  - `xp_amount INTEGER NOT NULL CHECK(xp_amount > 0)`
  - `awarded_at INTEGER NOT NULL`
  - `local_date TEXT NOT NULL`
  - `verification_source TEXT NOT NULL`
  - Indexed on `awarded_at DESC` (`idx_xp_rewards_awarded_at`) and `local_date DESC` (`idx_xp_rewards_local_date`).
- **Non-destructive migration:** Upgrading v1 → v3 or v2 → v3 preserves all existing `workout_sessions`, `access_attempts`, and `app_settings` rows intact.
- **Explicit Backfill Policy:** Pre-Module-09 historical `workout_sessions` are **not** silently awarded fabricated XP during SQLite migration. `xp_rewards` starts empty on upgrade and records authoritative rewards from Module 09A forward.

---

## 6. Exactly-Once Rewards & Coordinator Integration

- `ProgressService` serializes all mutations through an internal async queue (`_enqueue`).
- `SqliteProgressRepository.recordRewardIfAbsent` executes inside `db.transaction` with a `session_id` check + `PRIMARY KEY` constraint.
- `CoreIntegrationCoordinator._executeCompletionWorkflow` invokes `_progressService.recordCompletedWorkout(workoutResult)` inside a `try/catch` **after** `saveCompletedWorkout` and **before** the `freeWorkout` early return:
  - Both Free Workouts and Unlock Challenges earn XP.
  - Cancelled/failed sessions never enter `_executeCompletionWorkflow` and earn 0 XP.
  - Any XP persistence failure is caught in `ProgressService` / coordinator and can never abort or duplicate `AccessService.grantAccessForCompletedWorkout`.

---

## 7. Files Created and Modified

- **Created:**
  - `lib/features/progress/models/xp_reward_record.dart`
  - `lib/features/progress/models/level_info.dart`
  - `lib/features/progress/models/streak_info.dart`
  - `lib/features/progress/models/progress_state.dart`
  - `lib/features/progress/application/xp_reward_policy.dart`
  - `lib/features/progress/application/level_calculator.dart`
  - `lib/features/progress/application/streak_calculator.dart`
  - `lib/features/progress/data/progress_repository.dart`
  - `lib/features/progress/application/progress_service.dart`
  - `test/features/progress/progress_engine_test.dart`
  - `docs/module-09a-progress-engine.md`
- **Modified:**
  - `lib/data/database/database_constants.dart` — Added v3 `xp_rewards` table & indices.
  - `lib/data/database/levelup_database.dart` — Added non-destructive v2 → v3 migration.
  - `lib/core/integration/core_integration_coordinator.dart` — Added optional `IProgressService?` hook in `_executeCompletionWorkflow`.
  - `lib/app/di/app_scope.dart` — Wired `SqliteProgressRepository` and `ProgressService` into `AppScope.production()`.
  - `test/data/levelup_database_test.dart` — Updated version assertion and added v2 → v3 migration test.

---

## 8. Known Limitations & Module 09B Handoff

- `CoreInsightsAdapter` intentionally still reports `totalXp: null` and `ActivityEntry.xp: null` so the UI does not display partial XP wiring before Module 09B.
- **Module 09B Handoff:** Bind `AppScope.progressService.currentState` / `stateStream` into `CoreInsightsAdapter` and `LevelUpHomeScreen` (`totalXp`, `levelInfo`, `streakInfo`, `recentRewards`, `completedWorkoutCount`) and update the Progress tab UI to display live XP, levels, and daily streaks.
