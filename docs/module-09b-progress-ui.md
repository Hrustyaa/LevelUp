# LevelUp — Module 09B: Real XP, Levels & Streaks UI Integration

**Document:** Module 09B Integration Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Completed (Verified via `flutter analyze`, full `flutter test`, and `main_ui.dart` / `main_dev.dart` APK builds)

---

## 1. Existing Progress UI Reviewed

- `lib/screens/levelup_home_screen.dart`:
  - `_levelCard()` (Home tab, Progress tab, and `_openLevel` detail screen)
  - `_progress()` (Progress tab)
  - `_openLevel()` (`Your level` + `XP history`)
  - `_event()` (`+XP` badge rendering per activity row)
- `lib/data/dashboard_data.dart`: `DashboardInsights`, `ActivityEntry`, `DashboardLevel`.
- `lib/app/adapters/core_insights_adapter.dart`: `CoreInsightsAdapter`.
- `lib/main_ui.dart`: `LevelUpIntroDemo` / `_WelcomeFlowState`.

---

## 2. Real Data Sources & Adapter Integration

- **`AppScope.progressService` (`IProgressService`)** is passed into `CoreInsightsAdapter` inside `AppScope`.
- `CoreInsightsAdapter.loadInsights()` calls `_progressService.refresh()` alongside `IWorkoutHistoryRepository.getRecentWorkouts(limit: 50)` and `IAccessAttemptRepository.getRecentAttempts(limit: 50)` in parallel.
- `DashboardInsights` now carries authoritative `LevelInfo?`, `StreakInfo?`, `completedWorkoutCount`, `recentRewards`, and `progressError`.
- Each `ActivityEntry` attaches `xp` strictly from the matching `XpRewardRecord` (`rewardsBySession[w.sessionId]?.xpAmount`); workouts without an authoritative `XpRewardRecord` (such as pre-epoch or untrusted workouts) have `xp: null`.

---

## 3. XP, Level & Streak Display Logic

- **XP & Level (`_levelCard` & `_openLevel`):**
  - Reads `LevelInfo` directly from `ProgressService` (zero duplicated level formulas in UI).
  - Displays `Level N`, `${xpIntoCurrentLevel} / ${xpRequiredForNextLevel} XP · ${totalXp} total XP`, `LinearProgressIndicator(value: progressFraction)`, and `${xpRemainingToNextLevel} XP to Level ${level + 1}`.
  - New users cleanly render `Level 1`, `0 / 100 XP · 0 total XP`.
- **Streaks (`_streakCard` on Progress tab):**
  - Reads `StreakInfo` directly from `ProgressService`: `${currentStreak} day streak`, `Longest: ${longestStreak}`, and `Completed today` / `Not yet today` status.
- **Reward History (`_openLevel` & Activity feeds):**
  - Displays persisted `+50 XP` badges on verified sessions from `XpRewardRecord`s, deduplicated by `sessionId`.
- **Live Updates:**
  - `LevelUpHomeScreen` subscribes to `ProgressService.stateStream` (`progressStream`), guards against re-entrant refreshes (`_refreshing`), cancels subscriptions in `dispose()`, and preserves `_generation` out-of-order protection.

---

## 4. Empty & Error States

- Successfully loaded empty state: `Level 1`, `0 / 100 XP · 0 total XP`, `0 day streak`, `No recorded XP events yet.`
- Progress read/refresh error (`progressState.errorMessage != null`): displays `Progress could not be loaded.` and never converts a failed SQLite read into `0 XP`.

---

## 5. Files Modified / Added

- **Modified:**
  - `lib/data/dashboard_data.dart` — Extended `DashboardInsights` with `levelInfo`, `streakInfo`, `completedWorkoutCount`, `recentRewards`, and `progressError`.
  - `lib/app/adapters/core_insights_adapter.dart` — Connected `IProgressService` to populate `DashboardInsights` and per-session `xp`.
  - `lib/app/di/app_scope.dart` — Passed `this.progressService` to `CoreInsightsAdapter`.
  - `lib/screens/levelup_home_screen.dart` — Connected `_levelCard`, `_streakCard`, `_openLevel`, and `progressStream` subscription (with signature-based deduplication to prevent re-entrant refresh loops).
  - `lib/main_ui.dart` — Passed `progressStream: _scope?.progressService.stateStream` to `LevelUpHomeScreen`.
  - `lib/features/progress/data/progress_repository.dart` — Cached/read `progress_epoch_ms` outside transactions when already persisted to avoid SQLite transaction contention during dashboard refreshes.
  - `test/app/challenge/production_challenge_test.dart` — Advanced fake time past 5 s `_refresh()` timeouts and paused lifecycle before disposal in Test 1 so no pending timers remain.
- **Added:**
  - `test/app/integration_module_09b_test.dart`
  - `docs/module-09b-progress-ui.md`

### Verification
- `flutter analyze --no-pub`: `No issues found!`
- `flutter test --no-pub`: **453 passed, 0 failed**
- `flutter build apk --debug -t lib/main_ui.dart --no-pub`: Built successfully
- `flutter build apk --debug -t lib/main_dev.dart --no-pub`: Built successfully

---

## 6. Physical Pixel 7 Pro Verification Checklist

1. Install updated debug APK (`main_ui.dart`) over existing app **without clearing app data**.
2. Verify SQLite v2 → v3 upgrade preserves existing workout history and `AppSettings`.
3. Confirm pre-Module-09 workouts do not receive fabricated XP.
4. Complete a real 5-squat Unlock Challenge → confirm `+50 XP` appears (`Level 1`, `50 / 100 XP`).
5. Complete a 2nd eligible workout on the same day → confirm `+50 XP` (`Level 2`, `100 total XP`) and daily streak stays `1`.
6. Restart app → verify `Level 2` and `100 total XP` persist.
7. Confirm Focus blocking & 300-second unlock still work normally.
8. Confirm Free Workout earns `+50 XP` without unlocking restricted apps.
9. Toggle settings (`Sound & haptic feedback`, `Diagnostic logging`) → verify progress is preserved.
