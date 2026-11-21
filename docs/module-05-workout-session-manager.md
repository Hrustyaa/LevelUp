# Module 05 — Workout Session Manager

**Component:** Workout Session Lifecycle, Repetition Tracking Coordination & Completion Invariants  
**Layer:** Feature Domain & Application Layer (`lib/models/`, `lib/features/challenge/application/`)  
**Status:** Completed & Validated  
**Working Branch:** `feature/core`

---

## 1. Purpose and Architecture

The **Workout Session Manager** coordinates the lifecycle, repetition accumulation, and completion verification of physical workouts in LevelUp. 

It acts as the single coordinator connecting:
1. **Challenge Engine (Module 03)**: Consumes validated `ChallengeRequest` parameters (e.g. 5 squats target, unlock context, package ID).
2. **Pose Engine (Module 04)**: Receives verified repetition events from `SquatCounter`.
3. **Access Engine (Module 06)**: Hands off structured, immutable `WorkoutResult` records upon verified completion.
4. **Progress Engine (Module 07)**: Provides verifiable workout telemetry for local persistence and streak tracking.

```text
┌────────────────────────────────────────────────────────┐
│ Camera Stream (CameraImage NV21)                       │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ PoseDetector (Google ML Kit)                           │
│ - 33 body landmarks (hip, knee, ankle)                 │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ SquatGeometry & SquatCounter (Module 04)               │
│ - Angle calculation & 2-frame debounce                 │
│ - Emits verified repetition counts                     │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ WorkoutSessionManager (Module 05)                      │
│ - Enforces session lifecycle (CREATED -> ACTIVE -> ...) │
│ - Deduplicates repetition events                       │
│ - Validates target completion (5 squats)               │
│ - Returns structured WorkoutResult                     │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│ [Upcoming Module 06] Access Engine                     │
│ - Evaluates eligibleForAccess == true                  │
│ - Calls NativeBridge.grantAccess(minutes: 5)           │
└────────────────────────────────────────────────────────┘
```

---

## 2. Session Domain Models

### 2.1 `WorkoutSessionStatus` (`lib/models/workout_session_status.dart`)
Discrete states:
- `created`: Session initialized from `ChallengeRequest` and catalog definition.
- `preparing`: Camera initialization, user positioning, and countdown.
- `active`: Live repetition tracking actively accepted.
- `completed`: Successfully achieved target verified repetitions ($5$ squats). Terminal successful state.
- `cancelled`: User voluntarily stopped or exited the session (safe exit). Terminal state.
- `failed`: Camera stream disconnected, unrecoverable tracking error, or hardware failure. Terminal state.

### 2.2 `WorkoutSession` (`lib/models/workout_session.dart`)
Immutable session snapshot:
- `sessionId`: Unique identifier.
- `requestId`: Originating request ID.
- `challengeId`: Catalog definition ID.
- `challengeContext`: `unlockChallenge` or `freeWorkout`.
- `targetPackage`: Targeted app package (`null` for free workouts).
- `exerciseType`: Movement performed (`ExerciseType.squats`).
- `targetRepetitions`: Repetitions required ($5$).
- `verifiedRepetitions`: Verified count completed.
- `startedAt` & `completedAt`: Timestamps.
- `duration`: Elapsed duration.
- `status`: Current `WorkoutSessionStatus`.
- `failureReason`: Error explanation if failed.
- `toWorkoutResult()`: Converts completed session into `WorkoutResult`.

### 2.3 `WorkoutResult` (`lib/models/workout_result.dart`)
Structured outcome record for downstream consumption:
- `completedRepetitions`: Verified repetitions.
- `duration`: Elapsed exercise time.
- `eligibleForAccess`: Boolean flag authorizing app access.
- `accessDurationSeconds`: $300$ for unlock challenges; $0$ for free workouts.
- `earnedXp`: Base XP ($50$).
- `source`: `'camera'`.

---

## 3. Public Manager API (`IWorkoutSessionManager`)

Located in `lib/features/challenge/application/workout_session_manager.dart`:

