# Module 11D — Multi-Exercise Support & Computer Vision Tracking Stabilization

**Branch:** `integration/ui-core`
**Date:** 2026-11-25

---

## 1. Overview

Module 11D adds multi-exercise support (squats + push-ups) for Free Workout mode and resolves the real-device computer vision tracking instabilities reported after Module 11C on the Pixel 7 Pro.

**Two parts:**

| Part | Scope |
|------|-------|
| A — CV Stabilization | Replace fixed-EMA smoother with One Euro Filter; add temporal outlier rejection |
| B — Multi-Exercise | PushUpCounter, DB migration v4→v5, exercise selector UI, settings persistence |

---

## 2. Part A — CV Tracking Stabilization

### 2.1 Root Causes (from Module 11C)

1. **Fixed-alpha EMA** (alpha = 0.35) applies identical smoothing at all speeds. At rest it over-smooths causing visible lag; during fast squat movement it under-smooths causing jitter.
2. **No outlier rejection** — a single bad ML Kit frame with landmark jumping 300+ pixels passed through directly, causing teleportation artifacts.
3. No tracking-gap awareness — EMA continued from stale state after the user left the frame.

### 2.2 One Euro Filter (`PoseLandmarkSmoother`)

**File:** `lib/features/pose_detection/application/pose_landmark_smoother.dart`

The One Euro Filter is an adaptive low-pass filter designed for real-time interactive applications. It adapts its cutoff frequency based on the speed of the signal — high cutoff (less smoothing) when moving fast, low cutoff (more smoothing) when stationary.

**Parameters:**

| Parameter | Value | Effect |
|-----------|-------|--------|
| `minCutoff` | 1.5 Hz | Base smoothing at rest — reduces jitter |
| `beta` | 0.007 | Speed coefficient — raises cutoff during fast motion |
| `derivateCutoff` | 1.0 Hz | Smoothing on the derivative (velocity) signal |

At 30 fps:
- **Stationary:** α ≈ 0.24 → smooth, lag-free resting position
- **Fast squat:** α → near 1.0 → near-raw tracking, no lag

**API:**
```dart
Offset smooth(PoseLandmarkType type, Offset raw, {required DateTime timestamp})
void reset()
bool waitForEstablishment(PoseLandmarkType type)
```

**Tracking gap:** If `dt > 500ms`, the per-landmark state is reset and the raw value is returned immediately (no stale EMA carry-over).

**dt ≤ 0:** Uses α = 0.5 fallback and does not throw.

### 2.3 Temporal Outlier Guard (`PoseTemporalGuard`)

**File:** `lib/features/pose_detection/application/pose_temporal_guard.dart`

Rejects single-frame landmark jumps that exceed a plausibility threshold relative to the image dimensions. Protects the visual overlay from teleportation artifacts caused by occasional bad ML Kit detections.

**Threshold:** 25% of `max(imageWidth, imageHeight)` per frame.

**API:**
```dart
PoseTemporalGuard({double maxNormalizedJump = 0.25})
bool isPlausible(PoseLandmarkType type, Offset raw, Size imageSize)
void update(PoseLandmarkType type, Offset position)
void reset()
```

> [!IMPORTANT]
> The temporal guard applies to the **visual overlay only**. Raw landmark coordinates are forwarded unchanged to `SquatCounter` / `PushUpCounter` for rep counting. Smoothing and outlier rejection are cosmetic.

---

## 3. Part B — Multi-Exercise Support

### 3.1 ExerciseType Enum

**File:** `lib/models/exercise_type.dart`

```dart
enum ExerciseType { squats, pushUp }
```

- `ExerciseType.squats` — existing squat verification path
- `ExerciseType.pushUp` — new push-up path (Free Workout only)

### 3.2 PushUpCounter

**File:** `lib/features/pose_detection/application/push_up_counter.dart`

State machine mirroring `SquatCounter` mechanics but for push-up biomechanics:

| Threshold | Value | Description |
|-----------|-------|-------------|
| `downAngle` | 100° | Elbow angle indicating "down" position |
| `upAngle` | 150° | Elbow angle indicating "up" (extended) position |
| `consecutiveFrames` | 2 | Frames required to confirm phase transition |
| `defaultGoal` | 5 | Default repetition target |

**Rep cycle:** `up → down (elbow ≤ 100° for 2+ frames) → up (elbow ≥ 150° for 2+ frames) = 1 rep`

