# LevelUp — Core Integration Phase A (Headless Integration)

**Document:** Core Integration Architecture and Phase A Specification  
**Status:** Canonical Reference for Developer 1 (Core) and Developer 2 (UI)  
**Source of Truth:** [README.md](../README.md) · [docs/contracts.md](contracts.md) · Modules 01–07  
**Branch:** `feature/core`

---

## 1. Overview & Objectives

Core Integration Phase A connects Modules 01–07 into a unified, reliable, headless application-level workflow without building the final Flutter UI or altering the working prototype in `lib/main.dart` or `MainActivity.kt`.

### Core Goals Satisfied:
1. **Unified Orchestration:** Connects `NativeBridge`, `FocusService`, `ChallengeService`, `SquatCounter`, `WorkoutSessionManager`, `AccessService`, `WorkoutHistoryRepository`, and `AccessAttemptRepository`.
2. **Strict Workflow Separation:** Separates voluntary **Free Workout** (history saved, access never granted) from **Unlock Challenge** (gate validation, verified repetitions, access granted, audit journaled).
3. **Verified Repetition Guarantees:** Rejects arbitrary button taps; only verified pose frames from `SquatCounter` / `IPoseEventSource` advance session progress.
4. **Crash-Safe SQLite Journaling:** Records `AccessAttemptState.prepared` prior to platform channel invocation; prevents automatic retries of prepared/uncertain grants; guarantees no native invocation if SQLite fails.
5. **Reversible & Additive:** Preserves all existing prototype code, leaving the Pixel demo functional and untouched.

---

## 2. Service Dependency Graph

```
                                 ┌──────────────────────────────┐
                                 │   UI / Developer Lab         │
                                 │   (Phase B: Screens / Views) │
                                 └──────────────┬───────────────┘
                                                │ (observes stateStream, triggers workflows)
                                                ▼
                               ┌───────────────────────────────────┐
                               │    ICoreIntegrationCoordinator    │
                               │   (CoreIntegrationCoordinator)    │
                               └────────┬──────────────┬───────────┘
                                        │              │
           ┌────────────────────────────┼──────────────┼────────────────────────────┐
           │                            │              │                            │
           ▼                            ▼              ▼                            ▼
┌─────────────────────┐      ┌────────────────────┐ ┌────────────────────┐ ┌───────────────────┐
│    IFocusService    │      │ IChallengeService  │ │   IPoseEventSource │ │IWorkoutSession-   │
│   (FocusService)    │      │ (ChallengeService) │ │(PoseEngineAdapter) │ │    Manager        │
└──────────┬──────────┘      └──────────┬─────────┘ └─────────┬──────────┘ └─────────┬─────────┘
           │                            │                     │                      │
           │                            ▼                     │                      ▼
           │                 ┌────────────────────┐           │             ┌──────────────────┐
           │                 │  ChallengeCatalog  │           │             │  WorkoutSession  │
           │                 └────────────────────┘           │             │  (WorkoutResult) │
           │                                                  │             └────────┬─────────┘
           │                                                  ▼                      │
           │                                       ┌────────────────────┐            │
           │                                       │    SquatCounter    │            │
           │                                       └────────────────────┘            │
           │                                                                         │
           ├─────────────────────────────────────────────────────────────────────────┤
           │                                                                         │
           ▼                                                                         ▼
┌─────────────────────┐                                                    ┌───────────────────┐
│   IAccessService    │                                                    │IWorkoutHistory-   │
│   (AccessService)   │                                                    │   Repository      │
└──────────┬──────────┘                                                    └─────────┬─────────┘
           │                                                                         │
           ▼                                                                         │
┌─────────────────────┐                                                              │
│IAccessAttemptRepo-  │                                                              │
│      sitory         │                                                              │
└──────────┬──────────┘                                                              │
           │                                                                         │
           ▼                                                                         ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                                 LevelUp SQLite Persistence                                   │
│                        (workout_sessions, access_attempts tables)                            │
└──────────────────────────────────────────────┬───────────────────────────────────────────────┘
                                               │
                                               ▼
                               ┌───────────────────────────────┐
                               │         INativeBridge         │
                               │   (MethodChannel Platform)    │
                               └───────────────┬───────────────┘
                                               │
                                               ▼
                               ┌───────────────────────────────┐
                               │   Android Native Layer        │
                               │  (MainActivity / Blocker v3)  │
                               └───────────────────────────────┘
```

