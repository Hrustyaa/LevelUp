# LevelUp — Module 11A: Achievements Engine & Persistent Badges

**Document:** Module 11A Architecture & Implementation Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Implemented & Verified

---

## 1. Achievement Architecture

Module 11A implements a serialized, exactly-once Achievements Engine under `lib/features/achievements/`:

- **Models (`lib/features/achievements/models/`):**
  - `AchievementCategory` (`workouts`, `repetitions`, `unlocks`, `streaks`, `levels`)
  - `AchievementDefinition` (`id`, `category`, `targetValue`, `titleKey`, `descriptionKey`, `sortOrder`)
  - `AchievementUnlockRecord` (`achievementId`, `unlockedAt`, `category`, `targetValue`, `observedValue`)
  - `AchievementProgress` (`definition`, `currentValue`, `isUnlocked`, `unlockedAt`, `clampedCurrentValue`, `fraction`)
  - `AchievementState` (`achievements`, `recentlyUnlocked`, `isLoading`, `errorMessage`, `unlockedAchievements`, `lockedAchievements`, `unlockedCount`, `totalCount`)
- **Catalog (`lib/features/achievements/data/achievement_catalog.dart`):**
  - Centralized `AchievementCatalog.definitions`.
- **Repository (`lib/features/achievements/data/achievement_repository.dart`):**
  - `IAchievementRepository`, `SqliteAchievementRepository`, and `InMemoryAchievementRepository`.
- **Service (`lib/features/achievements/application/achievement_service.dart`):**
  - `IAchievementService` and `AchievementService`.
- **Dependency Injection (`lib/app/di/app_scope.dart`):**
  - Registered `achievementRepository` and `achievementService` in `AppScope` and `AppScope.production(...)`.

---

## 2. Achievement Catalog & Requirements

| ID | Category | Target | Translation Keys | Authoritative Source |
|---|---|---|---|---|
| `first_workout` | `workouts` | 1 | `achievement.first_workout.*` | `StatisticsSnapshot.workouts.allTimeCompleted` |
| `five_workouts` | `workouts` | 5 | `achievement.five_workouts.*` | `StatisticsSnapshot.workouts.allTimeCompleted` |
| `twenty_five_squats` | `repetitions` | 25 | `achievement.twenty_five_squats.*` | `StatisticsSnapshot.workouts.totalVerifiedRepetitions` |
| `first_unlock` | `unlocks` | 1 | `achievement.first_unlock.*` | `StatisticsSnapshot.unlocks.allTimeConfirmed` |
| `three_day_streak` | `streaks` | 3 | `achievement.three_day_streak.*` | `ProgressState.longestStreak` |
| `reach_level_two` | `levels` | 2 | `achievement.reach_level_two.*` | `ProgressState.level` |

No bonus XP is awarded for achievements in Module 11A, and achievements never grant app access or alter Focus authorization.

---

## 3. Unlock Evaluation Rules & Exactly-Once Persistence

- `AchievementService.evaluateAndRefresh()` serializes all evaluations through `_enqueue`.
- Reads `IStatisticsService.currentSnapshot` and `IProgressService.currentState` (never triggering `refresh()` on either service).
- `SqliteAchievementRepository.recordUnlockIfAbsent` executes inside `db.transaction` with an existence check + `achievement_id TEXT PRIMARY KEY NOT NULL` constraint.
- Previously unlocked achievements remain unlocked permanently even if `currentStreak` later resets.

---

## 4. Database Migration (v3 → v4)

- Incremented `DatabaseConstants.currentSchemaVersion` from `3` to `4`.
- Added table `achievements` (`achievement_id` PK, `unlocked_at`, `category`, `target_value`, `observed_value`) and index `idx_achievements_unlocked_at`.
- Non-destructive incremental migration `if (oldVersion < 4)` in `LevelUpDatabase._onUpgrade` preserves all `workout_sessions`, `access_attempts`, `app_settings`, `xp_rewards`, and `progress_epoch_ms` rows.

---

## 5. Historical Achievement Policy

- **Reconstructible from persisted records:** `first_workout`, `five_workouts`, `twenty_five_squats`, and `first_unlock` evaluate directly from `workout_sessions` and confirmed `access_attempts` via `StatisticsService`.
- **Epoch-scoped from Module 09A forward:** `three_day_streak` and `reach_level_two` evaluate from `ProgressService.currentState` (`longestStreak` and `level`), respecting `progress_epoch_ms` without retroactively fabricating XP.
- **Timestamp policy:** Because historical tables do not store achievement-unlock timestamps, newly discovered historical milestones record the actual evaluation/unlock timestamp (`_clock().toUtc()`) on first evaluation and never invent past timestamps.

---

## 6. Progress Calculations

- Locked achievements expose `clampedCurrentValue` in `[0, targetValue]` and `fraction` in `[0.0, 1.0]`.
- Unlocked achievements clamp to `targetValue` (`fraction == 1.0`) and preserve their persisted `unlockedAt`.

---

## 7. Integration, Refresh Strategy & Loop Prevention

- `AppScope.initialize()` initializes `progressService` → `statisticsService` → `achievementService`.
- `AppScope.refresh()` refreshes `progressService` → `statisticsService` → `achievementService.evaluateAndRefresh()`.
- `AchievementService` never calls `StatisticsService.refresh()` or `ProgressService.refresh()`, eliminating any `achievementStream → statisticsStream → achievementStream` cycle.

---

## 8. Error Handling & Performance

- If `StatisticsService` or `ProgressService` reports an error, `AchievementService` preserves existing unlocked records from SQLite, emits an error `AchievementState`, never falsely unlocks, and rethrows.
- SQLite read/write failures propagate cleanly without partial unlocks.
- Single `SELECT` on `achievements` + in-memory `currentSnapshot` / `currentState` reads avoid extra heavy SQLite scans.

---

## 9. Automated Tests & Validation

- Added `test/features/achievements/achievements_engine_test.dart` and updated `test/data/levelup_database_test.dart` (including v3 → v4 migration test).
- `flutter pub get`: Succeeded.
- `flutter analyze --no-pub`: `No issues found!`
- `flutter test --no-pub`: **475 passed, 0 failed**.
- `flutter build apk --debug -t lib/main_ui.dart --no-pub`: Built successfully.
- `flutter build apk --debug -t lib/main_dev.dart --no-pub`: Built successfully.

---

## 10. Known Limitations & Module 11B Handoff

- **Known limitations:** No bonus XP for achievements; no cloud sync or notifications; UI copy must be mapped from `AchievementDefinition.titleKey` / `descriptionKey` in Module 11B.
- **Module 11B handoff:** Consume `AppScope.achievementService.currentState` and `stateStream` to render earned/locked badges, progress bars (`clampedCurrentValue / targetValue`), unlock timestamps, and newly unlocked celebrations with EN/RU/KK localization.
