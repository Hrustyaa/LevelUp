# LevelUp — Phase I2C: Real Dashboard, History & Settings Integration

**Document:** Integration Phase I2C Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Completed (Verified via `flutter analyze`, full `flutter test`, and all 3 APK builds; awaiting physical device confirmation)

---

## 1. Existing Dashboard Widgets Reviewed

- `lib/screens/levelup_home_screen.dart` (`LevelUpHomeScreen`):
  - **Home tab (`_home`):** Focus status card, active unlock countdown (`_countdown`), `Today` metrics (`Selected apps usage`, `Temporary unlocks`), `Level & XP` card, `This week` usage card, and `Recent activity` feed (`_eventsCard(limit: 3)`).
  - **Progress tab (`_progress`):** `Workouts today` & `Unlocks today` metrics, `Level & XP` card, `Screen time` card, and `Activity` feed (`_eventsCard(limit: 5)`).
  - **Activity detail (`_openActivity`):** `Today` / `This week` / `All` period filter, full `History` list, and `Last 7 days` usage card.
  - **Settings tab (`_settings`):** Language selector (`EN` / `RU` / `KK`), `Permissions`, `Focus settings`, and persisted `AppSettings` toggles (`Sound & haptic feedback`, `Diagnostic logging`).
- `lib/screens/manage_apps_screen.dart` & `lib/screens/app_permissions_screen.dart`: Reviewed and preserved intact via Phase I2A `CoreAppCatalogAdapter` and `CorePermissionGatewayAdapter`.
- `lib/main_ui.dart`: Wires `AppScope.production()`, lifecycle refresh, refresh-token propagation, and `SettingsService` callbacks into `LevelUpHomeScreen`.

---

## 2. Actual Core Data Sources

| Feature | Authoritative Core Source |
|---|---|
| Focus enabled, Accessibility status, selected target, active `unlockUntil` | `FocusService` (`IFocusService`) via `CoreFocusGatewayAdapter` |
| Completed workouts, repetition counts, Free Workout vs Unlock Challenge | `WorkoutHistoryRepository` (`IWorkoutHistoryRepository`) via `CoreInsightsAdapter` |
| Confirmed native unlocks (`todayUnlocks`, unlock timestamps, 300s duration) | `AccessAttemptRepository` (`IAccessAttemptRepository`) via `CoreInsightsAdapter` |
| Sound & haptic feedback, diagnostic logging | `SettingsService` (`ISettingsService`) backed by `SqliteSettingsRepository` (`LevelUpDatabase`) |
| Language preference & onboarding state | `SharedPreferences` in `lib/main_ui.dart` (preserved separate from SQLite `AppSettings`) |
| Camera & Accessibility permissions | `CorePermissionGatewayAdapter` (`ISettingsService`, `INativeBridge`, `ICameraPermissionChecker`) |

---

## 3. Values Backed by Real Data

- **Focus & Access State:** `enabled`, `serviceEnabled`, `targets`, and `accessUntil` come directly from `NativeBridge.getState()` via `FocusService.refreshState()`.
- **Daily Metrics (Local-Day Boundaries):**
  - `todayUnlocks`: distinct `sessionId` count of `AccessAttemptRecord`s with `state == AccessAttemptState.confirmed` whose `(confirmedAt ?? attemptedAt).toLocal()` falls within `[startOfDay, endOfDay)`.
  - `todayWorkouts`: distinct `sessionId` count of `WorkoutResult`s whose `completedAt.toLocal()` falls within `[startOfDay, endOfDay)`.
- **Activity & History Feed:**
  - Confirmed `unlockChallenge` sessions (`AccessAttemptState.confirmed`) render as `ActivityKind.temporaryAccess` with app display name (`YouTube` / `Instagram` / `TikTok`), `5m` duration, and verified repetition count (`5 squats`).
  - `freeWorkout` sessions and unconfirmed `unlockChallenge` workouts (`prepared`, `uncertain`, `definitivelyRejected`) render strictly as `ActivityKind.movementCompleted` with `minutes: null` — never falsely reported as unlocked.
  - Sorted descending by timestamp and deduplicated by `sessionId`.
- **Settings:** `soundFeedbackEnabled` and `diagnosticLoggingEnabled` persist to SQLite via `SettingsService.updateSettings` without altering `defaultTargetPackage`, `FocusService`, `unlockUntil`, or workout history.
- **Refresh Lifecycle:** `refreshToken` increments in `lib/main_ui.dart` after returning from `ProductionChallengeScreen` (unlock or free workout), `AppPermissionsScreen`, and `AppLifecycleState.resumed`. `LevelUpHomeScreen._refresh` uses a monotonic `_generation` counter so stale async responses never overwrite newer ones.