**Reuses:** `SquatCounterResult` and `SquatPhase` (structurally identical state machine, shared types).

### 3.3 PushUpPoseAdapter

**File:** `lib/core/integration/pose_event_adapter.dart`

Wraps `PushUpCounter` with the same `IPoseEventSource` interface as `PoseEngineAdapter`. Streams `SquatCounterResult` to `CoreIntegrationCoordinator`. Separate class — does not modify the existing `PoseEngineAdapter` or `SquatCounter`.

### 3.4 PushUpGeometry

**File:** `lib/features/pose_detection/application/push_up_counter.dart`

```dart
static double calculateElbowAngle(Offset shoulder, Offset elbow, Offset wrist)
static double? estimateElbowAngle(Pose pose)
```

Estimates elbow angle from ML Kit landmarks. Tries left arm first, falls back to right. Returns `null` if neither arm has visible landmarks above the likelihood threshold.

### 3.5 Arm Overlay — PoseOverlayState & ArmLandmarks

**File:** `lib/features/pose_detection/models/pose_overlay_state.dart`

New fields in `PoseOverlayState`:
- `leftArm`, `rightArm` — `ArmLandmarks?` (shoulder → elbow → wrist)
- `exerciseMode` — `ExerciseMode.squat` or `ExerciseMode.pushUp`
- `hasAnyArm` — convenience getter

`ArmLandmarks` mirrors `LegLandmarks` with shoulder/elbow/wrist joints.

### 3.6 Pose Overlay Painter

**File:** `lib/features/pose_detection/presentation/pose_overlay_painter.dart`

Updated to dispatch on `exerciseMode`:
- `ExerciseMode.squat` → draws `hip → knee → ankle` (existing)
- `ExerciseMode.pushUp` → draws `shoulder → elbow → wrist` via `PoseCoordinateMapper.mapArm`

### 3.7 Database Migration v4 → v5

**File:** `lib/data/database/database_constants.dart`, `levelup_database.dart`

The `workout_sessions` table's `exercise_type` column `CHECK` constraint was extended from `= 'squats'` to `IN ('squats', 'pushUp')`. Because SQLite does not support `ALTER TABLE … MODIFY COLUMN`, the migration uses a safe table-rename pattern:

```
1. CREATE TABLE workout_sessions_v5 (… CHECK (exercise_type IN ('squats', 'pushUp')))
2. INSERT INTO workout_sessions_v5 SELECT * FROM workout_sessions
3. DROP TABLE workout_sessions
4. ALTER TABLE workout_sessions_v5 RENAME TO workout_sessions
5. Recreate index
```

All existing `'squats'` rows are valid under the new constraint. No data loss.

### 3.8 Exercise Preference in AppSettings

**File:** `lib/features/settings/models/app_settings.dart`

New field: `preferredExerciseType` (`ExerciseType`, default `ExerciseType.squats`).

- JSON key: `'preferred_exercise_type'`
- Serialized as `type.name` (e.g. `'squats'`, `'pushUp'`)
- Deserialized with `ExerciseType.values.byName()` with fallback to `squats` on error/missing
- Stored in existing settings JSON blob — no schema change required

### 3.9 SettingsService

**File:** `lib/features/settings/application/settings_service.dart`

New method on `ISettingsService` interface and `SettingsService` implementation:

```dart
Future<SettingsState> updatePreferredExercise(ExerciseType type)
```

Delegates to `updateSettings(settings.copyWith(preferredExerciseType: type))`.

### 3.10 ProductionChallengeController — Exercise Routing

**File:** `lib/app/challenge/production_challenge_controller.dart`

Changes:
- `exerciseType` constructor parameter (default `ExerciseType.squats`)
- `PushUpPoseAdapter _pushUpPoseAdapter` — created alongside `_poseAdapter`
- `start()` attaches the correct adapter based on `exerciseType`
- `processInputImage()` branches on `exerciseType`:
  - **Push-up path:** calls `PushUpGeometry.estimateElbowAngle`, routes to `_pushUpPoseAdapter`, builds arm overlay via `_buildSmoothedArmOverlayState`
  - **Squat path:** unchanged
- `_clearPoseOverlay()` resets both `_landmarkSmoother` and `_temporalGuard`
- `dispose()` disposes both `_poseAdapter` and `_pushUpPoseAdapter`

> [!IMPORTANT]
> Push-ups are available in **Free Workout only**. `isUnlockChallenge = true` always uses `ExerciseType.squats` regardless of `exerciseType` parameter. The 300-second native unlock remains squats-only.

