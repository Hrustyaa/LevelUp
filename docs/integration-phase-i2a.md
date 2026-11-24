# LevelUp — Phase I2A: Connect UI to Real Core Services

**Document:** Integration Phase I2A Report  
**Date:** November 25, 2026  
**Status:** Completed (Verified via `flutter analyze`, 419 passing tests, and 3 APK builds; awaiting review/commit)  
**Branch:** `integration/ui-core`  
**Base Commit:** `ec40d29` (Phase I1 Merge)  

---

## 1. Overview

Phase I2A connects the LevelUp UI onboarding, supported app selection, permission management, and Focus controls to the real Core services (Modules 01, 02, 07, 08) via a dedicated production dependency container (`AppScope`) and typed Dart adapters under `lib/app/adapters/`.

Per Phase I2A scope boundaries:
- The real ML Kit camera challenge workflow is **not** connected yet (scheduled for Phase I2B).
- `lib/test_kit/challenge_screen.dart` is isolated from production flows and cannot invoke `grantAccess`.
- `lib/main.dart` and `lib/main_dev.dart` remain preserved and untouched.

---

## 2. Production Dependency Injection (`AppScope`)

Implemented in `lib/app/di/app_scope.dart`:

- **`AppScope.production()`** wires real Core services without simulation bridges or Developer Lab state:
  - `INativeBridge` $\rightarrow$ `NativeBridge` (Module 01)
  - `IFocusService` $\rightarrow$ `FocusService` (Module 02)
  - `LevelUpDatabase` $\rightarrow$ SQLite database (Module 07)
  - `ISettingsRepository` $\rightarrow$ `SqliteSettingsRepository` (Module 08)
  - `ICameraPermissionChecker` $\rightarrow$ `DefaultCameraPermissionChecker` (Module 08)
  - `ISettingsService` $\rightarrow$ `SettingsService` (Module 08)
  - `IWorkoutHistoryRepository` $\rightarrow$ `WorkoutHistoryRepository` (Module 07)
  - `IAccessAttemptRepository` $\rightarrow$ `AccessAttemptRepository` (Module 07)
  - `IChallengeService` $\rightarrow$ `ChallengeService` (Module 03)
  - `IWorkoutSessionManager` $\rightarrow$ `WorkoutSessionManager` (Module 05)
  - `IAccessService` $\rightarrow$ `AccessService` (Module 06)
  - `ICoreIntegrationCoordinator` $\rightarrow$ `CoreIntegrationCoordinator`
- **Lifecycle:**
  - `AppScope.initialize()` opens SQLite, initializes `SettingsService`, refreshes `FocusService`, and initializes `CoreIntegrationCoordinator`.
  - `AppScope.refresh()` refreshes permissions and native Focus state on `AppLifecycleState.resumed`.
  - `AppScope.dispose()` disposes all stream controllers and closes the SQLite database.
- **`AppScopeProvider`** (`InheritedWidget`) exposes `AppScope` down the widget tree.

---

## 3. Exact UI Components Connected & Real Backend Services Used

| UI Component | Adapter / Bridge | Real Backend Services Used |
|---|---|---|
| `LevelUpAppSelectionScreen` | `CoreAppCatalogAdapter` | `ChannelConstants.allowedTargets` (YouTube, Instagram, TikTok) |
| `ManageAppsScreen` | `CoreAppCatalogAdapter` + `CoreFocusGatewayAdapter` | `ChannelConstants.allowedTargets`, `IFocusService` |
| `LevelUpPermissionsScreen` | `CorePermissionGatewayAdapter` | `ISettingsService`, `INativeBridge`, `ICameraPermissionChecker` |
| `AppPermissionsScreen` | `CorePermissionGatewayAdapter` | `ISettingsService`, `INativeBridge`, `ICameraPermissionChecker` |
| `LevelUpHomeScreen` (Home & Focus tabs) | `CoreFocusGatewayAdapter` | `IFocusService` (`getFocusStatus`, `enableFocus`, `disableFocus`, `selectTargetApp`, `refreshState`) |
| `LevelUpHomeScreen` (Progress tab) | `CoreInsightsAdapter` | `IWorkoutHistoryRepository`, `IAccessAttemptRepository` |
| `LevelUpIntroDemo` (`lib/main_ui.dart`) | `AppScope.production()` | Full Core DI container + lifecycle observer (`AppLifecycleState.resumed`) |

### Modified UI Files
- `lib/main_ui.dart` — Wired `AppScope.production()` in `main()`, added optional `AppScope? scope` to `LevelUpIntroDemo` and `_WelcomeFlow` (preserving backward compatibility for legacy preview widget tests), routed `_permissionGateway`, `_focusGateway`, `_loadApps`, and `_loadDashboardInsights` through `AppScope` when present, added `AppScope.refresh()` on resume, and isolated `_checkChallenge()` / `_handleMovementNotice()` from `test_kit/challenge_screen.dart`.

---

## 4. Supported App Selection & Focus Controls

- **Allowed Targets:** `CoreAppCatalogAdapter` exposes strictly the 3 native-supported packages from `ChannelConstants`:
  - `com.google.android.youtube` (YouTube)
  - `com.instagram.android` (Instagram)
  - `com.zhiliaoapp.musically` (TikTok)
- **Single-Target Restriction:** Native Android gate supports only one active restricted package at a time. When an onboarding draft contains multiple apps, `LevelUpHomeScreen` prompts the user to choose one target app before enabling Focus.
- **Draft Isolation:** Onboarding drafts saved to `SharedPreferences` never silently activate native blocking. Enabling Focus requires an explicit user tap on Home/Focus.
- **Accessibility Precondition & Anti-Racing:** `CoreFocusGatewayAdapter.enable()` validates target against `ChannelConstants.allowedTargets`, delegates to `FocusService.selectTargetApp()` and `FocusService.enableFocus()` (which throws `AccessibilityPermissionRequiredException` if Accessibility is off), and enforces an in-flight lock to prevent concurrent racing calls.
- **Active `unlockUntil` Preservation:** `CoreFocusGatewayAdapter.read()` reads `state.unlockUntil` from `FocusService.refreshState()` so temporary unlocks remain accurately displayed.

