# LevelUp — Phase I2B: Real Camera Challenge & Native Unlock Integration

**Document:** Integration Phase I2B Report  
**Date:** November 25, 2026  
**Status:** Completed (Verified via `flutter analyze`, 433 passing tests, and `main_ui.dart` / `main_dev.dart` APK builds; awaiting physical Pixel 7 Pro hardware verification)  
**Branch:** `integration/ui-core`  

---

## 1. Overview

Phase I2B connects the teammate's visual challenge screens (`FocusChallengeScreen` and `FocusAccessGrantedScreen` in `lib/focus_experience/focus_screens.dart`) to the real Camera + Google ML Kit Pose Detection + `CoreIntegrationCoordinator` + `AccessService` + `NativeBridge` pipeline.

The authoritative end-to-end flow is now wired:

> Blocked application $\rightarrow$ Android Accessibility Gate (`LevelUpAccessibilityService`) $\rightarrow$ Start Challenge $\rightarrow$ `CoreIntegrationCoordinator.launchUnlockChallenge(requirePendingRequest: true)` $\rightarrow$ Real Camera (`NV21`) + ML Kit `PoseDetector` + `SquatGeometry` + `PoseEngineAdapter(isSimulated: false)` $\rightarrow$ 5 verified squats $\rightarrow$ `AccessAttemptRepository` 2-phase journal $\rightarrow$ `AccessService.grantAccessForCompletedWorkout` $\rightarrow$ `NativeBridge.grantAccess(minutes: 5)` (300 seconds) $\rightarrow$ Android `unlock_until` expiration & re-blocking.

---

## 2. Actual Controller Architecture

Implemented in `lib/app/challenge/production_challenge_controller.dart` and `lib/app/challenge/production_challenge_screen.dart`:

- **`ProductionChallengeController` (`ChangeNotifier`):**
  - Thin coordinator-backed controller sitting between `FocusChallengeScreen` / `FocusAccessGrantedScreen` and `ICoreIntegrationCoordinator`.
  - Uses `PoseEngineAdapter(isSimulated: false)` (strictly non-simulated, backed by Module 04 `SquatCounter`).
  - Never imports or uses `lib/test_kit/squat_counter.dart` or `lib/test_kit/challenge_screen.dart`.
  - Never calls `NativeBridge.grantAccess` directly; listens to `coordinator.stateStream` and only marks `isUnlockConfirmed = true` when `state.accessGrantStatus == AccessGrantStatus.granted` and `state.unlockUntil` is in the future.
- **`ProductionChallengeScreen` (`StatefulWidget`):**
  - Observes `WidgetsBindingObserver` for app pause/resume interruptions.
  - Renders `FocusChallengeScreen` during active camera/pose tracking, `FocusAccessGrantedScreen` only after confirmed native unlock (`isUnlockConfirmed`), and a localized completion view for voluntary Free Workouts (`isFreeWorkoutCompleted`) without claiming app access was granted.
  - Enforces `PopScope(canPop: !_controller.isFinalizing)` so the user cannot accidentally abort mid-grant confirmation.

---

## 3. Native Request Handoff

- In `lib/main_ui.dart`, `_WelcomeFlowState._checkChallenge()` runs on initial post-frame launch (once onboarding is completed) and on `AppLifecycleState.resumed` (handling both cold launch and live-activity resume from the Android gate overlay).
- When `AppScope` is active, `_checkChallenge()` calls `scope.coordinator.launchUnlockChallenge(requirePendingRequest: true)` directly — **never** pre-calling `consumeChallengeRequest()` beforehand, which would double-consume the atomic `open_challenge` flag in `MainActivity.kt`.
- `CoreIntegrationCoordinator.launchUnlockChallenge` validates:
  1. No active session is already in progress.
  2. Android Accessibility permission is granted.
  3. Voluntary Focus restriction is enabled.
  4. Target package is in `ChannelConstants.allowedTargets`.
  5. `NativeBridge.consumeChallengeRequest()` returns `true` (boolean).
