# LevelUp — Module 10B: Real Statistics UI Integration

**Document:** Module 10B Architecture & Implementation Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Implemented & Verified

---

## 1. Existing UI Reviewed

- `lib/screens/levelup_home_screen.dart` (`LevelUpHomeScreen` / `_HomeState`):
  - Home tab (`_home`): `Today` metric cards, `_levelCard`, `This week` chart (`_usageCard` / `_UsageBars`), and `Recent activity`.
  - Progress tab (`_progress`): `Workouts today` & `Unlocks today`, `_levelCard`, `_streakCard`, `Screen time` (`_usageCard`), and `Activity`.
  - Activity detail (`_openActivity`): `Today` / `This week` / `All` filter and `Last 7 days` chart.
- `lib/data/dashboard_data.dart` (`DashboardInsights`, `UsageDay`).
- `lib/app/adapters/core_insights_adapter.dart` (`CoreInsightsAdapter`).
- `lib/main_ui.dart` (`LevelUpIntroDemo` / `_WelcomeFlowState`).

---

## 2. `StatisticsService` Integration Architecture

- **`AppScope`** (`lib/app/di/app_scope.dart`) passes `this.statisticsService` (`IStatisticsService`) into `CoreInsightsAdapter`.
- **`CoreInsightsAdapter.loadInsights()`** (`lib/app/adapters/core_insights_adapter.dart`) refreshes `_statisticsService.refresh()` after `_progressService?.refresh()` and populates `DashboardInsights.statistics` (`StatisticsSnapshot?`), `DashboardInsights.statisticsError`, `todayUnlocks` (`stats.unlocks.todayConfirmed`), and `todayWorkouts` (`stats.workouts.todayCompleted`) without `limit: 50` truncation.
- **`DashboardInsights`** (`lib/data/dashboard_data.dart`) adds optional `StatisticsSnapshot? statistics` and `String? statisticsError`, preserving full backward compatibility with legacy preview tests where `statistics == null`.
- **`lib/main_ui.dart`** passes `statisticsStream: _scope?.statisticsService.snapshotStream` to `LevelUpHomeScreen`.

---

## 3. Real Dashboard & Progress Metrics

### Home Dashboard (`_home`)
- When `todayUsageMinutes == null` and `statistics != null`, the first `Today` card displays **`Workouts today`** (`stats.workouts.todayCompleted`) alongside **`Temporary unlocks`** (`stats.unlocks.todayConfirmed`).
- The `This week` section renders **`Weekly workout activity`** (`_weeklyActivityCard`) backed by `stats.weeklyActivity`.

### Progress Tab (`_progress`)
- Preserves `Workouts today`, `Unlocks today`, `_levelCard` (Module 09B), and `_streakCard` (Module 09B).
- Adds `_progressStatsSummary`:
  - **`Total workouts`** (`stats.workouts.allTimeCompleted`)
  - **`Verified squats`** (`stats.workouts.totalVerifiedRepetitions`)
  - **`This week`** workouts & **`total unlocks`** (`stats.workouts.thisWeekCompleted`, `stats.unlocks.allTimeConfirmed`)
  - **`Authorized access granted`** (`stats.accessDuration.totalAuthorizedDuration` and `averageAuthorizedDuration`) — strictly labeled as granted permission duration, never "Screen time" or "Time saved".
  - **`Screen time saved: Unavailable`** — explicitly kept unavailable until Android `UsageStatsManager` is implemented.
- Replaces the unsupported `Screen time` placeholder with **`Weekly workout activity`** (`_WorkoutActivityBars`).

---

## 4. Seven-Day Chart Integration (`_WorkoutActivityBars`)

- Connects directly to `StatisticsSnapshot.weeklyActivity` (7 chronological `DailyActivityStats` entries).
- Displays real `completedWorkouts` counts with genuine `0`s on inactive days and localized weekday labels (`M T W T F S S`, `Пн Вт Ср Чт Пт Сб Вс`, `Дс Сс Ср Бс Жм Сб Жс`).
- Matches existing dark/lime `_UsageBars` styling without adding external charting dependencies.
- Also integrated into `_openActivity` (`Last 7 days`) when `insights.statistics != null`.

