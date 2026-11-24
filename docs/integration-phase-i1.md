# LevelUp — Phase I1: Safe UI/Core Branch Integration

**Document:** Integration Phase I1 Report
**Date:** November 25, 2026
**Status:** Completed (Merge Prepared, Verification Succeeded, Ready for Review)
**Target Branch:** `integration/ui-core`
**Source Branch:** `origin/feature/ui` (commit `985defa`)
**Base Branch:** `feature/core` (commit `3d4888b`)
**Merge Base:** commit `747e579`

---

## 1. Executive Summary

Phase I1 successfully unified the LevelUp core backend (`feature/core`) with the teammate's UI preview (`origin/feature/ui`) into the integration branch `integration/ui-core`.

- **Merge outcome:** Clean 3-way merge completed. Every source file merged cleanly without code collisions. The single conflict occurred in `pubspec.lock` due to differing dependencies added on both branches; this was resolved cleanly via `pubspec.yaml` reconciliation and `flutter pub get`.
- **Backend integrity:** All core modules (Modules 01–08), Developer Lab B2, SQLite repositories, and native accessibility gate logic remain 100% preserved and untouched.
- **Verification results:**
  - `flutter analyze`: **0 issues found** (0 errors, 0 warnings, 0 hints across entire codebase).
  - `flutter test`: **393 of 393 tests passed** (100% success rate across core, developer lab, and UI test suites).
  - `flutter build apk --debug`: All 3 entry points (`main.dart`, `main_dev.dart`, `main_ui.dart`) built successfully.

Per Git restrictions, **no automatic commit was created**. The merge is fully resolved, verified, and staged, awaiting manual review.

---

## 2. Preflight State

Before executing the merge:
- **Active Branch:** `integration/ui-core`
- **Initial HEAD Commit:** `3d4888b6f9cfe8a1098b9c591a75c142c152a8f1` (matching `feature/core`)
- **Remote UI Branch:** `origin/feature/ui` at `985defa49385304327ebe07994413b8b8b0948f8`
- **Merge Base:** `747e579be03e8b086a73a03370b0ea36882d2158` (Initial LevelUp project structure)
- **Working Tree:** Clean, 0 uncommitted changes.

---

## 3. Merge Result & Files Changed

### 3.1 Conflict Resolution
- `pubspec.yaml`: Auto-merged cleanly without conflict markers. Combined core dependencies (`sqflite`, `path`, `sqflite_common_ffi`) with UI dependencies (`shared_preferences`, `flutter_launcher_icons`, asset registration `assets/images/levelup_mark.png`, launcher icon configuration).
- `pubspec.lock`: Flagged as content conflict during merge. Resolved by checking out the base lockfile and executing `flutter pub get` against the unified `pubspec.yaml`.
- `.gitignore`: Cleanly merged build artifacts and Android Kotlin cache patterns.
- `android/`: **Zero changes** from `origin/feature/ui`. The native Android implementation in `feature/core` was 100% preserved.

### 3.2 List of Staged Files (43 files from UI preview)
- **Assets:**
  - `assets/images/app_icon.png`
  - `assets/images/app_icon_foreground.png`
  - `assets/images/levelup_mark.png`
- **Documentation:**
  - `docs/ui-preview.md`
- **UI Screens (`lib/screens/`):**
  - `lib/screens/app_permissions_screen.dart`
  - `lib/screens/focus_setup_preview.dart`
  - `lib/screens/home_preview_screen.dart`
  - `lib/screens/levelup_app_selection_screen.dart`
  - `lib/screens/levelup_focus_setup_screen.dart`
  - `lib/screens/levelup_home_screen.dart`
  - `lib/screens/levelup_permissions_screen.dart`
  - `lib/screens/levelup_splash_screen.dart`
  - `lib/screens/levelup_welcome_screen.dart`
  - `lib/screens/manage_apps_screen.dart`
  - `lib/screens/permissions_setup_preview.dart`
- **Focus Experience (`lib/focus_experience/`):**
  - `lib/focus_experience/focus_exercises.dart`
  - `lib/focus_experience/focus_screens.dart`
  - `lib/focus_experience/focus_style.dart`
