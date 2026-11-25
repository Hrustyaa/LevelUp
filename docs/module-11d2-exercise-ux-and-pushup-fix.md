# Module 11D.2 — Push-up counting and workout selection

## Reported issues and causes

The user reported a full frontal push-up with chest contact that stayed in the descent phase. The previous detector required **all four** of these observations together over two frames.

- Shoulder drop of at least 30% of projected shoulder width.
- Hip drop of at least 10% of projected shoulder width.
- Shoulder-to-wrist clearance reduction of at least 25% of projected shoulder width.
- Both elbows at or below 120° in the same measurement, either both projected angles or both depth-assisted angles.

The fixed travel requirements can reject a full motion from a low frontal camera. One arm can also have a cleaner projected angle while the opposite arm has a cleaner depth-assisted angle. Synthetic regressions reproduce those failure paths. The user’s original session has no landmark trace, so its exact rejected condition is unknown.

The old workout screen created a session and began camera setup in `initState`, then showed the exercise chips and cancelled and replaced the running controller when the choice changed. In the coordinator, passing null to `copyWith` also retained the previous session’s identity, access grant and expiry. The latter could carry a previous authorization into the next challenge’s presentation.

## Push-up verification

The live counter anchors a stable, extended plank with hands in view. It checks projected shoulder travel and the change in shoulder-to-wrist clearance against approximately 32% of the observed top clearance, bounded to 15–27% of shoulder width. Hip movement can be corroborated by hand-relative ML Kit depth when projected hip movement is small and its direction is consistent. Each arm independently supplies evidence through a meaningful change in its projected or depth-assisted elbow angle, or a substantial hand-relative shortening. Plank shape, two-arm evidence, hand stability and a return near the original top are still required.

An observed descent frame near the lower position can support the bottom confirmation. A second observation must reach the full movement criteria within 220 ms. Tracking gaps of up to 300 ms can preserve the phase, while a jump, sustained loss, camera interruption or timeout discards the in-flight repetition. The counter confirms the return with two valid frames and advances one repetition. A single anomalous bottom frame, isolated arm motion or a shallow motion without sufficient observed travel cannot complete a cycle.

