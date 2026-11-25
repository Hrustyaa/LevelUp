# Module 12A — MVP stability, security and integration audit

## Scope and starting state

The audit began on `integration/ui-core` at `d90a743`. The worktree already had copy edits in the native AccessibilityService and Gate layout and an untracked `AGENTS.md`. The copy and instructions were preserved. Modules 11D.1 through 11D.3 supplied the current camera, exercise, authorization and rewards designs. Pre-change analysis reported zero issues and all 564 Flutter tests passed.

The audit prioritized native authorization and verification provenance, followed by camera ownership, persistence and reward recovery, then lifecycle, UI and build regressions.

## Architecture assessment

The production flow remains Gate → Flutter challenge route → raw ML Kit landmarks → the selected session-bound counter → CoreIntegrationCoordinator → SQLite history and native-access journal → AccessService → Android. The default Flutter entry point now uses the same production flow as `main_ui.dart`. Developer Lab simulation uses its separate database and bridge. Developer Lab real-device squats use the same raw-landmark counter and authorization checks as the main app.

The repaired authorization and persistence paths are ready for device validation. The scope remains one Gate implementation, one active exercise and one native grant workflow. SQLite history backs production statistics, the XP journal backs levels and streaks, and achievements consume those snapshots. The overlay consumes a presentation copy of landmarks and has no input into verification.

## Confirmed findings and fixes

The audit found three high-severity defects and no critical defects in the reviewed paths.

| Severity | Finding | Resolution |
| --- | --- | --- |
| High | Squats accepted detached counter results and lacked the session-bound completion evidence already used for push-ups. Real native access exposed a direct request path alongside the coordinator. | Both camera adapters now issue matching completion evidence at five reps. The live coordinator, native AccessService and production XP/history writes require that evidence. Headless test and simulation bridges remain separate. |
| High | Android did not match a grant to a consumed Gate request and could issue an expiry after the selected target or eligibility changed between Dart checks and native completion. | Android claims the tapped target and checks it again immediately before committing a one-use five-minute grant. Target changes, Focus disable and reset invalidate a claim. Reapplying the same target preserves an existing timer. |
| High | Two launches could overlap while the first unlock was waiting on native state or a Gate claim. | The coordinator reserves launch ownership before its first asynchronous step. It rejects a second unlock or Free Workout while the first claim is pending. The completion signal reports the recorded failure to late waiters and duplicate callbacks share the original result. |
| Medium | The live squat counter could retain an unfinished descent across a lifecycle interruption or extended loss of tracking. Detector errors could leave previously valid form visible. | The camera adapter discards partial squat phases on interruption or loss beyond 500 ms. Equivalent pose thresholds are retained. Failed detection clears tracking and visual form state. A startup watchdog reports a stalled camera instead of showing indefinite loading. |
| Medium | XP recovery considered only the newest 50 workouts. A malformed persisted epoch could block initialization, and the XP snapshot loaded every reward row. | Recovery queries unrewarded, eligible post-epoch sessions in bounded batches. A damaged epoch falls back to the current activation time, so older workouts do not receive retroactive XP. The normal XP snapshot reads totals, the 20 newest rewards and distinct workout days. |
| Medium | Closing SQLite during its first open could leave a late connection open. A failed open could emit an extra unhandled future error. Developer Lab fixtures could delete a database ahead of asynchronous close. | Database open and close share their in-flight operations. AppScope disposal is awaitable and drains active scope work. Developer Lab leaves injected connections to their owners, and teardown fixtures await close. |
| Medium | Unknown squat source markers and short workouts could inflate verified totals. A Developer Lab receipt could display another session’s native timer. | Statistics and dashboard activity admit the known verification markers and completion counts. Receipts match the confirmed attempt to the live target and expiry. |
| Low | Superseded dashboard reads could leave timeout timers behind and overwrite refresh signatures. Developer Lab result loads and camera callbacks also lacked complete stale-operation checks. | Dashboard reads cancel their timers on supersession and disposal. Developer Lab applies only the latest result read and serializes camera transitions by generation. |

No app redesign was needed. The Workout picker still returns a selection before camera initialization, uses the existing EN/RU/KK labels, supports large text and prevents duplicate starts. The saved Focus selection applies to future sessions, including when a previous grant is active.

## Authorization and progress invariants