---

## 3. Public Coordinator API

Located in [lib/core/integration/core_integration_coordinator.dart](../lib/core/integration/core_integration_coordinator.dart):

```dart
abstract class ICoreIntegrationCoordinator {
  /// Reactive state snapshot and stream for UI observation
  CoordinatorState get currentState;
  Stream<CoordinatorState> get stateStream;

  /// Lifecycle & initialization
  Future<void> initialize();
  void dispose();

  /// Challenge entry points
  Future<WorkoutSession> launchUnlockChallenge({bool requirePendingRequest = false});
  Future<WorkoutSession> launchFreeWorkout();

  /// Pose Engine connection
  void attachPoseEventSource(IPoseEventSource source);
  void detachPoseEventSource();
  Future<WorkoutSession?> handlePoseResult(SquatCounterResult result, {String? eventId});

  /// Session control
  Future<WorkoutSession> cancelCurrentSession({String? reason});
  Future<WorkoutSession> failCurrentSession({required String reason});
  Future<void> completeCurrentSession();

  /// Test & sync synchronization
  Future<void> waitForCompletion([Duration timeout = const Duration(seconds: 5)]);
}
```

---

## 4. Integration Workflows

### 4.1 Unlock Challenge Flow
```
User / Native Overlay
       │
       ▼
launchUnlockChallenge()
  ├── 1. IFocusService.getFocusStatus()
  │      ├── Verify isAccessibilityGranted == true (else MissingAccessibilityPermissionException)
  │      ├── Verify isUserEnabled == true (else FocusDisabledException)
  │      └── Verify target in allowedTargets (else UnsupportedTargetException)
  ├── 2. INativeBridge.consumeChallengeRequest() (atomically resets open_challenge flag)
  ├── 3. IChallengeService.createUnlockChallengeRequest(target)
  └── 4. IWorkoutSessionManager.createSession() & startSession()
       │
       ▼ (Session in active state)
  Live Squat Tracking (IPoseEventSource / Camera)
       ├── SquatCounter evaluates knee angles: Standing -> Squat (<125°) -> Standing (>155°)
       └── Emits SquatCounterResult(reps, isRepetitionCompleted: true)
       │
       ▼
  handlePoseResult()
       ├── Monotonic repetition progress forwarded to WorkoutSessionManager
       └── When verifiedRepetitions >= targetRepetitions (5) -> triggers completion workflow
       │
       ▼
  Completion Workflow
       ├── 1. Retrieve authoritative WorkoutResult
       ├── 2. IWorkoutHistoryRepository.saveCompletedWorkout(result) -> SQLite
       ├── 3. IAccessAttemptRepository.getAttemptBySessionId(sessionId)
       │      ├── If confirmed: return (idempotent, no re-grant)
       │      └── If prepared / uncertain: throw (no automatic retry)
       ├── 4. IAccessAttemptRepository.createAttemptIfAbsent(state: prepared) -> SQLite
       │      (CRITICAL: If SQLite write fails, native grant is ABORTED)
       ├── 5. IAccessService.grantAccessForCompletedWorkout(result) -> INativeBridge.grantAccess(5)
       └── 6. IAccessAttemptRepository.markConfirmed(unlockUntil) -> SQLite
```

### 4.2 Free Workout Flow
```
User (Challenge Tab)
       │
       ▼
launchFreeWorkout()
  ├── 1. IChallengeService.createFreeWorkoutRequest() (targetPackage: null, accessDuration: 0)
  └── 2. IWorkoutSessionManager.createSession() & startSession()
       │
       ▼
  handlePoseResult() (tracks verified squats up to goal)
       │
       ▼
  Completion Workflow
       ├── 1. Retrieve authoritative WorkoutResult (eligibleForAccess: false)
       ├── 2. IWorkoutHistoryRepository.saveCompletedWorkout(result) -> SQLite
       └── 3. FINISH (Never invoke AccessService or create access_attempts record)
```