---

## 5. Permissions Integration & Unsupported Capabilities

`CorePermissionGatewayAdapter` maps real system status without inventing new MethodChannels:
- **Accessibility (`LevelUpPermission.accessibility`):** Read via `SettingsService.refresh()` (`NativeBridge.getState()`). Requests open Android Accessibility Settings via `NativeBridge.openAccessibilitySettings()`.
- **Camera (`LevelUpPermission.camera`):** Read via `ICameraPermissionChecker.checkCameraPermission()`. Requests invoke `ICameraPermissionChecker.requestCameraPermission()`; permanently denied maps to `PermissionState.unavailable`, settings opens `NativeBridge.openAppSettings()`.
- **Usage Stats (`LevelUpPermission.usage`):** Honestly reported as `PermissionState.unavailable` (native `UsageStatsManager` bridge is not implemented). Never faked as granted.
- **Notifications (`LevelUpPermission.notifications`):** Honestly reported as `PermissionState.unavailable` (native `levelup/focus_notifications` bridge is not implemented). Never faked as granted.

---

## 6. Remaining Mock / Unavailable Data & Known Limitations

1. **OS Screen Time (`todayUsageMinutes`, `week`, `usageByApp`):** `CoreInsightsAdapter` honestly returns `todayUsageMinutes: null` and empty usage maps because `UsageStatsManager` is not implemented natively.
2. **Legacy Preview Fallback (`lib/data/`):** `AndroidAppCatalog`, `AndroidPermissionGateway`, `AndroidUsageGateway`, and `ExistingFocusGateway` remain intact on disk so existing `test/ui/` unit/widget tests continue to pass without modification, but they are bypassed whenever `AppScope` is provided (including production `main_ui.dart`).
3. **Challenge Execution (Phase I2A Safety Isolation):**
   - `test_kit/challenge_screen.dart` and `test_kit/squat_counter.dart` are **not** connected to `AppScope` or native `grantAccess`.
   - Tapping "Open movement challenge" on the Challenge tab displays a clear dialog informing the user that real ML Kit camera pose verification connects in Phase I2B and direct UI access grants are disabled.
   - `_checkChallenge()` in `main_ui.dart` is a safe no-op when `AppScope` is active so native challenge requests are not consumed prematurely or routed to the unverified test-kit counter.

---

## 7. Automated Verification Results

- **`flutter pub get`:** Succeeded (`Got dependencies!`).
- **`flutter analyze`:** `No issues found! (ran in 0.8s)`.
- **`flutter test`:** **419 tests passed, 0 failed, 0 skipped** (393 existing Core/DevLab/UI tests + 26 new Phase I2A tests across `test/app/adapters/`, `test/app/di/`, and `test/app/integration_phase_i2a_test.dart`).
- **APK Builds:**
  - `flutter build apk --debug -t lib/main.dart`: **Success**
  - `flutter build apk --debug -t lib/main_dev.dart`: **Success**
  - `flutter build apk --debug -t lib/main_ui.dart`: **Success**

---

## 8. Physical Device Verification Checklist (Android)

- [ ] Install `lib/main_ui.dart` debug APK on physical Android device.
- [ ] Complete onboarding (Welcome $\rightarrow$ App Selection shows YouTube, Instagram, TikTok $\rightarrow$ Focus Setup $\rightarrow$ Permissions).
- [ ] Confirm native Focus remains OFF after onboarding completion.
- [ ] Attempt to enable Focus with Accessibility disabled $\rightarrow$ verify "Accessibility Required" dialog appears.
- [ ] Tap "Open Permissions" $\rightarrow$ enable LevelUp Accessibility Service in Android Settings $\rightarrow$ return to app $\rightarrow$ verify Accessibility updates to Granted on resume.
- [ ] Enable Focus for YouTube $\rightarrow$ verify Focus becomes active and YouTube is blocked by `LevelUpAccessibilityService`.
- [ ] Tap Movement challenge $\rightarrow$ verify Phase I2B notice appears and no access is granted.
- [ ] Disable Focus from Home/Focus tab $\rightarrow$ verify YouTube opens normally.
- [ ] Install `lib/main_dev.dart` and confirm Developer Lab B2 diagnostics and ML Kit challenge remain intact.

---

## 9. Phase I2B Handoff

To complete full end-to-end integration in Phase I2B:
1. Build a `FocusChallengeViewModel` connecting `FocusChallengeScreen` & `FocusAccessGrantedScreen` (`lib/focus_experience/focus_screens.dart`) to `AppScope.coordinator` (`CoreIntegrationCoordinator`), `CameraController`, `PoseDetector`, `SquatGeometry`, and `PoseEngineAdapter`.
2. Update `_checkChallenge()` in `lib/main_ui.dart` to detect pending native challenge requests via `coordinator.launchUnlockChallenge(requirePendingRequest: true)` on app launch/resume.
3. Wire Challenge tab "Movement" action to `coordinator.launchFreeWorkout()` (which never grants app access).
4. Ensure all access grants flow exclusively through `CoreIntegrationCoordinator` $\rightarrow$ `AccessAttemptRepository` $\rightarrow$ `AccessService` $\rightarrow$ `NativeBridge.grantAccess(minutes: 5)`.
5. Once physical-device end-to-end testing passes, promote the integrated UI to `lib/main.dart` while keeping `lib/main_dev.dart`.