- A normal squat or push-up unlock requires the selected app’s Gate claim and five repetitions from the selected exercise. Android commits an expiry exactly `300_000` ms after its grant timestamp. Gate policy tests cover expiry, Home, and foreground changes, with device navigation still to verify.
- Free Workout earns eligible XP while skipping the native grant workflow. Incomplete and cancelled sessions never reach its completion workflow. Simulated Developer Lab activity cannot reach a real grant or production XP.
- A UI-selected exercise, detached pose result, or caller-supplied source string cannot confer live production verification. The proof is checked against session, request, challenge, exercise, target and repetition count. Existing camera rows remain readable for post-epoch reward recovery. Experimental push-ups and unknown sources remain excluded.
- The XP and achievements journals retain their primary keys and historical rows. First Workout, Five Workouts and streaks include eligible squats or push-ups. Level 2 follows the XP ledger, First Unlock follows confirmed access, and 25 Squats still reads squat repetitions only. Authorized access duration remains distinct from screen time.
- The v1→v5, v2→v5, v3→v5 and v4→v5 fixtures verify workouts, access attempts, settings, XP, epoch and achievements preservation. Module 12A introduces no schema migration or database reset.

## Camera and lifecycle assessment

The main flow opens one camera stream and one lazy ML Kit detector per active route. Serialized transitions wait for previous camera teardown, and camera, session and adapter checks reject late frames. The move to a shared squat landmark helper retains the existing knee-angle thresholds and checks finite coordinates and confidence. Push-up thresholds are unchanged.

Front-camera coordinate mapping, mirror, preview clipping, One Euro filtering, temporal outlier rejection and visibility hysteresis are covered by the existing geometry and overlay tests. They remain separate from both counters. Automated poses and a mock native channel do not measure physical gesture accuracy or real preview alignment.

## Validation

| Check | Result |
| --- | --- |
| Pre-change Flutter tests | 564 passed |
| `flutter pub get` | Passed. Seven newer package versions are outside the current constraints. |
| `flutter analyze --no-pub` | Passed with zero issues. |
| `flutter test --no-pub --timeout 45s --reporter expanded` | All 570 passed, including six new Flutter tests. |
| Android `:app:testDebugUnitTest` | All 16 passed with Android Studio’s bundled JDK, including two new authorization tests. |
| `flutter build apk --debug -t lib/main_ui.dart --no-pub` | Passed in 9.7 seconds. |
| `flutter build apk --debug -t lib/main_dev.dart --no-pub` | Passed in 6.4 seconds. |
| `flutter build apk --release -t lib/main_ui.dart --no-pub` | Blocked at `:app:compileFlutterBuildRelease` after 242.4 seconds. macOS Gatekeeper prompted for the installed Flutter SDK’s `gen_snapshot` and `font-subset` tools. All three AOT targets and font subsetting exited with code `-9`. No release APK was produced. |

The debug APKs are available as `build/app/outputs/flutter-apk/levelup-12a-main_ui-debug.apk` and `build/app/outputs/flutter-apk/levelup-12a-main_dev-debug.apk`. Both were built without developer feature flags.

Added regressions cover Gate claims, overlapping launch requests, detached verification, live XP rejection, older missing rewards, malformed epoch recovery, concurrent SQLite open failures and close/reopen, and interrupted squats. Existing integration tests now feed the real session-bound camera counter where they previously supplied completed squat snapshots. The Developer Lab receipt regression also covers an active timer for another target.

## Files and Git state

Module 12A changed 47 files. The existing changes in `view_levelup_gate.xml` and `AGENTS.md` account for two additional worktree entries. The AccessibilityService retains the existing Gate copy alongside the authorization changes.

The checkout remains on `integration/ui-core` at `d90a743` with 43 modified tracked files, six untracked files and no staged changes.

<details>
<summary>Android policy, service and JVM tests (4)</summary>

- `android/app/src/main/kotlin/com/levelup/levelup_test/GateAuthorization.kt`
- `android/app/src/main/kotlin/com/levelup/levelup_test/LevelUpAccessibilityService.kt`
- `android/app/src/main/kotlin/com/levelup/levelup_test/MainActivity.kt`
- `android/app/src/test/kotlin/com/levelup/levelup_test/GateAuthorizationTest.kt`

</details>

<details>
<summary>Audit report (1)</summary>

- `docs/module-12a-stability-audit.md`

