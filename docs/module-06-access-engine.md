# Module 06 — Access Engine

> **Status:** Implemented and unit-tested  
> **Branch:** `feature/core`  
> **Dependencies:** Module 01 (Native Bridge), Module 05 (Workout Session Manager)

## Overview

The Access Engine is the final authorization layer between a completed physical workout and temporary Android application access. It validates workout results, enforces safety preconditions, and orchestrates the existing native `grantAccess` platform call through the Module 01 Native Bridge.

**The Access Engine never retries failed grants, never awards XP, and never persists state to disk.**

## Public API

### IAccessService

```dart
abstract class IAccessService {
  Future<AccessGrantResult> grantAccessForCompletedWorkout(WorkoutResult result);
  Future<AccessGrantResult> requestAccess(AccessGrantRequest request);
  Future<NativeAccessStatus> getAccessStatus();
  Future<bool> resetAccess();
  Stream<AccessGrantResult> get grantStream;
  void dispose();
}
```

### AccessService

Production implementation using `INativeBridge`. Accepts optional dependency injection:

```dart
AccessService({
  INativeBridge? bridge,  // Defaults to const NativeBridge()
  DateTime Function()? clock,  // Defaults to DateTime.now
});
```

## Validation Pipeline

When `grantAccessForCompletedWorkout(WorkoutResult)` is called, the following checks execute in order:

| Step | Check | Exception on Failure |
|------|-------|---------------------|
| 1 | `challengeContext == unlockChallenge && eligibleForAccess` | `IneligibleWorkoutContextException` |
| 2 | Resolve authoritative `definition` from `ChallengeCatalog` by `challengeId` | `IneligibleWorkoutContextException` |
| 3 | Definition specifies access duration > 0 | `IneligibleWorkoutContextException` |
| 4 | `exerciseType == definition.exerciseType` | `IneligibleWorkoutContextException` |
| 5 | `completedRepetitions >= definition.targetRepetitions` | `IncompleteWorkoutResultException` |
| 6 | `targetPackage ∈ allowedTargets` | `UnsupportedAccessTargetException` |
| 7 | `accessDurationSeconds > 0` | `InvalidAccessDurationException` |
| 8 | Direct `requestAccess` runtime validation (context, target, duration bounds 1..15) | `IneligibleWorkoutContextException` / `UnsupportedAccessTargetException` / `InvalidAccessDurationException` |
| 9 | Duplicate session suppression (in-memory) | Returns cached `AccessGrantResult` |
| 10 | Concurrent request guard | `ConcurrentGrantException` |
| 11 | Native: `isAccessibilityGranted == true` | `MissingAccessibilityPermissionException` |
| 12 | Native: `isGateEnabled == true` | `FocusDisabledException` |
| 13 | Native: `targetPackage == request.targetPackage` | `TargetPackageMismatchException` |
| 14 | Invoke `bridge.grantAccess(minutes: N)` | `AccessEnginePlatformException` |

Steps 1–7 happen in `AccessGrantRequest.fromWorkoutResult()`.  
Step 8 happens in `AccessGrantRequest` constructor and `AccessService.requestAccess()`.  
Steps 9–14 happen in `AccessService.requestAccess()`.

## Models

### AccessGrantRequest

Factory-constructed from `WorkoutResult`. Clamps `accessDurationSeconds` to 1–15 minutes.

```
lib/models/access_grant_request.dart
```

### AccessGrantResult

Immutable result containing:

- `sessionId` — originating workout session
- `targetPackage` — unlocked application
- `status` — `AccessGrantStatus` enum
- `unlockUntil` — authoritative expiration timestamp from native
- `grantedAt` — Dart-side timestamp of grant execution

Provides computed helpers:
- `isSuccessful` — true for `granted` or `alreadyActive`
- `isAccessActive(DateTime now)` — time-relative active check
- `remainingDuration(DateTime now)` — remaining `Duration`

```
lib/models/access_grant_result.dart
```