- **UI Data Gateways (`lib/data/`):**
  - `lib/data/android_app_catalog.dart`
  - `lib/data/android_usage_gateway.dart`
  - `lib/data/dashboard_data.dart`
  - `lib/data/levelup_permissions.dart`
- **UI Entrypoint & Test Kit (`lib/` & `lib/test_kit/`):**
  - `lib/main_ui.dart`
  - `lib/test_kit/challenge_screen.dart`
  - `lib/test_kit/squat_counter.dart`
  - `lib/test_kit/test_kit_screen.dart`
- **UI Tests (`test/ui/`):**
  - 14 test suites covering app selection, dashboard, focus screens, permissions, and welcome flows.

---

## 4. Dependencies Reconciled

The unified `pubspec.yaml` combines all required runtime and development dependencies:

```yaml
dependencies:
  shared_preferences: ^2.5.6
  flutter:
    sdk: flutter
  camera: ^0.12.2
  camera_android: ^0.10.13
  google_mlkit_pose_detection: ^1.0.3
  material_ui: ^1.11.1
  sqflite: ^2.4.6
  path: ^1.9.1

dev_dependencies:
  flutter_launcher_icons: ^0.14.4
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  sqflite_common_ffi: ^2.4.7

flutter:
  uses-material-design: true
  assets:
    - assets/images/levelup_mark.png
```

---

## 5. Entry Point Status

All three entry points coexist and build cleanly:

1. **`lib/main.dart` (Production Prototype / Core MVP):**
   - Kept unchanged.
   - Verified: Builds debug APK successfully (`build/app/outputs/flutter-apk/app-debug.apk`).
2. **`lib/main_dev.dart` (Developer Lab B2):**
   - Dedicated diagnostic workbench for QA, state machine inspection, database exploration, and scenario testing.
   - Verified: Builds debug APK successfully.
3. **`lib/main_ui.dart` (Teammate UI Preview):**
   - Standalone preview of the splash, onboarding, home dashboard, and presentation components.
   - Verified: Builds debug APK successfully.

---

## 6. Known Incompatible UI Gateways (Isolated for Phase I2)

The teammate's UI preview files were preserved in Phase I1 but contain protocol mismatches and nonexistent channels that must NOT be wired to the production core directly:

1. **`lib/data/levelup_permissions.dart` (`AndroidPermissionGateway`):**
   - Assumes MethodChannel `levelup/permissions` with methods `getStates`, `request`, `openPermissionSettings`.
   - *Status:* Channel does not exist in Android Kotlin. Must be adapted in Phase I2 to delegate to `ISettingsService` and `INativeBridge`.
2. **`lib/data/android_app_catalog.dart` (`AndroidAppCatalog`):**
   - Assumes MethodChannel `levelup/app_catalog` with method `listSupportedApps`.
   - *Status:* Channel does not exist in Android Kotlin. Target packages are strictly constrained to `ChannelConstants.allowedTargets` (YouTube, Instagram, TikTok). Must be backed by a static catalog adapter.
3. **`lib/data/android_usage_gateway.dart` (`AndroidUsageGateway`):**
   - Assumes MethodChannel `levelup/usage` with method `getScreenTime`.
   - *Status:* Channel does not exist in Android Kotlin. Screen time metrics must be derived from `WorkoutHistoryRepository` and `AccessAttemptRepository`, or marked unavailable.
4. **`lib/data/dashboard_data.dart` (`ExistingFocusGateway`):**
   - `claimChallenge()` expects `consumeChallengeRequest` to return `Map<String, String>` (`{'id': ..., 'target': ...}`). Android returns `Boolean`.
   - `completeChallenge()` invokes `grantAccess` with `{'id': ..., 'target': ..., 'repetitions': ...}`. Android expects `{'minutes': Int}`.
   - `cancelChallenge()` calls nonexistent native method.
   - Assumes MethodChannel `levelup/focus_notifications`.
   - *Status:* Must be replaced by `CoreFocusGatewayAdapter` delegating to `IFocusService` and `ICoreIntegrationCoordinator`.
5. **`lib/test_kit/squat_counter.dart` & `lib/test_kit/challenge_screen.dart`:**
   - Incomplete 41-line squat counter and UI challenge controller that bypasses `CoreIntegrationCoordinator` and attempts direct access grants.
   - *Status:* Preserved in `test_kit/` for preview compatibility; strictly prohibited from authoritative unlock flow. Phase I2 will bind the visual components in `focus_experience/focus_screens.dart` to `CoreIntegrationCoordinator`.