---

## 5. Failure & Recovery Semantics

| Scenario | Behavior & State Mutation |
|---|---|
| **Missing Accessibility Permission** | `launchUnlockChallenge()` throws `MissingAccessibilityPermissionException`. No session created. |
| **Focus Mode Disabled** | `launchUnlockChallenge()` throws `FocusDisabledException`. No session created. |
| **Target Package Mismatch at Completion** | `AccessService` throws `TargetPackageMismatchException`. Completed workout history is saved in SQLite, but `access_attempts` is marked `definitivelyRejected`. Native `grantAccess` is never invoked. |
| **SQLite Write Failure before Native Grant** | SQLite throws `PersistenceException`. Process aborts immediately before calling `grantAccess`. No native grant is issued. |
| **Ambiguous Native Outcome (Timeout/Crash)** | Native channel throws `PlatformException` or `NativeBridgeException`. `access_attempts` record is marked `AccessAttemptState.uncertain` with failure message. Never auto-retried. |
| **Restart with Prepared Attempt** | Coordinator detects `attempt.requiresReconciliation == true`. Refuses to call native `grantAccess` automatically without explicit reconciliation. |
| **Restart with Confirmed Attempt** | Coordinator detects `attempt.isConfirmed == true`. Returns authoritative cached state without duplicate native invocation. |
| **User Voluntary Cancellation** | `cancelCurrentSession()` sets status to `cancelled`. Subsequent pose events are ignored. No history or access recorded. |
| **Camera Failure** | `failCurrentSession(reason)` sets status to `failed`. Subsequent pose events ignored. |

---

## 6. Remaining Native Limitations

1. **`consumeChallengeRequest` Attribution:**
   - The native platform call returns only a boolean indicating whether the barrier overlay was clicked.
   - It does not pass an authenticated session token or package name. The coordinator binds the challenge to whatever target is actively selected in `FocusService`.
2. **Native `grantAccess` Arguments:**
   - The native MethodChannel implementation in `MainActivity.kt` only accepts `{'minutes': Int}`.
   - It does not receive `sessionId` or `targetPackage`. Native unlocks whatever package is saved in `SharedPreferences["target"]` and launches it.
   - The coordinator validates target package equivalence before native invocation, but cannot prevent race conditions if native settings are modified concurrently outside the Flutter process.

---

## 7. Developer Lab (Phase B) Requirements

Phase B will implement the developer testing screen (`DeveloperLabScreen`) without touching teammate files in `feature/ui`. It will:
1. Provide one-tap buttons to trigger `launchUnlockChallenge()` and `launchFreeWorkout()`.
2. Bind the existing camera preview and ML Kit pipeline from `lib/main.dart` through `PoseEngineAdapter`.
3. Display real-time reactive stats from `coordinator.stateStream`:
   - Active session ID and status.
   - Verified repetition count and knee angle.
   - Focus gate enabled status and target app.
   - Access expiration countdown timer.
   - SQLite persistence status (workout history & attempt journal).
4. Provide manual simulation triggers to test edge cases on device (e.g. simulate timeout, reset access).

---

## 8. Physical Pixel Testing Checklist

Before the competition demo on November 25, run this manual checklist on the physical Google Pixel:
- [ ] Install application and verify Accessibility Service is listed in Android Settings.
- [ ] Enable `LevelUpAccessibilityService` in Accessibility Settings.
- [ ] Open LevelUp, select YouTube as target, and turn on voluntary Focus mode.
- [ ] Open YouTube directly: verify LevelUp restriction barrier appears immediately.
- [ ] Press "Start challenge" on the barrier: verify LevelUp opens to challenge.
- [ ] Stand in front of camera: perform 5 full bodyweight squats.
- [ ] Verify repetition counter increments accurately from 0 to 5.
- [ ] Upon 5th repetition, verify YouTube opens automatically with 5 minutes of access.
- [ ] Return to LevelUp: verify access countdown displays approximately 5 minutes remaining.
- [ ] Restart LevelUp: verify workout session appears in SQLite history and access attempt is marked `confirmed`.
- [ ] Wait 5 minutes (or tap Reset): verify YouTube is locked again when opened.