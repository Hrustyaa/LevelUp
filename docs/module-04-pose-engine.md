# Module 04 — Pose Engine Architecture & Testing

**Component:** Squat Biomechanical Angle Calculation, Debounced State Machine & Testing  
**Layer:** Feature Domain & Application Layer (`lib/features/pose_detection/application/`)  
**Status:** Completed & Validated  
**Working Branch:** `feature/core`

---

## 1. Existing Prototype Audit

The working prototype in `lib/main.dart` integrates camera streaming and Google ML Kit pose estimation inside `_ChallengeScreenState`.

### 1.1 Camera Lifecycle Management
- **Initialization**: Triggered in `initState()` via `openCamera()`. Queries `availableCameras()`, prefers front-facing lens (`CameraLensDirection.front`), and initializes `CameraController` with `ResolutionPreset.medium`, `enableAudio: false`, and `ImageFormatGroup.nv21`.
- **Image Streaming**: On initialization, calls `controller.startImageStream(onFrame)`.
- **Lifecycle Observers**: Listens to `WidgetsBindingObserver.didChangeAppLifecycleState`:
  - `inactive` / `paused`: Calls `releaseCamera()` to release the camera hardware and stop the image stream.
  - `resumed`: Calls `openCamera()` if the challenge has not finished.
- **Teardown**: Calls `releaseCamera()` and `poseDetector.close()`.

### 1.2 Pose Processing Pipeline
1. **Frame Ingestion**: `onFrame(CameraImage image)` receives NV21 image buffer from the camera stream.
2. **Backpressure Guard**: Guarded by `if (busy || finished) return;`. Drops frames if the detector is currently computing (`busy = true`).
3. **Buffer Conversion**: `fromCameraImage(CameraImage image)` translates `CameraImage` planes into Google ML Kit's `InputImage`, adjusting rotation based on `sensorOrientation` and device orientation.
4. **Pose Landmark Extraction**: Evaluates 33 body landmarks via `PoseDetector(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base)`.
5. **Knee Angle Calculation**:
   - Landmark coordinates: $A = \text{hip}(x, y)$, $B = \text{knee}(x, y)$, $C = \text{ankle}(x, y)$.
   - Likelihood check: Requires $A, B, C$ likelihood $\ge 0.55$.
   - Left-side priority with right-side fallback.
   - Vector 2D dot product:
     $$\cos(\theta) = \frac{\vec{BA} \cdot \vec{BC}}{|\vec{BA}| \cdot |\vec{BC}|}$$
     $$\theta = \arccos(\cos(\theta)) \times \frac{180}{\pi}$$
6. **Completion Side Effect**: When 5 repetitions are reached, marks `finished = true`, releases camera, and invokes `native.invokeMethod('grantAccess', {'minutes': 5})`.

---

## 2. Squat State Machine Algorithm

```text
                  ┌──────────────────────┐
                  │      Standing        │
                  │   Phase = UP (0)     │
                  └──────────┬───────────┘
                             │
            Angle < 125° for 2 consecutive frames
                             │
                             ▼
                  ┌──────────────────────┐
                  │    Bottom Squat      │
                  │   Phase = DOWN (1)   │
                  └──────────┬───────────┘
                             │
            Angle > 155° for 2 consecutive frames
                             │
                             ▼
                  ┌──────────────────────┐
                  │    Repetition ++     │
                  │    Phase = UP (0)    │
                  └──────────────────────┘
```

### 2.1 Thresholds (`SquatThresholds`)
- **Down Threshold**: $125.0^\circ$. Angles strictly below $125^\circ$ count towards bottom depth.
- **Up Threshold**: $155.0^\circ$. Angles strictly above $155^\circ$ count towards standing upright.
- **Debounce Threshold**: $2$ consecutive frames required before any phase transition occurs.
- **Default Goal**: $5$ verified repetitions.

### 2.2 Edge-Case Handling in State Machine
- **Landmark Dropout / Person Leaves Frame**: When angle is `null`, debounce counters (`consecutiveDown`, `consecutiveUp`) are reset to 0 to prevent cross-dropout false positives, while cumulative repetition count and current phase are preserved.
- **Threshold Jitter**: If an angle fluctuates across the boundary (e.g. $124^\circ \rightarrow 126^\circ$), the debounce counter resets to 0. A transition is never triggered on a single frame spike.
- **Repeated Frames**: Remaining at the bottom ($110^\circ$) or standing ($170^\circ$) generates 0 duplicate repetition counts.
- **Partial Repetitions**:
  - Shallow squats ($\ge 125^\circ$) never enter the down phase.
  - Incomplete standing ($\le 155^\circ$) never trigger a repetition increment.

---

## 3. Extracted Pure Dart Modules

To enable isolated unit testing without camera hardware, Android runtime, or ML Kit native binaries, two pure Dart components were created:

### 3.1 `SquatGeometry` (`lib/features/pose_detection/application/squat_geometry.dart`)
- `calculateKneeAngle(Offset hip, Offset knee, Offset ankle)`: Pure geometric interior angle calculator using 2D dot product math. Includes degenerate zero-distance checks ($< 1e-5$).
- `defaultLikelihoodThreshold`: $0.55$.

### 3.2 `SquatCounter` (`lib/features/pose_detection/application/squat_counter.dart`)
- **Inputs**: Stream of joint angles via `processAngle(double? kneeAngle)`.
- **Outputs**: `SquatCounterResult`:
  * `repetitionCount`: Current valid reps.
  * `phase`: `SquatPhase.up` or `SquatPhase.down`.
  * `isRepetitionCompleted`: `true` on the single transition frame when a rep finishes.
  * `isValidTracking`: Whether landmarks were present.
  * `consecutiveDownFrames` / `consecutiveUpFrames`: Real-time debounce progress.
  * `feedbackMessage`: Contextual posture hints.
- **Lifecycle**: `reset()` to restart session.

---

## 4. Known Biomechanical & Hardware Limitations

1. **2D Projection / Perspective Distortion**: Angles are computed in 2D camera coordinates $(x, y)$. If the user faces the camera frontally rather than profile/3-quarter angle, depth foreshortening distorts the calculated knee angle.
2. **Frame Rate Sensitivity**: The 2-consecutive-frame debounce at 30 fps requires $\sim 66$ ms hold at turnaround. Extremely rapid "bounce" squats could be missed if the turnaround occurs in a single frame.
3. **Lighting & Occlusion**: Baggy clothing, poor contrast, or low-light conditions decrease landmark likelihood below $0.55$, causing frames to be dropped.
4. **Single-Leg Evaluation**: Evaluates left side with right side fallback. Asymmetrical squats (e.g. leaning heavily to one leg) may read different angles depending on which leg is tracked.

---

## 5. Future Integration: Module 05 Workout Session Manager

In Module 05, the `WorkoutSessionManager` will orchestrate the full camera challenge lifecycle:

```text
┌────────────────────────────────────────────────────────┐
│ Camera Stream (CameraImage NV21)                       │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ PoseDetector (Google ML Kit)                           │
│ - Extracts landmarks (hip, knee, ankle)                │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ SquatGeometry.calculateKneeAngle()                     │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ SquatCounter.processAngle()                            │
│ - Evaluates 125° / 155° / 2-frame debounce             │
│ - Emits isRepetitionCompleted                          │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ Module 05: WorkoutSessionManager                       │
│ - Subscribes to verified repetition events             │
│ - Tracks session duration & accuracy telemetry         │
│ - On goal reached (5 reps): invokes Access Engine      │
└────────────────────────────────────────────────────────┘
```