### 3.11 Exercise Selector UI

**File:** `lib/app/challenge/production_challenge_screen.dart`

For Free Workout sessions (not controlled by a test override), a compact exercise selector is shown via `headerExtra` in `FocusChallengeScreen`:

- Two `ChoiceChip` widgets: Squats / Push-ups
- Selector is **disabled** once `trackingReady` is true (session locked)
- On selection change: persists preference via `settingsService.updatePreferredExercise`, disposes old controller, creates new one with new `exerciseType`
- Completion text uses exercise-aware wording
- Unlock challenge: no selector shown

**File:** `lib/focus_experience/focus_screens.dart`

Added optional `headerExtra` parameter to `FocusChallengeScreen`. Inserted below the progress bar using null-aware collection element syntax (`?headerExtra`).

### 3.12 Focus Exercises Helpers

**File:** `lib/focus_experience/focus_exercises.dart`

```dart
bool isExerciseAvailableForFreeWorkout(FocusExerciseId id)
FocusExercise? exerciseById(FocusExerciseId id)
```

`pushUp` has `ready = false` in the Focus unlock rotation (unchanged). `isExerciseAvailableForFreeWorkout` returns `true` for both `squat` and `pushUp` — keeping unlock rotation pure squats while enabling push-up Free Workouts.

---

## 4. Unlocking Policy

| Context | Exercise |
|---------|----------|
| Native Unlock Challenge | Squats only (enforced in controller and screen) |
| Free Workout | Squats or Push-ups (user preference, persisted) |
| Focus rotation | Squats only (`ready = true` for squat only) |

---

## 5. Test Coverage

**New test file:** `test/features/pose_detection/module_11d_test.dart`

| Group | Tests |
|-------|-------|
| PoseTemporalGuard | First obs, small jump, large jump rejection, reset, independent landmarks |
| PoseLandmarkSmoother (One Euro) | Stationary convergence, fast tracking, gap reset, per-landmark independence, reset, dt≤0, irregular intervals |
| PushUpCounter | Full rep cycle, partial rep, null angle, debounce, reset, goal default |
| PushUpGeometry | Straight arm ~180°, 90° bend, null when no landmarks |
| ExerciseMode in PoseOverlayState | Default mode, pushUp mode, hasAnyArm |
| AppSettings preference | fromJson with pushUp, without key, invalid key, copyWith, toJson round-trip, defaults, equality |
| ExerciseType enum | squats.name, pushUp.name |
| Smoother/counter separation | Raw angle reaches counter unmodified |

**Updated:** `test/data/levelup_database_test.dart` — test 22 assertion updated from schema version 4 to 5 (v3→v5 migration now runs through v4 then v5).

---

## 6. Statistics Compatibility

The existing `loadWorkoutStatistics` SQL already uses:

```sql
SUM(CASE WHEN exercise_type = 'squats' THEN completed_repetitions ELSE 0 END) AS total_reps
```

This correctly excludes push-up reps from squat counts. Push-up workouts are recorded with `exercise_type = 'pushUp'` and appear in `WorkoutStatistics` aggregates under separate CASE branches. No statistics service changes required.

---

## 7. Device Validation Checklist

> [!NOTE]
> The following checklist is for physical device testing on Pixel 7 Pro (front camera). No physical validation was performed in this session — all claims are based on software logic.

- [ ] Squat overlay: no jitter at rest, tracks smoothly during fast squats
- [ ] Squat overlay: no teleportation on rapid landmark jumps
- [ ] Push-up overlay: shoulder/elbow/wrist lines visible in frontal position
- [ ] Exercise selector: appears in Free Workout, hidden in Unlock Challenge
- [ ] Exercise selector: locks once tracking starts
- [ ] Preference persists across app restarts
- [ ] Completion screen shows exercise-aware text
- [ ] v4→v5 migration: existing squat sessions retained after upgrade
- [ ] Unlock challenge: always squats, 300s timer unaffected

---

## 8. Constraints Preserved

- `SquatCounter`, `SquatGeometry`, `PoseEngineAdapter` — not modified
- `CoreIntegrationCoordinator` internals — not modified
- Android `AccessibilityService`, 300-second unlock duration — not modified
- XP amounts, achievement thresholds — not modified
- No data fabrication, no simulated reps
- Branch: `integration/ui-core` — no new branches, commits, or pushes
