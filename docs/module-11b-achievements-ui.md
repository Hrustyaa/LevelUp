# LevelUp — Module 11B: Real Achievements UI Integration

**Document:** Module 11B Architecture & Implementation Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Implemented & Verified

---

## 1. Existing Achievement UI Reviewed

- No pre-existing production Achievements screen or badge grid existed; `lib/screens/levelup_home_screen.dart` (`Progress` tab `_progress()`) had `Workouts today`, `Unlocks today`, `_levelCard`, `_streakCard`, `_progressStatsSummary`, `_weeklyActivityCard`, and `Activity` (`_eventsCard`).
- `lib/data/dashboard_data.dart` (`DashboardInsights`) and `lib/app/adapters/core_insights_adapter.dart` (`CoreInsightsAdapter`) already connected `ProgressService` (09B) and `StatisticsService` (10B).

---

## 2. `AchievementService` Integration

- **`AppScope`** (`lib/app/di/app_scope.dart`) passes `achievementService` (`IAchievementService`) into `CoreInsightsAdapter` when configured (including `AppScope.production(...)`).
- **`CoreInsightsAdapter.loadInsights()`** (`lib/app/adapters/core_insights_adapter.dart`) evaluates `_achievementService.evaluateAndRefresh()` after `_progressService?.refresh()` and `_statisticsService?.refresh()`, populating `DashboardInsights.achievements` (`AchievementState?`) and `DashboardInsights.achievementsError` (`String?`).
- **`lib/main_ui.dart`** passes `achievementStream: _scope?.achievementService.stateStream` to `LevelUpHomeScreen`.
- UI never calls `recordUnlockIfAbsent`, never awards XP, and never triggers `grantAccess`.

---

## 3. UI Components Created / Modified

- **Progress tab (`_progress()` in `lib/screens/levelup_home_screen.dart`):**
  - `_achievementsCard(AchievementState)`: Displays summary header (`Achievements: X / Y` + completion percentage + `LinearProgressIndicator`) and renders all catalog achievements via `_achievementRow(AchievementProgress)`.
  - `_achievementsErrorCard()`: Displays localized `Achievements could not be loaded.` when `achievementsError != null`.
  - **Locked cards:** Muted icon, title, short description, `current / target` progress text, and thin `LinearProgressIndicator(value: item.fraction)`.
  - **Unlocked cards:** Lime verified badge icon, title, short description, `target / target`, and `Unlocked · <short date>` read directly from `AchievementUnlockRecord.unlockedAt`.

---

## 4. Historical Milestone & New-Unlock Feedback Policy

- Historical milestones evaluated from persisted records on startup or upgrade keep their persisted `unlockedAt` timestamp without fabricating past dates.
- `_HomeState._handleAchievementFeedback()` seeds `_shownUnlockIds` on the first non-error load (`_achievementsBaselineSeeded = true`) so historical/startup reconciliations **never** replay SnackBars.
- Genuinely new unlocks during the active session trigger a single subtle `SnackBar` (`Achievement unlocked: <localized title>`) per achievement ID.

---

## 5. Developer Lab & Simulation Isolation Finding

- During preflight inspection, we verified that `TestScenarioRunner` uses isolated `tempDb` files, while `DevLabScope` (`main_dev.dart`) defaults to `LevelUpDatabase()` if `customDatabase` is not overridden and can persist `source: 'simulated'` workouts.
- **Fix implemented:** Added `_trustedWorkoutFilter` in `SqliteStatisticsRepository` (`lib/features/statistics/data/statistics_repository.dart`) to exclude `verification_source IN ('simulated', 'preview', 'ui_only', 'mock')` while preserving `NULL` (legacy rows) and `'camera'`. This ensures simulated Developer Lab sessions cannot contaminate production statistics or unlock `first_workout`, `five_workouts`, or `twenty_five_squats`.

---

## 6. EN / RU / KK Localization

Added complete EN, RU, and KK translations in `lib/screens/levelup_home_screen.dart` for:
- `Achievements` / `Достижения` / `Жетістіктер`
- `Unlocked` / `Открыто` / `Ашылды`
- `Achievement unlocked` / `Достижение открыто` / `Жетістік ашылды`
- `Achievements could not be loaded.` / `Не удалось загрузить достижения.` / `Жетістіктерді жүктеу мүмкін болмады.`
- All 6 achievement titles & descriptions (`first_workout`, `five_workouts`, `twenty_five_squats`, `first_unlock`, `three_day_streak`, `reach_level_two`).

---

## 7. Refresh Lifecycle, Stream & SQLite Safety

- `LevelUpHomeScreen` subscribes to `achievementStream` with `_signatureFromAchievements` deduplication alongside `_lastProgressSignature`, `_lastStatisticsSignature`, `_refreshing`, and `_generation`.
- `_achievementSub?.cancel()` is called in `dispose()` and rebound in `didUpdateWidget()`.
- `AchievementService` reads `StatisticsService.currentSnapshot` and `ProgressService.currentState` without triggering `refresh()` on either service, preventing circular stream loops and SQLite lock contention.

---

## 8. Files Changed

- **Modified:**
  - `lib/features/statistics/data/statistics_repository.dart` (simulation isolation filter)
  - `lib/data/dashboard_data.dart`
  - `lib/app/adapters/core_insights_adapter.dart`
  - `lib/app/di/app_scope.dart`
  - `lib/main_ui.dart`
  - `lib/screens/levelup_home_screen.dart`
- **Added:**
  - `test/app/integration_module_11b_test.dart`
  - `docs/module-11b-achievements-ui.md`

---

## 9. Physical Pixel 7 Pro Verification Checklist

1. Install updated `main_ui.dart` debug APK over existing app **without clearing app data**.
2. Verify SQLite v3 → v4 migration preserves workouts, XP, statistics, and settings.
3. Open **Progress** → confirm **Achievements** section displays all 6 badges and accurate historical/locked progress.
4. Complete a real 5-squat Unlock Challenge → confirm `First Step` & `Focus Breakthrough` unlock with `Unlocked · <date>` and a single SnackBar.
5. Complete a Free Workout → confirm workout/squat progress updates without granting app access.
6. Reach Level 2 (`100 XP`) and cumulative milestones → confirm `Level Up`, `Getting Stronger`, `Squat Starter`, and `Consistency` unlock accurately.
7. Restart LevelUp → verify unlocked badges persist and no startup SnackBar replays.
8. Rapidly switch between Home, Progress, and Focus → verify no freezes or SQLite lock errors, and confirm native Gate + 300-second unlock still work.

---

## 10. Remaining Limitations & Module 12 Handoff

- **Limitations:** No bonus XP for achievements, no Android push notifications, no cloud sync.
- **Module 12 handoff:** All core backend engines (Focus, Challenge, Pose/Camera, Access, Settings, Progress 09, Statistics 10, Achievements 11) and production UI integrations are wired through `AppScope.production()` and ready for end-to-end physical device QA and release hardening.
