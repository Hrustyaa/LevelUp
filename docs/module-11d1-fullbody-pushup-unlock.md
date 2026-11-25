# Module 11D.1 — Full-body pose and experimental push-up unlock

## Starting point

The clean `integration/ui-core` checkout at `04a4525` contained Modules 11C and 11D. ML Kit supplied raw frames to squat and experimental push-up counters. The overlay showed legs for squats and arms for push-ups. Push-ups were available in Free Workout, and the only native unlock challenge was five squats. SQLite v5 already supported both exercise types and a verification source per workout.

## Overlay and counting

Both exercises now render the shoulder and hip crossbars, both sides of the torso, shoulder–elbow–wrist on each side, and hip–knee–ankle on each side. Each edge needs two mapped endpoints. A missing wrist can hide the forearm while leaving the upper arm and torso visible. The painter uses LevelUp’s existing white and lime, 5.5 logical-pixel rounded strokes, and line primitives only. No joint markers or glow are drawn.

The existing One Euro smoother, outlier guard and visibility hysteresis operate per joint. A briefly lost joint can retain its last observed position for up to 250 ms while a pose is still present. An uncertain edge fades to white. A frame with no pose clears the overlay. Mapping still uses the camera preview’s rotation, crop or letterboxing, and front-camera mirror. Raw landmarks drive repetition counting independently of the overlay.

The previous single-arm 2D angle could stay nearly straight through an entire head-on repetition as the elbow bent along the camera’s depth axis. The new live counter requires both arms and a front-facing plank with extended legs and feet receding behind the hips. It confirms an extended top, measures downward shoulder and hip travel normalized by shoulder width, checks clearance above the wrists and bilateral elbow flexion, and requires a return to the original top. The hands must remain near their starting positions. Both phase transitions require two consecutive qualifying frames. The counter preserves an in-flight repetition for up to 300 ms of confidence loss, abandons it on a large jump or lifecycle interruption, and counts once per completed cycle.