- If valid, `main_ui.dart` pushes `ProductionChallengeScreen(scope: scope, isUnlockChallenge: true, ...)`.
- If invalid or not pending (normal app resume), `launchUnlockChallenge` throws and `_checkChallenge()` exits silently without opening a challenge or granting access.
- Tapping `"Open movement challenge"` on the Challenge tab calls `_openFreeWorkout()`, launching `ProductionChallengeScreen(isUnlockChallenge: false)` which calls `coordinator.launchFreeWorkout()` — guaranteed to never grant native access.

---

## 4. Camera and Pose Lifecycle

1. **Permission Check & User-Triggered Request:**
   - `_ensureCameraPermissionAndOpen()` calls `ICameraPermissionChecker.checkCameraPermission()`.
   - Only if `denied` does it call `requestCameraPermission()` (triggered after user starts the challenge).
   - If `permanentlyDenied` or `restricted`, surfaces a clear localized message and `retry()` opens Android App Details via `NativeBridge.openAppSettings()`.
2. **Camera Acquisition & Stream:**
   - Acquires front camera (`CameraLensDirection.front`, `ResolutionPreset.medium`, `ImageFormatGroup.nv21`, `enableAudio: false`) with a 1500ms timeout guard.
   - Converts `CameraImage` NV21 planes with sensor/device orientation compensation to ML Kit `InputImage`.
   - Extracts hip/knee/ankle landmarks above `SquatGeometry.defaultLikelihoodThreshold` (`0.55`) and computes interior knee angle via `SquatGeometry.calculateKneeAngle`.
   - Missing poses or landmarks pass `null` to `PoseEngineAdapter.processAngle(null)` to reset debounce frames and update user posture hints honestly.
3. **Interruption & Disposal:**
   - `AppLifecycleState.inactive` / `paused` immediately releases `CameraController` (`stopImageStream` + `dispose`) and resets tracking.
   - `AppLifecycleState.resumed` re-checks camera permission and re-opens the camera if the session is still active.
   - `cancel()` and `dispose()` detach `IPoseEventSource`, cancel active sessions, release terminal sessions, close `PoseDetector`, and dispose `CameraController`.

---

## 5. Unlock Authorization Path

1. 5th verified squat transitions `WorkoutSessionManager` to `WorkoutSessionStatus.completed`.
2. `CoreIntegrationCoordinator._executeCompletionWorkflow` persists `WorkoutResult` to `WorkoutHistoryRepository`.
3. `_executeAccessGrantWorkflow` creates a `prepared` record in `AccessAttemptRepository` **before** native invocation.
4. `AccessService.grantAccessForCompletedWorkout` validates eligibility and calls `NativeBridge.grantAccess(minutes: 5)`.
5. `MainActivity.kt` sets `unlock_until = startMs + 300_000L`, triggers `LevelUpAccessibilityService.instance?.reevaluate()`, returns `unlockUntil`, and launches the target app.
6. `CoreIntegrationCoordinator` marks the attempt `confirmed` in SQLite and emits `AccessGrantStatus.granted` + `unlockUntil` to `ProductionChallengeController`, which releases camera hardware and renders `FocusAccessGrantedScreen`.
7. Duplicate frames after 5/5 are ignored by `WorkoutSessionManager` terminal guard and `AccessAttemptRepository` idempotency.

---

## 6. Files Changed / Added

- **Added:**
  - `lib/app/challenge/production_challenge_controller.dart`
  - `lib/app/challenge/production_challenge_screen.dart`
  - `test/app/challenge/production_challenge_test.dart`
  - `docs/integration-phase-i2b.md`
- **Modified:**
  - `lib/main_ui.dart` — Wired `_checkChallenge()` to `CoreIntegrationCoordinator.launchUnlockChallenge(requirePendingRequest: true)` + `ProductionChallengeScreen(isUnlockChallenge: true)` and wired Challenge tab `onMovement` to `_openFreeWorkout()` (`isUnlockChallenge: false`).
  - `test/app/integration_phase_i2a_test.dart` — Updated Test 5 to verify Free Workout launch without `grantAccess`.