### AccessGrantStatus

```dart
enum AccessGrantStatus { granted, alreadyActive, rejected, failed }
```

## Exception Hierarchy

All exceptions extend `AccessEngineException`:

| Exception | Code | Trigger |
|-----------|------|---------|
| `IneligibleWorkoutContextException` | `INELIGIBLE_CONTEXT` | Free workout or non-eligible result |
| `IncompleteWorkoutResultException` | `INCOMPLETE_RESULT` | 0 verified repetitions |
| `UnsupportedAccessTargetException` | `UNSUPPORTED_TARGET` | Package not in allowed targets |
| `InvalidAccessDurationException` | `INVALID_DURATION` | Duration ≤ 0 seconds |
| `MissingAccessibilityPermissionException` | `PERMISSION_MISSING` | Accessibility not granted |
| `FocusDisabledException` | `FOCUS_DISABLED` | Voluntary restriction disabled |
| `TargetPackageMismatchException` | `TARGET_MISMATCH` | Workout target ≠ native target |
| `ConcurrentGrantException` | `CONCURRENT_GRANT` | Same sessionId already in-flight |
| `AccessEnginePlatformException` | `PLATFORM_ERROR` | Native bridge or platform failure |

## Native Contract Limitations

### What `grantAccess({'minutes': int})` does

1. Receives integer `minutes` only — no `sessionId`, no `targetPackage`.
2. Computes `System.currentTimeMillis() + minutes * 60_000L`.
3. Writes result to `SharedPreferences("unlock_until")`.
4. Returns the epoch millisecond value.

### What it does NOT do

- Accept or verify which package is being unlocked.
- Accept a `sessionId` for server-side idempotency.
- Provide a transactional guarantee (write-then-read is not atomic).

### Race condition: `setTarget` clears access

Calling `setTarget(newPackage)` in `MainActivity.kt` writes `0L` to `"unlock_until"`, immediately revoking any active access window. `AccessService` mitigates this by verifying `nativeStatus.targetPackage == request.targetPackage` before invoking `grantAccess`.

## Explicitly Documented Architectural Limitations

1. **Native `grantAccess` API Scope:** `MainActivity.kt`'s `grantAccess` accepts only integer `minutes`. It does not accept `sessionId` or `targetPackage`. Native code grants access globally to whatever target is in SharedPreferences.
2. **Target Selection TOCTOU Race:** There is an inherent Time-of-Check to Time-of-Use window between Dart verifying `nativeStatus.targetPackage == workoutTarget` via `getState()` and native executing `grantAccess()`. If `setTarget` is called during this window, the newly selected package is granted instead.
3. **Process Restart Idempotency Boundary:** `_grantedSessions` duplicate suppression is in-memory only. Upon process kill/restart, in-memory history is cleared. Durable session idempotency requires Module 07 (local database with unique session ID constraints) and future Kotlin contract updates.
4. **Prototype Bypass:** `lib/main.dart` directly invokes `native.invokeMethod('grantAccess')` as an experimental camera prototype. It will be replaced during UI/Core integration.
5. **Untrusted Client Data Boundary:** A client-side `WorkoutResult` instantiated in Dart is an in-process DTO; the Access Engine validates logical consistency, definition matching, and preconditions, but client-side DTOs cannot provide cryptographic proof of human physical activity.

## Test Coverage

**38 unit tests** in Module 06 covering:
- Repetition threshold enforcement (0/5, 1/5, 4/5 rejected; 5/5 accepted)
- Challenge definition lookups and matching from `ChallengeCatalog`
- Rejection of unknown challenges, mismatched exercise types, and free workouts
- Direct constructor runtime validation on `AccessGrantRequest`
- Authorization preconditions (permissions, gate enabled, target match)
- Concurrency guard (simultaneous in-flight requests)
- Safe error handling on IPC failures without unsafe retries
- Reactive `grantStream` event emission
- Full model equality and serialization verification