---

## 7. Automated Test Results

Executed via `/Users/arsen/development/flutter/bin/flutter test`:

```text
00:10 +393: All tests passed!
```

- **Total Tests:** 393
- **Passed:** 393 (100%)
- **Failed:** 0
- **Skipped:** 0
- **Test Coverage Breakdown:**
  - Core Modules (01–08): NativeBridge, FocusService, ChallengeService, SquatCounter, WorkoutSessionManager, AccessService, LevelUpDatabase, SettingsService.
  - Integration & Coordination: CoreIntegrationCoordinator, PoseEventAdapter, AccessAttemptRepository, WorkoutHistoryRepository.
  - Developer Lab B2: SystemHubScreen, LiveChallengeScreen, HistoryDatabaseScreen, WorkoutResultScreen, TestCenterScreen, GateTimerSessionLifecycle, CriticalIntegrationAudit.
  - UI Preview Tests: AppSelection, Dashboard, FixSprint, FocusExercises, FocusManagement, FocusScreens, FocusSetup, Permissions, PreviewBridge, SquatCounter, UsageAndNotifications, WelcomeScreen, WidgetTest.

---

## 8. APK Build Results

All debug APK targets compiled successfully with Android Gradle plugin and NDK:

| Entry Point | Target | Result | Build Time |
|---|---|---|---|
| `lib/main.dart` | `flutter build apk --debug -t lib/main.dart` | **Success** (`app-debug.apk`) | 87.2s |
| `lib/main_dev.dart` | `flutter build apk --debug -t lib/main_dev.dart` | **Success** (`app-debug.apk`) | 7.0s |
| `lib/main_ui.dart` | `flutter build apk --debug -t lib/main_ui.dart` | **Success** (`app-debug.apk`) | 9.3s |

---

## 9. Remaining Work for Phase I2 (Functional UI/Core Integration)

1. **Adapter Implementation (`lib/app/adapters/`):**
   - `CoreFocusGatewayAdapter`: Implements `DashboardFocusGateway` backed by `IFocusService`.
   - `CorePermissionGatewayAdapter`: Implements `LevelUpPermissionGateway` backed by `ISettingsService` and `ICameraPermissionChecker`.
   - `CoreInsightsAdapter`: Provides `DashboardInsights` backed by SQLite repositories.
   - `AppCatalogAdapter`: Supplies supported targets from `ChannelConstants.allowedTargets`.
2. **Authoritative Challenge View-Model:**
   - Wire `FocusChallengeScreen` (`focus_experience/focus_screens.dart`) to `CoreIntegrationCoordinator`.
   - Ensure camera stream feeds `SquatGeometry` $\rightarrow$ `SquatCounter` $\rightarrow$ `CoreIntegrationCoordinator.handlePoseResult()`.
   - Ensure completion triggers 2-phase idempotent access grant via `AccessService.grantAccessForCompletedWorkout()`.
3. **Unified Production App Shell:**
   - Wire `lib/main.dart` to initialize core services (`DevLabScope` / DI container) and launch the integrated `LevelUpApp` with onboarding and home dashboard.

---

## 10. Physical Device Testing Requirements for Phase I2

- [ ] Clean install on physical Android device (API 24–35).
- [ ] Complete onboarding flow (Welcome $\rightarrow$ App Selection $\rightarrow$ Focus Setup $\rightarrow$ Accessibility Settings).
- [ ] Verify voluntary gate restriction: Open YouTube $\rightarrow$ Accessibility service displays overlay gate.
- [ ] Verify challenge trigger: Tap "Start Challenge" on gate $\rightarrow$ App opens `FocusChallengeScreen`.
- [ ] Verify ML Kit pose tracking: Perform 5 squats $\rightarrow$ Verify repetitions increment and feedback displays.
- [ ] Verify access grant: On 5th repetition, verify native `grantAccess(5)` executes, gate closes, and YouTube opens.
- [ ] Verify expiration: After 5 minutes, verify YouTube is re-blocked by the native accessibility service.
- [ ] Verify Developer Lab: Run `main_dev.dart` and confirm all diagnostics and test center scenarios continue to function.