Start in a high plank with the front camera facing you. Position the phone just above the floor and tilt it slightly down so the shoulders, hands, hips, knees and feet are visible. ML Kit’s relative depth is an experimental estimate. As an inference, foreshortening, occlusion, lighting, and camera position can still cause missed repetitions or false positives. The camera cannot directly verify contact with the floor. [Google ML Kit pose detection](https://developers.google.com/ml-kit/vision/pose-detection#z_coordinate)

## Focus and native access

A debug build with `--dart-define=LEVELUP_TEST_PUSH_UP_UNLOCK=true` makes **Push-ups** selectable in the existing **Focus → Exercises** checklist. Select one exercise to always receive it, or select both to use the existing rotation. The saved choice and rotation survive a restart. The native Gate displays exercise-neutral wording until Flutter presents the assigned exercise.

The push-up challenge runs through `ChallengeService`, `CoreIntegrationCoordinator`, `AccessService`, and the existing native grant journal. Five completed repetitions are required and the existing grant lasts 300 seconds. A direct access request cannot stand in for a completed push-up workout. Free Workout never requests access. Ordinary builds continue to use squats for unlocks. The debug switch is ignored in profile and release builds.

## XP, statistics, and history

Five eligible camera-verified squats still earn +50 XP once per session. Unvalidated push-ups retain `experimental_unverified` in SQLite and remain outside production XP, streaks, activity statistics and achievements. Experimental native grants remain in the access journal for diagnostics and are excluded from production unlock totals. A workout that consumes simulated repetitions retains the `simulated` source. Incomplete workouts earn no XP.

After physical sign-off, newly recorded push-up sessions can use the dedicated `camera_pushup_verified` source and earn +50 XP through the same per-session ledger. Eligible sessions contribute to **First Workout** and **Five Workouts**. **25 Squats** and squat totals count squat repetitions only. History rejects a conflicting verification source for an existing workout ID. SQLite remains at schema v5 with existing workout rows, reward rows and achievement records preserved.

## Files modified

- `AGENTS.md` and this document record the project constraints and validation.
- `lib/features/pose_detection/application/push_up_counter.dart`, `models/pose_overlay_state.dart` and `presentation/pose_overlay_painter.dart` under the same feature implement frontal counting and full-body rendering.
- `lib/app/challenge/production_challenge_controller.dart`, `production_challenge_screen.dart` and `lib/core/integration/pose_event_adapter.dart` connect the detector and overlay to the existing challenge screen.
- `lib/main_ui.dart` and `lib/focus_experience/focus_exercises.dart` and `focus_screens.dart` use the existing Focus checklist and saved rotation. The Android `LevelUpAccessibilityService.kt` and `view_levelup_gate.xml` change Gate wording.
- `lib/features/challenge/application/challenge_service.dart`, `push_up_verification.dart`, `lib/features/challenge/data/challenge_catalog.dart`, `lib/core/integration/core_integration_coordinator.dart`, `lib/models/access_grant_request.dart`, and `lib/services/access_service.dart` route and gate authorization.
- `lib/models/exercise_type.dart`, `workout_session.dart`, `lib/data/repositories/workout_history_repository.dart`, `lib/features/progress/application/xp_reward_policy.dart`, `lib/features/statistics/data/statistics_repository.dart`, and `lib/app/adapters/core_insights_adapter.dart` preserve exercise identity and enforce progress eligibility.
- `test/features/pose_detection/module_11d1_pose_test.dart`, `test/features/progress/progress_engine_test.dart` and `test/ui/focus_exercises_test.dart` cover rendering, counting, persistence, access and configuration.

## Automated validation

| Check | Result |
| --- | --- |
| Baseline Flutter tests | 541 passed |
| `flutter pub get` | Passed |
| `flutter analyze --no-pub` | 0 issues |
| `flutter test --no-pub` | 548 passed |
| Focused tests with `LEVELUP_TEST_PUSH_UP_UNLOCK=true` | 14 passed |
| Debug APK for `lib/main_ui.dart` | Passed |
| Debug APK for `lib/main_dev.dart` | Passed |

The pose tests use synthetic landmark sequences. The access test uses a mocked platform channel and SQLite, including a close and reopen. It checks that the fifth experimental rep triggers one five-minute grant in the flagged build and that unvalidated sessions earn zero XP and contribute zero production unlocks.

## Physical Pixel 7 Pro checklist

ADB reported an empty device list. All physical checks below are pending.

- [ ] Use an ordinary build to confirm five squats unlock the selected app and the Gate returns after 300 seconds.
- [ ] Use the explicit debug flag to select Push-ups in Focus. Restart and verify the selection, then verify both-exercise rotation and the displayed challenge.
- [ ] Test full sets at normal speed, with multiple users, camera positions, lighting conditions and clothing. Record completed, missed and duplicate repetitions.
- [ ] Test standing curls, seated movement, head or shoulder dips, shallow repetitions, moving hands, temporary occlusion and tracking jumps. Record any falsely counted repetitions and grants.
- [ ] Inspect skeleton alignment during both exercises, including mirrored preview, partial framing, fast movement and camera restart.
- [ ] Confirm no unlock at four push-ups, a single 300-second grant at five in the flagged build, and zero grants from Free Workout.
- [ ] Confirm that restart preserves exercise identity, historical XP and achievements, and that experimental push-ups add no production progress.

## Remaining risks and Module 12A handoff

Camera position and lower-body visibility affect depth and motion estimates. Device observation is required before enabling trusted push-up rewards or production unlock. Module 12A can start from the existing camera lifecycle, source checks, v5 schema, XP ledger and native access journal. Its stability audit should cover permission and lifecycle interruption, journal and reward retries, migrations, and cross-session event delivery. Physical validation belongs to the Pixel 7 Pro workstream.