---

## 5. Data Refresh Strategy & Loop/Contention Prevention

- `LevelUpHomeScreen` subscribes to `statisticsStream` in `_bindStatisticsStream()` and cancels `_statisticsSub` in `dispose()` (re-binding on `didUpdateWidget`).
- Uses `_signatureFromStatistics(StatisticsSnapshot)` deduplication alongside `_signatureFromState(ProgressState)` and `_refreshing` / `_generation` guards:
  - Self-triggered `statisticsService.refresh()` emissions from `_refresh()` update `_lastStatisticsSignature` before clearing `_refreshing`, preventing re-entrant refresh loops.
  - Rapid `AppLifecycleState.resumed` events and repeated equivalent stream emissions do not cause chained refreshes or SQLite lock contention.
  - 1-second `_ticker` uses `quiet: true` and never triggers `loadInsights()` or `statisticsService.refresh()`.

---

## 6. Loading, Empty & Error States

- **Empty / new user:** Genuine `0`s (`Workouts today: 0`, `Temporary unlocks: 0`, `Total workouts: 0`, `Verified squats: 0`, 7-day chart all `0`s, `Authorized access granted: 0m · Avg: —`).
- **Statistics / SQLite error:** `CoreInsightsAdapter` captures `statisticsService.refresh()` failures into `DashboardInsights.statisticsError` (`statistics` stays `null`), and the UI displays localized `_statisticsErrorCard()` (`Statistics could not be loaded.`) instead of fake `0`s.
- **Unsupported metrics:** `Screen time saved: Unavailable` and `foregroundUsageMinutes == null`.

---

## 7. Localization Updates (EN / RU / KK)

Localized labels added in `lib/screens/levelup_home_screen.dart` for:
- `Weekly workout activity` / `Тренировки за неделю` / `Апталық жаттығу белсенділігі`
- `Total workouts` / `Всего тренировок` / `Барлық жаттығулар`
- `Verified squats` / `Засчитано приседаний` / `Есептелген отырулар`
- `Authorized access granted` / `Выданный доступ` / `Берілген рұқсат`
- `Screen time saved` / `Сэкономлено времени` / `Үнемделген уақыт`
- `Unavailable` / `Недоступно` / `Қолжетімсіз`
- `Statistics could not be loaded.` / `Не удалось загрузить статистику.` / `Статистиканы жүктеу мүмкін болмады.`

---

## 8. Files Changed

- **Modified:**
  - `lib/data/dashboard_data.dart`
  - `lib/app/adapters/core_insights_adapter.dart`
  - `lib/app/di/app_scope.dart`
  - `lib/main_ui.dart`
  - `lib/screens/levelup_home_screen.dart`
- **Added:**
  - `test/app/integration_module_10b_test.dart`
  - `docs/module-10b-statistics-ui.md`

---

## 9. Physical Pixel 7 Pro Verification Checklist

1. Install updated debug APK (`main_ui.dart`) over existing app **without clearing app data**.
2. Verify Dashboard and Progress load without freezing.
3. Check existing historical workout totals (`Total workouts`, `Verified squats`, `Weekly workout activity`).
4. Complete a real 5-squat Unlock Challenge → verify `Workouts today`, `Total workouts`, `Verified squats`, `Temporary unlocks`, `Authorized access granted`, and `XP` increase only after native authorization.
5. Complete a Free Workout → verify `Workouts today`, `Total workouts`, `Verified squats`, and `XP` increase without increasing unlocks or granting native access.
6. Confirm `Weekly workout activity` updates for the current day.
7. Restart LevelUp → verify totals persist with no duplicate XP, workouts, or unlocks.
8. Rapidly switch between Dashboard, Progress, and Android Home → verify no freezes or SQLite lock errors, and confirm native Gate + 300-second unlock still work.

---

## 10. Remaining Limitations

- Android `UsageStatsManager` (`PACKAGE_USAGE_STATS`) is not implemented; `Screen time saved` and foreground app usage remain `Unavailable` (`null`).
