# Module 11D.3 — MVP feature completion

## Starting point

Work began on `integration/ui-core` at `aa4a377`. The worktree already contained copy edits in `LevelUpAccessibilityService.kt` and `view_levelup_gate.xml`, plus an untracked `AGENTS.md`. Those files were preserved. The checked-out Module 11D.2 baseline passed all 558 tests. The final worktree has 36 modified and 3 untracked files. No changes were staged, committed or pushed.

The user reported manually testing frontal push-ups on their Pixel 7 Pro and approved production use. Module 11D.3 removes the debug capability gate for push-up access and XP. The optional `LEVELUP_DEBUG_PUSH_UP_DIAGNOSTICS` flag still controls debug-only diagnostic messages.

## Focus exercises and native access

**Focus Rules → Exercises** offers **Squats · 5 reps** and **Push-ups · 5 reps** in ordinary builds. The screen uses the existing checkbox cards and Save action, with scrollable guidance for large text. Selecting one exercise assigns it to future unlock challenges. Selecting both preserves the existing rotation. The SharedPreferences keys retain both the saved selection and last assignment. Free Workout continues to store its own last-started exercise in SQLite.

The native Gate starts the existing ChallengeService → CoreIntegrationCoordinator → AccessService workflow. The coordinator captures the selected exercise and session ID when the challenge starts. Changing the saved preference affects future sessions and leaves the current camera challenge, selected apps, Focus state and native timer alone.

A live push-up adapter binds to a single session and issues completion evidence after the fifth counted repetition. The evidence carries the session, request, challenge, target and repetition count. The coordinator accepts push-up completion through that bound adapter. The same access journal records the resulting 300-second request, and the existing native confirmation drives the success screen. A manual result, simulated push-up, or reloaded history row cannot issue a push-up grant. Free Workout never calls the native grant workflow.

## XP, history, statistics and achievements

Five verified squats or push-ups earn 50 XP once per eligible session. New verified push-ups store `camera_pushup_verified`. The live XP path and workout repository require matching camera completion evidence, so supplying the source string alone cannot earn XP or create a trusted history row. The repository’s validated marker supports recovery if the reward write fails after history is saved. Existing `progress_epoch_ms` rules, XP IDs, levels and streak calculations remain in use.

Historical `experimental_unverified` push-ups remain readable and earn no retroactive XP or production statistics. Simulated, incomplete and cancelled workouts earn no XP. SQLite stays at schema v5 with no migration or data rewrite.

Production statistics include total workouts, squat and push-up workout counts, separate repetition totals, weekly activity and confirmed native unlocks. Authorized access is still reported as access duration. The existing statistics card adds a verified push-up total. First Workout and Five Workouts count both exercises, Three-Day Streak and Reach Level 2 use the existing reward ledger, and First Unlock uses confirmed grants. The 25 Squats achievement reads the squat-only repetition total. Existing achievement identifiers and unlock records are preserved.

## Workout selection and camera interface

**Challenges → Workout** opens a redesigned exercise picker with two full-width cards. Each shows the exercise name, an explanation, five reps, 50 XP and a visible selection indicator. The camera setup note follows the chosen exercise. The short-screen layout scrolls while the Start Workout button stays in the safe area. English, Russian and Kazakh use the existing fonts, dark surfaces, lime accent, Material icons and LevelUp primary button.

The picker only returns an `ExerciseType`. **Start Workout** creates the selected exercise’s controller, which uses one pose adapter and the existing camera and ML Kit pipeline. The camera screen keeps its controls, guidance, repetition counter and full-body white/lime overlay. The One Euro Filter, temporal outlier guard and visibility hysteresis still affect presentation only. Session and camera epoch guards still reject old callbacks.

## Automated verification

| Check | Result |
| --- | --- |
| Module 11D.2 baseline | 558 passed |
| `flutter pub get` | Passed |
| `flutter analyze --no-pub` | 0 issues |
| `flutter test --no-pub` | 564 passed |
| `flutter build apk --debug -t lib/main_ui.dart --no-pub` | Passed without feature flags |
| `flutter build apk --debug -t lib/main_dev.dart --no-pub` | Passed without feature flags |