The user sees guidance about tracking, framing, steady hands and briefly holding a detected lower position. The counter has no physical floor-distance measurement. Google describes ML Kit’s depth coordinate as an experimental image-relative estimate. [Google ML Kit pose detection](https://developers.google.com/ml-kit/vision/pose-detection#z_coordinate)

With `LEVELUP_DEBUG_PUSH_UP_DIAGNOSTICS=true` in a debug build, log output includes missing landmark or plank checks, the failed bottom conditions from the best observed descent on an incomplete return, and phase confirmations or interruptions. Repeated setup messages are rate-limited. The diagnostics store neither images nor videos.

## Workout and Focus selection

**Challenges → Workout → Choose exercise → Start Workout** opens a separate route with the existing exercise chips, theme and primary button. Selecting or changing a chip creates no workout controller, camera or detector. Start captures the selection once and then creates the workout route. The SQLite preference remembers the last started Free Workout. Focus uses its own saved exercise selection and is unaffected by Free Workout.

The workout controller creates one counter and binds its stream to the selected session ID. Camera opening, pause, resume and teardown are serialized. Camera callbacks check their camera instance and epoch, and pose results and controller cleanup check the session identity. The coordinator rejects unrelated live counter events and holds new sessions until the preceding completion workflow has finished. Fresh session state clears earlier progress and authorization fields.

In **Focus → Focus Rules → Exercises**, both supported exercises show five reps. Squats are available in ordinary builds. Push-ups are disabled with an availability message until either the debug opt-in or reviewed production validation enables them. Select one checkbox to use that exercise every time. Selecting both retains the existing rotation. The Gate carries the assigned session and exercise into the camera route.

**Movement** is now **Workout**. **Mindful break** is now **Quick Reset**, including the title of its existing one-minute screen-free timer. Russian uses «Тренировка» and «Короткая пауза». Kazakh uses «Жаттығу» and «Қысқа үзіліс». Existing card styling, icons, timer behavior, camera layout and white/lime overlay styling remain in place.

## Rewards and native access

Five verified squats still award 50 XP once per eligible session. Free Workout grants no native access. In a flagged debug build a complete five-rep push-up Gate challenge can use the existing journaled 300-second native grant. The experiment remains `experimental_unverified` and contributes no production XP, streaks or achievements. Push-up progress requires the session’s push-up pose adapter. A direct result or a squat stream cannot complete the push-up challenge.

After documented physical validation and review, explicitly set `PushUpVerification.physicallyValidated` in `lib/features/challenge/application/push_up_verification.dart`. That change activates production selection, authorization and the dedicated `camera_pushup_verified` source for future sessions. Verified sessions use the existing 50 XP ledger and general workout and streak totals. The 25 Squats achievement continues to count squats only. Existing experimental records retain their original classification. SQLite stays at v5.

## Automated validation

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed |
| `flutter analyze --no-pub` | 0 issues |
| `flutter test --no-pub` | 558 passed |
| Focused tests with unlock and diagnostics flags | 29 passed |
| `flutter build apk --debug -t lib/main_ui.dart --no-pub` | Passed |
| `flutter build apk --debug -t lib/main_dev.dart --no-pub` | Passed |

Regression coverage includes low-angle projected motion, mixed arm evidence, brief dropout, diagnostics, partial and standing movements, duplicate rep rejection, workout selection before camera access, exercise isolation, camera pause/resume during initialization, stale callbacks and old grants, three-language card labels, debug-only Focus selection, and the isolated validated XP ledger. Full-suite coverage includes SQLite, exactly-once XP, native 300-second authorization, squat statistics and achievements. Synthetic landmarks and a mocked native channel do not establish physical accuracy.

## Pixel 7 Pro verification

ADB listed no attached device during this work. For a connected Pixel 7 Pro, use its ID from `adb devices -l` in the diagnostic build command.

```sh
flutter run --debug -t lib/main_ui.dart -d <device-id> \
  --dart-define=LEVELUP_TEST_PUSH_UP_UNLOCK=true \
  --dart-define=LEVELUP_DEBUG_PUSH_UP_DIAGNOSTICS=true
adb -s <device-id> logcat -s flutter
```

- [ ] In **Challenges → Workout**, switch choices and go back before starting. Check that camera access begins only after **Start Workout**. Start each choice and check the displayed exercise and overlay. Cancel during setup and during tracking, then start the other choice.
- [ ] Place the phone just above the floor facing the user, tilted slightly downward. Keep both hands and feet in frame. Repeat the originally reported push-up motion at normal speed and note physical reps, misses, duplicates and diagnostic messages. Try more than one phone height, distance and user.
- [ ] Try shallow reps, standing curls, seated arm motions, head dips, hand movement and temporary occlusion. Record any false count or grant. Check the unchanged full-body overlay in both exercises.
- [ ] Select Push-ups in **Focus Rules → Exercises**, restart, and trigger the Gate for the selected restricted app. Check no grant at four reps and one grant at five, and observe the Gate returning after 300 seconds. Confirm Free Workout still never grants access.
- [ ] In an ordinary build confirm that push-up unlocking is unavailable, five squats still grant access, and experimental push-ups add no production XP, statistics or achievements.

## Files changed in Module 11D.2

- Challenge UI and lifecycle in `lib/app/challenge/production_challenge_controller.dart`, `production_challenge_screen.dart` and `workout_exercise_screen.dart`.
- Session binding and grant isolation in `lib/core/integration/core_integration_coordinator.dart` and `pose_event_adapter.dart`.
- Motion verification and reward-policy coverage in `lib/features/pose_detection/application/push_up_counter.dart` and `lib/features/progress/application/xp_reward_policy.dart`.
- Focus and challenge copy in `lib/main_ui.dart`, `lib/focus_experience/focus_screens.dart` and `lib/screens/levelup_home_screen.dart`.
- Regression tests in `test/app/challenge/production_challenge_test.dart`, `test/app/integration_phase_i2a_test.dart`, `test/features/pose_detection/module_11d1_pose_test.dart`, `test/features/progress/progress_engine_test.dart`, `test/ui/focus_exercises_test.dart`, `test/ui/focus_management_test.dart`, `test/ui/focus_screens_test.dart` and the shared fixture `test/support/push_up_pose.dart`.

## Remaining Module 12A risks

A single frontal view still depends on visibility, projection and ML Kit tracking quality. Module 12A can audit Android permission revocation, rapid pause/resume across OS versions, interrupted native-grant reconciliation and camera-plugin errors. Production push-up activation remains contingent on physical verification.
