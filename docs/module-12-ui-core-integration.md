# Module 12 — Final frontend and Core integration

## Git and merge

The checkout started clean on `integration/ui-core` at `4cc4b97284e284b39ddcf40d164a0100e5baf510`. Modules 11D through 12A were already committed. No checkpoint approval was required. `git fetch origin --prune` succeeded. Both `git ls-remote origin refs/heads/feature/ui` and `git rev-parse origin/feature/ui` returned `8b14609b11d911c111370e8dd190788dbab58948`, following `f2c5491`. The merge used `git merge --no-ff --no-commit origin/feature/ui` with the original integration branch checked out.

| Conflicted file | Resolution |
| --- | --- |
| `LevelUpAccessibilityService.kt` | Retained the audited window lifecycle and target claim. Replaced the old layout binding with the teammate’s Gate view and kept a visible safe-exit action. |
| `MainActivity.kt` | Retained the audited grant, expiry and state cases. Registered the teammate’s app catalog, usage, permission and notification channels and the permission callback lifecycle. |
| `lib/data/dashboard_data.dart` | Kept the Core insight models and combined them with the teammate’s Android screen-time data and preview compatibility. |
| `lib/main.dart` | Used the shared production entry point. Both the default launch and `main_ui.dart` start the audited app. |
| `lib/screens/levelup_home_screen.dart` | Combined the teammate’s tabs and shell with Core refresh, workout navigation, persisted controls and achievement state. |

## Feature Reconciliation Report

| Feature | Source and final presentation | Core binding and disposition |
| --- | --- | --- |
| Welcome and onboarding | `feature/ui` polished welcome with language choice and explanatory sheet. Existing app selection, setup and permission steps remain in the flow. | SharedPreferences retains language, draft and onboarding status. Onboarding never enables Focus or requests temporary access. |
| Home | `feature/ui` dashboard, cards, navigation and setup checklist. | Core progress supplies XP, level, progress and activity. Real permission and selected-app state feed the checklist. Android Usage Access provides measured usage where available. |
| Focus and Focus Rules | `feature/ui` Focus shell, rules panel and editable drafts, with a localized exercise row. | `FocusService` verifies status, enables and disables protection, and controls the single target. Draft schedules, sessions and custom access durations are shown as unsupported by the current engine. The saved exercise applies to future challenges. |
| Manage Apps and Permissions | `feature/ui` searchable app picker and permission page. | Native catalog shows installed supported apps. Target selection uses the existing Focus service. Accessibility and camera stay on the Core gateway, with optional usage and notification permissions from the supplemental Android channel. |
| Native Gate | `feature/ui` Gate v2 card, app icon and call to action in the audited Android overlay. | The existing target-bound claim remains the only pending request. Exercise-neutral copy accommodates both counters. The Go Back action uses the audited exit behavior. |
| Challenges and Quick Reset | `feature/ui` workout card, other-exercise section and one-minute break. | The workout card opens the real details and exercise selector. The duplicate movement action was removed. Quick Reset remains camera-free, with no XP or access side effects. |
| Workout details, camera and result | `feature/ui` details layout, Focus v2 full-bleed camera and success/error presentation, and workout result screen. | Both exercise cards return an explicit selection before camera initialization. The one production controller owns the stream, detector, chosen counter and cancellation. The overlay shares the preview crop. Unlock success follows native confirmation. The result screen reads the persisted workout by session ID. The old independent camera and unrestricted multi-set source are kept for reference and tests, outside the production route. |
| Progress and workout history | `feature/ui` workout and Focus pages with period controls, chart, history, filters and detail views. | The workout chart uses verified SQLite history for the last 30 days. History can load older verified records. Exercise identities and verification sources remain distinct. Usage access reports measured time. Unlock history filters the Core’s recent activity to confirmed access. |
| Levels, streaks and achievements | Core cards supplement the teammate’s Progress screen. `feature/ui` supplied no separate authoritative achievement page. | The existing XP ledger, statistics and achievement snapshots drive the views. General workout achievements accept both exercises, 25 Squats stays squat-specific, and First Unlock depends on confirmed access. |
| Settings and language | `feature/ui` Settings, privacy, about, notifications, and unlock challenge screens. | EN/RU/KK and existing SQLite settings persist. Both Focus exercises are selectable and use the existing preferences and rotation. Manual focus notifications are optional. Developer Lab remains a separate Flutter entry point. |
| Launcher | `feature/ui` supplied the original artwork in `assets/images/app_icon.png` and `assets/images/app_icon_foreground.png`, density-specific legacy icons, and regular and round adaptive resources. | The main manifest sets `Level Up`, `@mipmap/ic_launcher` and `@mipmap/ic_launcher_round`. The packaged application ID, MainActivity and accessibility service identity are preserved. |

## Authorization, persistence and lifecycle

CoreIntegrationCoordinator, GateAuthorization, AccessService, FocusService, the verification adapters and counters, XP policy, SQLite schema and migrations remain the committed Module 12A implementations. AppScope only adds optional permission presentation wiring. The Gate visuals feed the existing Android request path. An unlock needs a matching one-use claim, one active challenge and five verified reps for the selected exercise. Android persists a 300-second grant. Free Workout never enters the grant path. SQLite v5 retains workout history, access attempts, settings, XP, achievements and the progress epoch. Camera presentation uses the existing overlay painter and its confidence and smoothing behavior. The Progress tab cancels superseded and disposed read timers. No database reset or new migration was introduced.