| Method | Return Type | Description |
|---|---|---|
| `createSession(ChallengeRequest)` | `WorkoutSession` | Instantiates a new session in `created` status. Throws `SessionAlreadyActiveException` if another is running. |
| `prepareSession(sessionId)` | `WorkoutSession` | Transitions to `preparing` (countdown/positioning). Idempotent. |
| `startSession(sessionId)` | `WorkoutSession` | Transitions to `active` and records `startedAt`. Idempotent. |
| `updateVerifiedProgress(sessionId, cumulativeReps, eventId)` | `WorkoutSession` | Updates cumulative reps. Automatically completes when target is reached. Deduplicates events. |
| `completeSession(sessionId)` | `WorkoutResult` | Explicitly completes an active session. Throws `IncompleteWorkoutException` if reps $<$ target. |
| `cancelSession(sessionId, reason)` | `WorkoutSession` | Voluntarily cancels an active session (safe exit). Idempotent. |
| `failSession(sessionId, reason)` | `WorkoutSession` | Terminates session due to unrecoverable error. Idempotent. |
| `getCurrentSession()` | `WorkoutSession?` | Returns active or latest managed session. |
| `releaseCurrentSession()` | `void` | Clears terminal session reference allowing a new session to be created. |
| `sessionStream` | `Stream<WorkoutSession>` | Reactive broadcast stream of session updates. |

---

## 4. State Transition Rules

```text
         ┌───────────────┐
         │    CREATED    │
         └──┬─────────┬──┘
            │         │
            ▼         │ (direct start)
      ┌───────────┐   │
      │ PREPARING │   │
      └─────┬─────┘   │
            │         │
            ▼         ▼
         ┌───────────────┐
         │    ACTIVE     │
         └──┬────┬────┬──┘
            │    │    │
            │    │    └──────────────────────┐
            ▼    ▼                           ▼
     ┌───────────┐ ┌───────────┐       ┌───────────┐
     │ COMPLETED │ │ CANCELLED │       │  FAILED   │
     └───────────┘ └───────────┘       └───────────┘
```

- **Terminal States**: `completed`, `cancelled`, and `failed` are terminal. No further state transitions or progress updates are accepted.
- **Single Active Workout**: Attempting to create a session while another is active or preparing throws `SessionAlreadyActiveException`.
- **Release Guard**: `releaseCurrentSession()` throws if called while a session is active.

---

## 5. Repetition Pipeline & Idempotency Rules

### 5.1 Pipeline Separation
```text
Camera Frames -> ML Kit -> SquatCounter -> WorkoutSessionManager
```
- `WorkoutSessionManager` does **NOT** process raw camera frames or ML Kit landmarks.
- It receives validated cumulative counts and/or event IDs from `SquatCounter`.

### 5.2 Anti-Duplication & Monotonicity
1. **Monotonic Progress**: Progress is non-decreasing. If a lower or identical count arrives, it is safely ignored.
2. **Event Deduplication**: If an `eventId` was already processed, it is dropped immediately.
3. **Single Completion**: Reaching target repetitions transitions to `completed` exactly once. Calling `completeSession` repeatedly returns the identical `WorkoutResult`.
4. **Process Restart Limitation**: In-memory deduplication operates during app execution. Durable cross-process idempotency will be reinforced with database constraints in Module 07 and native gate checks in Module 06.

---

## 6. Context Safety Guarantee

| Parameter | `unlockChallenge` | `freeWorkout` |
|---|---|---|
| Target Package | Mandatory (`YouTube`, `Instagram`, `TikTok`) | `null` |
| `eligibleForAccess` | **`true`** | **`false`** |
| `accessDurationSeconds` | **$300$** ($5$ min) | **$0$** |
| Access Authorization | Granted by downstream Access Engine | **Never authorized** |

A free workout session can **never** produce an access authorization, preventing security bypasses.

---

## 7. Error Hierarchy

All session errors derive from `WorkoutSessionException`:

```text
WorkoutSessionException (base)
 ├── InvalidSessionTransitionException (code: 'INVALID_TRANSITION')
 ├── UnknownSessionException (code: 'UNKNOWN_SESSION')
 ├── SessionAlreadyActiveException (code: 'SESSION_ALREADY_ACTIVE')
 ├── IncompleteWorkoutException (code: 'INCOMPLETE_WORKOUT')
 ├── SessionTerminatedException (code: 'SESSION_TERMINATED')
 └── InvalidProgressException (code: 'INVALID_PROGRESS')
```

---

## 8. Future Integration Roadmap

- **Module 06 (Access Engine)**: Will subscribe to `WorkoutResult` where `eligibleForAccess == true` and call `INativeBridge.grantAccess(minutes: 5)`.
- **Module 07 (Progress Engine & Local Database)**: Will store verified `WorkoutResult` records in local SQLite/DataStore to track streaks, weekly history, and XP.
- **Flutter UI Integration**: UI screens will consume `sessionStream` to render live rep counters ($X / 5$) and progress bars without polling.
