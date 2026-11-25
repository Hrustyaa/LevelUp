# LevelUp — Module 11C: Real-Time Computer Vision Pose Overlay

**Document:** Module 11C Architecture & Implementation Report  
**Date:** November 25, 2026  
**Branch:** `integration/ui-core`  
**Status:** Implemented & Verified

---

## 1. Architecture Overview

Module 11C layers a non-interactive, read-only leg-skeleton overlay directly over the live `CameraPreview` in `ProductionChallengeScreen` using the existing ML Kit `PoseDetector` output from `ProductionChallengeController`:

- **Models (`lib/features/pose_detection/models/pose_overlay_state.dart`):**
  - `PoseJointPoint`, `LegLandmarks`, `PoseOverlayState`
- **Coordinate Transformation (`lib/features/pose_detection/application/pose_coordinate_mapper.dart`):**
  - `PoseCoordinateMapper` (`effectiveImageSize`, `mapPoint`, `mapLeg`, `MappedLegSegment`)
- **Presentation (`lib/features/pose_detection/presentation/`):**
  - `PoseOverlayPainter` (`CustomPainter`)
  - `PoseOverlayWidget` (`IgnorePointer` + `RepaintBoundary` + `ValueListenableBuilder<PoseOverlayState>`)
- **Controller & Screen Integration:**
  - `ProductionChallengeController.poseOverlayListenable` (`ValueNotifier<PoseOverlayState>`)
  - `ProductionChallengeScreen` wraps `CameraPreview(camera)` and `Positioned.fill(child: PoseOverlayWidget(...))` in a `Stack` inside `FocusChallengeScreen`.

---

## 2. Existing ML Kit Integration Reused & Landmark Data Flow

- Reuses the single `PoseDetector` (`PoseDetectionMode.stream`, `PoseDetectionModel.base`) and single `CameraController` NV21 `startImageStream` in `ProductionChallengeController`.
- Inside `processInputImage(InputImage)`:
  1. ML Kit detects `poses.first`.
  2. `estimateKneeAngle(poses.first)` feeds `_poseAdapter.processAngle(angle)` -> `SquatCounter` (unchanged).
  3. `extractOverlayState(...)` extracts `LEFT_HIP -> LEFT_KNEE -> LEFT_ANKLE` and `RIGHT_HIP -> RIGHT_KNEE -> RIGHT_ANKLE` (filtered by `SquatGeometry.defaultLikelihoodThreshold = 0.55` and non-zero finite coordinates) into `PoseOverlayState` and updates `_poseOverlayNotifier`.
- Both **Unlock Challenge** (`isUnlockChallenge: true`) and **Free Workout** (`isUnlockChallenge: false`) use `ProductionChallengeScreen`, so both share the exact same overlay pipeline.

---

## 3. White and Lime-Green Color Semantics

- **White (`FocusStyle.text`, `#F7F8F8`):** Reliably detected leg segments (`likelihood >= 0.55`).
- **Lime Green (`FocusStyle.accent`, `#C7FA5B`):** Authoritative `SquatCounterResult` confirms `isValidTracking && (phase == SquatPhase.down || isRepetitionCompleted)`.
- Overlay rendering never counts repetitions and never calls `grantAccess`.

---

## 4. Coordinate Mapping, Rotation & Front-Camera Mirroring

- `PoseCoordinateMapper.effectiveImageSize` swaps raw image width/height for `rotation90deg` and `rotation270deg` to match ML Kit's upright output coordinate space.
- Scales from upright image coordinates to `previewSize` using `BoxFit.cover` (centered crop offset), matching `CameraPreview` bounds.
- For `CameraLensDirection.front`, applies horizontal mirroring (`previewWidth - mappedX`) so the overlay aligns with the user's mirrored front-camera preview.
- Any point outside `[0, previewSize.width] x [0, previewSize.height]` or with missing/low-confidence joints is hidden (`null`).

---

## 5. Performance, Lifecycle & Resource Cleanup

- `PoseOverlayWidget` uses `ValueListenableBuilder` + `RepaintBoundary` so per-frame pose updates repaint only the `CustomPaint` layer without rebuilding `ProductionChallengeScreen` or `FocusChallengeScreen`.
- `IgnorePointer` ensures touch events (Cancel / Retry) pass straight through.
- `_sessionEpoch` guards against stale async ML Kit responses overwriting a cancelled or restarted session.
- Overlay clears immediately on `poses.isEmpty`, `angle == null`, `handleLifecycleChange(paused/inactive)`, `_releaseCamera()`, `_handleCompletion()`, `cancel()`, and `dispose()` (`_poseOverlayNotifier.dispose()`).

---

## 6. Automated Tests & Validation

Added `test/features/pose_detection/pose_overlay_test.dart` covering coordinate mapping (rotation, mirroring, cropping, aspect ratio), confidence filtering, partial leg visibility, empty-pose clearing, white vs lime-green semantics, stale session epoch rejection, `IgnorePointer` touch passthrough, disposal safety, and Free Workout / 5-squat invariants.

- `flutter pub get`: Succeeded.
- `flutter analyze --no-pub`: `No issues found!`
- `flutter test --no-pub`: **485 passed, 0 failed**.
- `flutter build apk --debug -t lib/main_ui.dart --no-pub`: Built successfully.
- `flutter build apk --debug -t lib/main_dev.dart --no-pub`: Built successfully.

---

## 7. Physical Pixel 7 Pro Verification Checklist

1. Open LevelUp on Pixel 7 Pro and start a real squat challenge.
2. Verify white `hip -> knee -> ankle` lines appear on visible legs and follow left/right leg movement with accurate front-camera mirroring.
3. Verify joints align near screen edges and turn lime green only during valid squat phase (`down` / repetition).
4. Complete 5 verified squats → confirm 300-second native unlock.
5. Open Free Workout → verify the same overlay works without granting native access.
6. Step out of frame → verify lines disappear; step back in → verify tracking resumes.
7. Background/resume and close challenge → verify camera & overlay clean up with no freezes, and XP/Statistics/Achievements update normally.

---

## 8. Known Limitations & Module 11D Handoff

- **Known limitations:** Side-profile squats may show one leg reliably when the far leg is occluded; `PoseOverlayState` intentionally hides occluded/low-confidence segments rather than guessing them.
- **Module 11D handoff:** `PoseJointPoint`, `PoseCoordinateMapper`, and `PoseOverlayWidget` are structured cleanly so Module 11D can add upper-body arm landmarks (`shoulder -> elbow -> wrist`) for `PushUpCounter` without altering camera or coordinate infrastructure.