The production configuration contains no push-up unlock capability define in Flutter or Android. The regression tests exercise both ordinary Focus choices, a reload of the saved preference, pre-camera selection and rapid Start taps, cancellation, one counter per workout, camera pause/resume, stale-session isolation, two 300-second challenge paths, exactly-once XP, forged and simulated result rejection, mixed-exercise weekly statistics and achievements, legacy history, and SQLite v1–v5 compatibility. Selector coverage includes English, Russian and Kazakh, plus large text in a small viewport.

## Pixel 7 Pro checklist and Module 12A handoff

ADB found no attached device during implementation. The user’s earlier manual test authorized activation. The updated build has automated coverage and still needs the following device regression pass.

- [ ] Install the ordinary `main_ui` APK. Confirm both Focus exercise choices, pick each in turn, restart and trigger the Gate for the selected app.
- [ ] In each challenge, confirm zero access after four reps and one grant after five. Confirm the Gate returns when 300 seconds expire.
- [ ] Change the preference while an unlock is active and check that its expiry remains the same. Trigger the next challenge and verify the new selection.
- [ ] In Workout, pick each exercise before tapping Start. Verify the camera stays closed while selecting. Repeat with large text and a smaller display, and cancel during camera setup and active tracking.
- [ ] Check frontal push-up counting and overlay alignment in varied lighting and camera positions. Include partial reps, arm-only movement and a brief loss of tracking.
- [ ] Confirm 50 XP per verified session, correct weekly statistics and achievement progress, and zero app access from Free Workout.

A frontal monocular camera can miss motion when joints are occluded or have little projected movement. Completion evidence enforces the application’s camera path and session identity. Module 12A can audit device lifecycle behavior, permission revocation, native journal reconciliation, and broader physical accuracy. Module 12A work did not start here.

## Files changed in Module 11D.3

- `docs/` — `module-11d3-mvp-feature-completion.md`.
- `lib/app/adapters/` — `core_insights_adapter.dart`.
- `lib/app/challenge/` — `production_challenge_controller.dart`, `production_challenge_screen.dart`, `workout_exercise_screen.dart`.
- `lib/core/integration/` — `core_integration_coordinator.dart`, `pose_event_adapter.dart`.
- `lib/data/repositories/` — `workout_history_repository.dart`.
- `lib/features/achievements/application/` — `achievement_service.dart`.
- `lib/features/challenge/application/` — `challenge_service.dart`, `push_up_verification.dart`.
- `lib/features/challenge/data/` — `challenge_catalog.dart`.
- `lib/features/pose_detection/application/` — `push_up_counter.dart`.
- `lib/features/progress/application/` — `progress_service.dart`, `xp_reward_policy.dart`.
- `lib/features/settings/models/` — `app_settings.dart`.
- `lib/features/statistics/data/` — `statistics_repository.dart`.
- `lib/features/statistics/models/` — `daily_activity_stats.dart`, `workout_statistics.dart`.
- `lib/focus_experience/` — `focus_exercises.dart`, `focus_screens.dart`.
- `lib/` — `main_ui.dart`.
- `lib/models/` — `access_grant_request.dart`, `exercise_type.dart`, `workout_result.dart`, `workout_session.dart`.
- `lib/screens/` — `levelup_home_screen.dart`.
- `lib/services/` — `access_service.dart`.
- `test/app/challenge/` — `production_challenge_test.dart`, `workout_exercise_screen_test.dart`.
- `test/app/` — `integration_phase_i2a_test.dart`.
- `test/features/challenge/` — `challenge_service_test.dart`.
- `test/features/pose_detection/` — `module_11d_test.dart`.
- `test/features/progress/` — `progress_engine_test.dart`.
- `test/ui/` — `focus_exercises_test.dart`, `focus_screens_test.dart`.