Preserved untouched: `lib/main.dart`, `lib/main_dev.dart`, `android/` native blocker & `MainActivity.kt`, `CoreIntegrationCoordinator`, `AccessService`, `SquatCounter`, `SquatGeometry`, and Developer Lab B2.

---

## 7. Automated Verification Results

- **`flutter analyze`:** `No issues found! (ran in 1.2s)`
- **`flutter test`:** **433 passed, 0 failed, 0 skipped**
  - Includes 9 new Phase I2B tests in `test/app/challenge/production_challenge_test.dart` covering gate-triggered launch, single consumption of `consumeChallengeRequest`, stale/missing/ineligible rejection, 0-grant before 5 squats, single 5-min (300s) grant on 5th squat, duplicate completion protection, Free Workout zero-grant, camera permission denial & `openAppSettings`, lifecycle pause/resume & cancellation, and `FocusAccessGrantedScreen` gating on confirmed native grant.
- **APK Builds:**
  - `flutter build apk --debug -t lib/main_ui.dart`: **Success** (`app-debug.apk`, 9.3s)
  - `flutter build apk --debug -t lib/main_dev.dart`: **Success** (`app-debug.apk`, 5.0s)

---

## 8. Remaining Limitations

- Physical Android camera streaming (`NV21` orientation + ML Kit latency) and `MainActivity` $\leftrightarrow$ `LevelUpAccessibilityService` task switching have not been executed on physical hardware in this automated environment.
- Legacy `lib/test_kit/` files remain isolated on disk for `test/ui/` compatibility; they are unreachable from `AppScope`-backed production `main_ui.dart`.
- Module 09 (XP & Progress Engine), OS Screen Time (`UsageStatsManager`), and Notifications remain unimplemented.

---

## 9. Physical Pixel 7 Pro Verification Checklist

- [ ] Install `flutter run -t lib/main_ui.dart` (or `app-debug.apk`) on Pixel 7 Pro.
- [ ] Complete onboarding, grant Accessibility Service in Android Settings, and enable Focus for YouTube.
- [ ] Open YouTube $\rightarrow$ verify `LevelUpAccessibilityService` displays the latched overlay gate.
- [ ] Tap **Start Challenge** on the gate overlay $\rightarrow$ verify LevelUp opens `ProductionChallengeScreen` (both when LevelUp was killed and when LevelUp was alive in background).
- [ ] Grant Camera permission when prompted $\rightarrow$ verify live front-camera preview and `"Pose detected"` / `"Поза распознана"` badge.
- [ ] Perform 4 squats $\rightarrow$ verify counter shows `4 / 5` and YouTube remains locked.
- [ ] Perform 5th squat $\rightarrow$ verify `FocusAccessGrantedScreen` (`5 min`), native `grantAccess(5)` executes, and YouTube launches automatically.
- [ ] Wait 300 seconds (5 minutes) $\rightarrow$ verify `LevelUpAccessibilityService` re-blocks YouTube.
- [ ] Open Challenge tab $\rightarrow$ tap **Open movement challenge** (Free Workout) $\rightarrow$ complete 5 squats $\rightarrow$ verify completion screen appears and YouTube remains blocked (no access granted).
- [ ] Test backgrounding mid-challenge (Home button $\rightarrow$ resume) and cancelling mid-challenge $\rightarrow$ verify camera releases cleanly and no access is granted.
- [ ] Run `flutter run -t lib/main_dev.dart` $\rightarrow$ confirm Developer Lab B2 remains 100% functional.

---

## 10. Required Follow-Up Work

1. Execute the Pixel 7 Pro physical device verification checklist above and confirm logcat `LevelUpGate` (`GRANT_ACCESS`, `unlockUntil`, re-block) matches expectations.
2. After hardware sign-off, promote the integrated UI from `lib/main_ui.dart` to `lib/main.dart` (preserving `lib/main_dev.dart`).
3. Implement Module 09 (XP & Progress Engine) if progression/XP is required post-MVP.