</details>

<details>
<summary>Flutter application, services and persistence (21)</summary>

- `lib/app/adapters/core_insights_adapter.dart`
- `lib/app/challenge/production_challenge_controller.dart`
- `lib/app/di/app_scope.dart`
- `lib/core/integration/core_integration_coordinator.dart`
- `lib/core/integration/pose_event_adapter.dart`
- `lib/data/database/levelup_database.dart`
- `lib/data/repositories/workout_history_repository.dart`
- `lib/features/developer_lab/di/dev_lab_scope.dart`
- `lib/features/developer_lab/screens/live_challenge_screen.dart`
- `lib/features/developer_lab/screens/workout_result_screen.dart`
- `lib/features/pose_detection/application/squat_counter.dart`
- `lib/features/pose_detection/application/squat_geometry.dart`
- `lib/features/progress/application/progress_service.dart`
- `lib/features/progress/data/progress_repository.dart`
- `lib/features/statistics/data/statistics_repository.dart`
- `lib/main.dart`
- `lib/models/workout_result.dart`
- `lib/models/workout_session.dart`
- `lib/screens/levelup_home_screen.dart`
- `lib/services/access_service.dart`
- `lib/services/native_bridge.dart`

</details>

<details>
<summary>Flutter regression tests and fixtures (21)</summary>

- `test/app/challenge/production_challenge_test.dart`
- `test/app/di/app_scope_test.dart`
- `test/app/integration_module_09b_test.dart`
- `test/app/integration_module_10b_test.dart`
- `test/app/integration_module_11b_test.dart`
- `test/app/integration_phase_i2c_test.dart`
- `test/data/levelup_database_test.dart`
- `test/developer_lab/critical_integration_audit_test.dart`
- `test/developer_lab/dev_lab_scope_test.dart`
- `test/developer_lab/gate_timer_session_lifecycle_test.dart`
- `test/developer_lab/history_database_screen_test.dart`
- `test/developer_lab/live_challenge_screen_test.dart`
- `test/developer_lab/preflight_focus_screen_test.dart`
- `test/developer_lab/system_hub_screen_test.dart`
- `test/developer_lab/test_center_screen_test.dart`
- `test/developer_lab/workout_result_screen_test.dart`
- `test/features/achievements/achievements_engine_test.dart`
- `test/features/pose_detection/squat_camera_pose_adapter_test.dart`
- `test/features/progress/progress_engine_test.dart`
- `test/features/statistics/statistics_engine_test.dart`
- `test/support/verified_squat_frames.dart`

</details>

## Remaining risks and Module 12B test order

**High priority for device QA.** ADB found no attached Pixel 7 Pro. The full Android lifecycle, window and AccessibilityService behavior and real exercise recognition remain pending on the audited APK. The user’s Module 11D.3 device experience applies to that earlier build.

**Medium.** A platform plugin that never returns can hold the serial camera teardown despite the startup watchdog. Confirm app recovery after camera permission changes, rapid activity transitions and process recreation. Native expiry retains the existing wall-clock basis. The journal deliberately leaves an uncertain interrupted grant for reconciliation rather than reissuing it.

**Release validation.** A trusted local Flutter release toolchain is required to rerun the release build. The repository release configuration uses its existing debug signing configuration, so store-distribution signing remains outside this audit.

Run the Pixel 7 Pro regression in this order.

1. Protect one app and trigger the native Gate normally. Repeat with squats and frontal push-ups. Verify zero grants at four reps, one grant at five, and restriction returning at 300 seconds. Exercise Home, Recents, screen lock, app switching and target changes.
2. Disable Focus or revoke Accessibility while a challenge is open, cancel before completion, background and resume the app, and restart during a persisted grant. Confirm eligibility and expiry remain authoritative.
3. Run both Free Workouts, cancel during camera acquisition and at partial progress, and switch exercise on the next route. Check camera errors and reconstruction, overlay alignment in different orientations and distances, genuine reps, partial reps and temporary landmark loss.
4. Reopen progress and history after restart. Confirm two eligible exercise paths award 50 XP once, weekly totals stay separate, historical experimental rows stay unverified and 25 Squats stays squat-specific.
5. Run the same ordinary APK with EN/RU/KK, compact display and large text. Finish with Developer Lab simulation isolation and the real-device diagnostic route.

Module 12B work was not started in this audit.
