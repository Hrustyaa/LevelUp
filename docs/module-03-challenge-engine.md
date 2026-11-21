# Module 03 — Challenge Engine

**Component:** Physical Challenge Catalog, Domain Models & Request Validation  
**Layer:** Feature Domain & Application Layer (`lib/models/`, `lib/features/challenge/`)  
**Status:** Completed & Validated  
**Working Branch:** `feature/core`

---

## 1. Purpose of Challenge Engine

The **Challenge Engine** is the central domain authority for defining physical exercises, challenge parameters, and session requests in LevelUp. 

It isolates the *rules* and *configurations* of physical challenges from:
- Biomechanical frame processing (Google ML Kit pose detection).
- Live session execution and repetition counting (Workout Session Manager).
- Android application access grants (Access Engine).
- User habit progression and XP persistence (Progress Engine).

By centralizing challenge definitions, it ensures that challenge criteria (e.g. 5 squats for 5 minutes of access) are deterministic and immutable rather than hardcoded separately across UI screens.

---

## 2. Domain Models

All models are immutable, null-safe Dart objects located in `lib/models/`:

### 2.1 `ChallengeType` (`lib/models/challenge_type.dart`)
Distinguishes the operational context:
- `unlockChallenge`: Performed to earn temporary calendar access to a restricted distracting application.
- `freeWorkout`: Voluntary physical activity without an app-unlock reward grant.

### 2.2 `ExerciseType` (`lib/models/exercise_type.dart`)
Defines the biomechanical movement:
- `squats`: Standard bodyweight squats with standing $\rightarrow$ bottom $\rightarrow$ standing state transitions.
- Designed to be extensible for future movements (e.g. pushups, lunges) without redesigning the Challenge Engine.

### 2.3 `ChallengeDefinition` (`lib/models/challenge_definition.dart`)
Configuration of a physical challenge:
- `challengeId`: String identifier (e.g. `'squats_unlock_5'`).
- `exerciseType`: Associated movement (`ExerciseType.squats`).
- `title` & `description`: User-facing localized strings.
- `targetRepetitions`: Validated positive integer ($> 0$).
- `accessDurationSeconds`: Non-negative integer ($\ge 0$). Describes potential unlock duration.
- `optionalXpReward`: Optional metadata for future Progress Engine XP allocation.

### 2.4 `ChallengeRequest` (`lib/models/challenge_request.dart`)
An instantiated session request awaiting execution:
- `requestId`: Unique identifier for session tracking.
- `challengeId`: ID of the target definition.
- `context`: `unlockChallenge` or `freeWorkout`.
- `targetPackage`: The targeted restricted app. Mandatory for unlock challenges; MUST be `null` for free workouts.
- `createdAt`: Timestamp.

### 2.5 `ChallengeReward` (`lib/models/challenge_reward.dart`)
Descriptive metadata only:
- `xpAmount`: Base XP.
- `accessDurationSeconds`: Screen time in seconds.
- `eligibleForAccess`: Whether this challenge qualifies for an Android access grant.
> *Note: This module does NOT grant access or persist XP.*

---

## 3. Challenge Catalog (`lib/features/challenge/data/challenge_catalog.dart`)

The MVP defines two canonical challenges:

| Challenge | ID | Exercise | Target Reps | Possible Access | Eligible for Unlock | XP Metadata |
|---|---|---|---|---|---|---|
| **5 Squats Unlock** | `squats_unlock_5` | `ExerciseType.squats` | 5 | 300 sec (5 min) | **Yes** | 50 XP |
| **5 Squats Quick Set** | `squats_free_5` | `ExerciseType.squats` | 5 | 0 sec | **No** | 50 XP |

---

## 4. Public ChallengeService API (`IChallengeService`)

Located in `lib/features/challenge/application/challenge_service.dart`:

```dart
abstract class IChallengeService {
  List<ChallengeDefinition> getAvailableChallenges();
  ChallengeDefinition getDefaultUnlockChallenge();
  ChallengeDefinition getDefaultFreeWorkout();
  ChallengeDefinition getChallengeDefinition(String challengeId);
  ChallengeRequest createUnlockChallengeRequest(String targetPackage);
  ChallengeRequest createFreeWorkoutRequest();
  void validateChallengeRequest(ChallengeRequest request);
}
```

---

## 5. Validation Rules

All operations validate inputs with typed exceptions (`lib/core/errors/challenge_exceptions.dart`):

1. **Repetition & Duration Invariants**: `targetRepetitions` must be $> 0$; `accessDurationSeconds` must be $\ge 0$.
2. **Context Integrity**:
   - `unlockChallenge` **requires** a valid `targetPackage` in `ChannelConstants.allowedTargets` (`YouTube`, `Instagram`, `TikTok`).
   - `freeWorkout` **rejects** requests containing a `targetPackage`.
3. **Definition Matching**: An unlock request cannot point to a definition with 0 access duration.
4. **Idempotent / Deterministic Requests**: Sequential requests generate unique, verifiable `requestId` values.

---

## 6. Integration Boundaries & Native Trigger Limitations

```text
┌───────────────────────────┐      ┌─────────────────────────────┐
│ Android Native Overlay    │      │ User in Flutter App         │
│ (Taps "Start challenge")  │      │ (Selects Free Workout / Go) │
└─────────────┬─────────────┘      └──────────────┬──────────────┘
              │                                   │
              ▼                                   ▼
┌───────────────────────────┐      ┌─────────────────────────────┐
│ MainActivity.kt           │      │ FocusService                │
│ open_challenge = true     │      │ Confirms selected target    │
└─────────────┬─────────────┘      └──────────────┬──────────────┘
              │                                   │
              ▼                                   │
┌───────────────────────────┐                     │
│ consumeChallengeRequest() │                     │
│ (returns boolean flag)    │                     │
└─────────────┬─────────────┘                     │
              │                                   │
              └───────────────┬───────────────────┘
                              ▼
               ┌─────────────────────────────┐
               │ ChallengeService            │
               │ Creates ChallengeRequest    │
               │ (Validates target & context)│
               └──────────────┬──────────────┘
                              ▼
               ┌─────────────────────────────┐
               │ [Future: Module 04]         │
               │ Workout Session Manager     │
               │ - Feeds frames to ML Kit    │
               │ - Validates 5 reps          │
               └──────────────┬──────────────┘
                              ▼
               ┌─────────────────────────────┐
               │ [Future: Module 05]         │
               │ Access & Progress Engine    │
               │ - Invokes grantAccess(5)    │
               │ - Persists earned XP        │
               └─────────────────────────────┘
```

### 6.1 Native Trigger Limitation (`consumeChallengeRequest`)
The native Android method `consumeChallengeRequest` returns only a boolean indicating whether the user tapped "Start challenge" on the native gate overlay. 

**Important Architectural Fact**:
- Native `consumeChallengeRequest` does **not** specify which package was being accessed or pass package metadata.
- Therefore, the upcoming Session Coordinator must query `FocusService.getSelectedTarget()` to securely pair the pending native challenge request with the active restricted target package.

---

## 7. Future Extension to Additional Exercises

When adding new exercises (e.g. pushups, lunges):
1. Add new enum value to `ExerciseType`.
2. Add new `ChallengeDefinition` entries in `ChallengeCatalog`.
3. Add corresponding biomechanical state machine in `pose_detection`.
4. The Challenge Engine architecture requires **zero breaking changes** to accommodate new movements.