---

## 4. Remaining Mock or Unsupported Features (Honest Fallbacks)

- **Module 09 (XP & Progress Engine):** Not implemented yet. `CoreInsightsAdapter` keeps `totalXp: null` and `ActivityEntry.xp: null`. The UI shows `Level & XP` without fabricated XP, levels, streaks, or achievements.
- **OS Screen Time (`UsageStatsManager`):** Not implemented natively. `todayUsageMinutes: null`, `week: const []`, `usageByApp: const {}`, and `LevelUpPermission.usage: PermissionState.unavailable`.
- **Notifications:** Not implemented natively. `LevelUpPermission.notifications: PermissionState.unavailable`.
- **Legacy Preview Gateways (`lib/data/`):** Preserved untouched on disk solely for backward compatibility with legacy `test/ui/` widget tests when `AppScope` is `null`.

---

## 5. Settings Persistence Architecture

- **SQLite (`LevelUpDatabase`, schema preserved):** `SqliteSettingsRepository` stores `AppSettings` (`defaultTargetPackage`, `defaultUnlockDurationSeconds = 300`, `emergencyPauseAllowed`, `soundFeedbackEnabled`, `diagnosticLoggingEnabled`).
- **`SharedPreferences` (`lib/main_ui.dart`):** Stores UI onboarding state, selected language (`en` / `ru` / `kk`), and onboarding focus draft.
- Updating `soundFeedbackEnabled` or `diagnosticLoggingEnabled` calls `SettingsService.updateSettings(current.copyWith(...))`, which validates invariants, writes to SQLite, and leaves native `target` and active `unlock_until` untouched.

---

## 6. Files Modified / Added

- **Modified:**
  - `lib/data/dashboard_data.dart` — Added optional `todayWorkouts` on `DashboardInsights` and `detail` on `ActivityEntry`.
  - `lib/app/adapters/core_insights_adapter.dart` — Parallel recent queries, `sessionId` deduplication, local-day boundaries, confirmed-only unlock counting, Free Workout vs Unlock Challenge distinction, error propagation, and injected `_clock`.
  - `lib/screens/levelup_home_screen.dart` — Added `refreshToken` support, `Workouts today` & `Unlocks today` cards on Progress tab, `detail` display in `_event`, and SQLite-backed `SwitchListTile` controls in `_settings`.
  - `lib/main_ui.dart` — Wired `_homeRefreshToken` updates on resume/challenge/permissions return and connected `SettingsService.updateSettings` callbacks.
- **Added:**
  - `test/app/integration_phase_i2c_test.dart` — Focused automated tests covering Insights accuracy, deduplication, local-day boundaries, error states, disposal safety, and real SQLite settings persistence across restart.
  - `docs/integration-phase-i2c.md` — This report.

---

## 7. Automated Test Results

- `flutter pub get`: Succeeded.
- `flutter analyze`: `No issues found!`.
- `flutter test`: All existing Core, DevLab, UI, Phase I2A, Phase I2B, and Phase I2C tests passing (see final report for exact total count).

---

## 8. Performance Considerations

- `CoreInsightsAdapter.loadInsights` executes `getRecentWorkouts(limit: 50)` and `getRecentAttempts(limit: 50)` concurrently via `Future.wait` and only runs on explicit refresh (`initState`, `refreshToken` change, pull-to-refresh, or lifecycle resume) — never on widget rebuilds or 1-second countdown ticks (`quiet: true`).
- `LevelUpHomeScreen._refresh` guards against out-of-order responses with `_generation` and checks `mounted` before `setState`.

---

## 9. Physical Android Device Verification Checklist

- [ ] Install `lib/main_ui.dart` debug APK on Pixel 7 Pro.
- [ ] Verify Home and Progress tabs show real Focus state, `Today` unlock/workout counts, and `Level & XP` unavailable state (no fake XP).
- [ ] Complete a Free Workout → verify it appears in Activity as `Movement completed` with `5 squats` and `0` unlocks added.
- [ ] Complete an Unlock Challenge → verify it appears as `<App> · unlocked · 5 squats · 5m` and increments `Unlocks today`.
- [ ] Toggle `Sound & haptic feedback` and `Diagnostic logging` in Settings while Focus & an active 5-minute unlock are running → verify native target & unlock countdown remain intact, force-close and reopen app, and verify toggles persisted.

---

## 10. Future Module 09 Integration Requirements

1. Implement authoritative XP calculation and level progression repository in Module 09.
2. Wire `CoreInsightsAdapter` to read `totalXp` and per-session `xp` from Module 09 instead of returning `null`.
3. Add `UsageStatsManager` native bridge only when Android `PACKAGE_USAGE_STATS` permission & query policy are approved.
