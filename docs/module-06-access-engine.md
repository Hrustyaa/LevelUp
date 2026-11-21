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
| 2 | `completedRepetitions > 0` | `IncompleteWorkoutResultException` |
| 3 | `targetPackage ∈ allowedTargets` | `UnsupportedAccessTargetException` |
| 4 | `accessDurationSeconds > 0` | `InvalidAccessDurationException` |
| 5 | Duplicate session suppression (in-memory) | Returns cached `AccessGrantResult` |
| 6 | Concurrent request guard | `ConcurrentGrantException` |
| 7 | Native: `isAccessibilityGranted == true` | `MissingAccessibilityPermissionException` |
| 8 | Native: `isGateEnabled == true` | `FocusDisabledException` |
| 9 | Native: `targetPackage == request.targetPackage` | `TargetPackageMismatchException` |
| 10 | Invoke `bridge.grantAccess(minutes: N)` | `AccessEnginePlatformException` |

Steps 1–4 happen in `AccessGrantRequest.fromWorkoutResult()`.  
Steps 5–10 happen in `AccessService.requestAccess()`.

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

### Process restart boundary

In-memory duplicate suppression (`_grantedSessions`) is lost on app process restart. Without a `sessionId` in native storage, durable idempotency requires Module 07 (local database with unique session constraints).

## Reactive Stream

`grantStream` emits `AccessGrantResult` on each successful grant. UI consumers can listen to display countdown timers or unlock confirmations.

## Integration Points

### With WorkoutSessionManager (Module 05)

```dart
final result = workoutSessionManager.completeSession();
if (result.eligibleForAccess) {
  final grant = await accessService.grantAccessForCompletedWorkout(result);
  // Show unlock UI
}
```

### With FocusService (Module 02)

AccessService queries `INativeBridge.getState()` to verify focus state. It does **not** call `FocusService` directly — both operate on the same native state through `INativeBridge`.

## For the UI Developer

1. **Call `grantAccessForCompletedWorkout(workoutResult)` after workout completion.**
2. **Handle every typed exception** to show user-appropriate feedback.
3. **Listen to `grantStream`** for real-time unlock notifications.
4. **Use `getAccessStatus()`** to check remaining access time.
5. **Use `resetAccess()`** only for explicit user-initiated access revocation.
6. **Never call `grantAccess` directly on `NativeBridge`** — always go through `AccessService`.

## Required Future Kotlin Enhancements

1. **Atomic `grantAccess(sessionId, targetPackage, minutes)`** — allows native-level idempotency and target verification.
2. **Native sessionId persistence** — crash-safe duplicate prevention.
3. **`getAccessStatus()` with remaining seconds** — eliminates Dart-side clock skew.

## Files

| File | Purpose |
|------|---------|
| `lib/core/errors/access_exceptions.dart` | Typed exception hierarchy |
| `lib/models/access_grant_status.dart` | Status enum |
| `lib/models/access_grant_request.dart` | Request model with factory validation |
| `lib/models/access_grant_result.dart` | Immutable grant result |
| `lib/services/access_service.dart` | `IAccessService` + `AccessService` implementation |
| `test/models/access_models_test.dart` | Model unit tests |
| `test/services/access_service_test.dart` | Service unit tests (24 tests) |

## Test Coverage

**24 unit tests** covering:
- 8 authorization precondition validations
- 10 native grant invariants and idempotency guarantees
- 1 reactive stream emission
- 5 model equality, computation, and serialization tests