The approval and permission channels report real state. Scheduled Focus, timed resumes, configurable unlock duration, unlimited sets, unsupported extra exercises and screen time saved remain outside the available Core capabilities. Their existing visual entries are represented as drafts, unavailable options or an accurate empty state. The legacy preview widgets and fixtures remain available for testing where they have separate supported uses. Historical SQLite data remains readable under the original verification policy. Prototype-only SharedPreferences workout results are excluded from production statistics and rewards.

## Regression and artifact verification

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed. Seven newer packages are outside the current constraints. |
| `flutter analyze --no-pub` | Passed with zero issues. |
| `flutter test --no-pub --reporter expanded --timeout 45s` | 633 passed in 23 seconds. |
| Gradle `:app:testDebugUnitTest` with Android Studio’s JDK | 16 passed. The two Gate authorization and 14 Gate lifecycle tests had zero failures, errors, or skips. |
| `flutter build apk --debug -t lib/main_ui.dart --no-pub` | Passed in 9.7 seconds. `build/app/outputs/flutter-apk/levelup-final-main_ui-debug.apk`. |
| `flutter build apk --debug -t lib/main_dev.dart --no-pub` | Passed in 7.4 seconds. `build/app/outputs/flutter-apk/levelup-final-main_dev-debug.apk`. |
| `aapt2 dump badging` and manifest inspection | Both APKs report `Level Up`, the official adaptive icon resource, round icon and `com.levelup.levelup_test`. The AccessibilityService retains its bind permission. `apksigner verify` passed for both APKs. |
| `flutter build apk --release -t lib/main_ui.dart --no-pub` | Release remains blocked in the local SDK. `codesign --verify --strict` reported invalid arm64 signatures on the three `gen_snapshot` binaries and `font-subset`. Module 12A recorded exit `-9` for those tools. An unchanged release retry would use the same invalid binaries. The common manifest supplies release branding. |
| `adb devices -l` | No connected or authorized devices were listed. An installed launcher and physical camera/Gate behavior remain unverified. |

Two tests specifically cover the new bindings. One verifies verified workout identity, exclusion of simulated and experimental rows and access to older history. The other verifies optional Android permissions and confirms that they do not authorize access. Four compact-layout regressions cover the workout selector, camera controls, unlock confirmation and error recovery in EN/RU/KK. Existing UI integration assertions now use the teammate’s widget routes and retain the original security, persistence and reward assertions.

## Visual comparison

Flutter widget captures from the archived frontend commit and merged screens used a 390 × 844 logical viewport with matched input fixtures. They are available in `build/levelup-integration-previews`, with the frontend captures under `reference`. The polished welcome capture matched exactly. The dashboard retained the reference layout and added the authoritative total XP label. Challenges retained the workout and Quick Reset cards. Settings retained the grouped rows and routes. The input fixtures produced empty history, sample activity and unknown optional permissions in some captures. Those states describe the test data.

The initial merge put the new Core summary ahead of the teammate’s Progress chart and period controls and omitted Access options from the newer Focus Rules panel. The final layout puts the chart and controls first again and restores the Access options row. The duplicate workout action was intentionally reconciled into the workout card. No complete screen was removed.

At 320 × 568 with 200% text, the unlock receipt overflowed vertically with bundled Roboto. The standard Flutter test font also exposed a narrow camera count and overflowing error content. The count now fits its available width, and the receipt and camera error screens scroll when their existing content needs room. The four compact-layout tests pass in EN/RU/KK. Earlier square icons and the debug ribbon came from the widget capture harness and were corrected there. The supplemental Roboto probe reached layout without reporting overflow after the changes and then reported a font-change scheduler callback during test teardown. The standard suite passed independently. Native camera preview, overlay alignment and launcher appearance on Android still need a physical check.

## Review and Module 12B handoff

The merge is staged for review with both ancestries preserved in the pending merge. The index contains 92 changed files with no unresolved conflicts or unstaged project changes. Inspect the final file inventory with `git diff --cached --name-status` and inspect the full changes with `git diff --cached`. Once accepted, finalize with `git commit` on `integration/ui-core`. Push only when authorized. No final merge commit or push was performed.

1. Install the main debug APK on the Pixel 7 Pro. Verify the **Level Up** label and original launcher art, first-run and existing-install navigation, and EN/RU/KK at normal and large text.
2. Test explicit Focus enable and disable, a protected app, Manage Apps, permission changes, Home, Recents and returning to Level Up. Repeat both real Gate exercises, verify no grant at four reps, one grant at five and restriction returning after 300 seconds.
3. Exercise both Free Workouts on-device. Check front-camera mirror, skeleton alignment, permissions, interrupted movement, cancellation and background/resume. Confirm no grant from the free route.
4. Verify one 50 XP award per eligible workout, period filters, history, independent squat and push-up totals, confirmed access, achievements and persistence after restart. Test optional Android usage data and notification delivery with and without permission.
5. Verify release compilation using a trusted Flutter SDK and inspect its packaged branding. Module 12B has not started.
