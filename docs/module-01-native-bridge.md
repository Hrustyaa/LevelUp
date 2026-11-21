# Module 01 — Native Bridge

**Component:** Android Platform Channel Integration & Typed Native Bridge  
**Layer:** Core Infrastructure (`lib/services/`, `lib/models/`, `lib/core/`)  
**Status:** Completed & Validated  
**Working Branch:** `feature/core`

---

## 1. Purpose of this Module

The LevelUp application relies on Android operating system capabilities that are outside Flutter's standard sandbox:
1. Detecting foreground application changes using `LevelUpAccessibilityService` (Blocker v3).
2. Displaying a system-level gate overlay (`TYPE_ACCESSIBILITY_OVERLAY`) when a restricted app is launched.
3. Launching system Accessibility settings.
4. Managing temporary access timestamps in native `SharedPreferences`.
5. Automatically launching target applications (YouTube, Instagram, TikTok) when exercises are completed.

Module 01 introduces a **clean, typed, null-safe, and testable Dart Native Bridge** around the existing Android Kotlin contracts without rewriting or destabilizing existing native logic.

---

## 2. File Structure

```text
lib/
  core/
    constants/
      channel_constants.dart          # Canonical channel name ('levelup_test/control'), method names, and package IDs
    errors/
      native_bridge_exception.dart    # Hierarchy: NativeBridgeException, UnsupportedTargetPackageException, etc.
  models/
    native_permission_status.dart     # Accessibility service enabled state
    native_access_status.dart         # Temporary unlock duration and calendar time calculations
    native_focus_status.dart          # Composed live gate snapshot (target, enabled, permission, access)
  services/
    native_bridge.dart                # INativeBridge interface & NativeBridge implementation

test/
  models/
    native_models_test.dart           # Model parsing, fallback handling, equality and duration tests
  services/
    native_bridge_test.dart           # 37 unit tests covering method calls, arguments, exceptions, and state discrimination

docs/
  contracts.md                        # Master API contract reference
  module-01-native-bridge.md          # Architectural guide for Module 01
```

---

## 3. How Flutter Communicates with Kotlin

### 3.1 Architecture Overview
Communication is coordinated over a single binary `MethodChannel`:
```text
Flutter (Dart)                          Android (Kotlin)
┌───────────────────────┐               ┌──────────────────────────────────────┐
│  INativeBridge        │               │  MainActivity.kt                     │
│  (NativeBridge)       │               │  - Registers 'levelup_test/control'  │
│         │             │               │  - Reads/writes 'levelup_gate' prefs │
│         ▼             │               │  - Invokes reevaluate() on service   │
│  MethodChannel        │ ◄──────────►  │         │                            │
│  'levelup_test/control│               └─────────┼────────────────────────────┘
└───────────────────────┘                         ▼
                                        ┌──────────────────────────────────────┐
                                        │  LevelUpAccessibilityService.kt      │
                                        │  - Blocker v3: Latched overlay       │
                                        │  - HOME audio mitigation             │
                                        │  - Opt-in soft gate                  │
                                        └──────────────────────────────────────┘
```

### 3.2 Channel Contracts Summary
- **Channel ID:** `levelup_test/control`
- **Active Native Methods:**
  1. `getState`: Reads `"target"`, `"enabled"`, `"unlockUntil"`, and `"serviceEnabled"`.
  2. `setTarget`: Updates restricted package; enforces allowed set (`YouTube`, `Instagram`, `TikTok`).
  3. `setEnabled`: Toggles gate restriction on/off.
  4. `openAccessibilitySettings`: Opens Android Accessibility Settings intent.
  5. `consumeChallengeRequest`: Atomic read-and-clear of `"open_challenge"` flag.
  6. `grantAccess`: Sets `unlock_until = now + minutes * 60,000` and launches target app intent.
  7. `resetAccess`: Clears `unlock_until` and re-arms restriction.

---

## 4. What is Implemented & What is Not

### 4.1 Implemented Capabilities
- **Typed Models:**
  - `NativeFocusStatus`: complete gate snapshot.
  - `NativePermissionStatus`: encapsulates system accessibility service availability.
  - `NativeAccessStatus`: computes calendar expiration and remaining duration.
- **Robust Parsing:**
  - Graceful fallback for null, missing, or malformed fields without runtime crashes.
- **Explicit Error Handling:**
  - `UnsupportedTargetPackageException`: thrown when native rejects package with code `'TARGET'`.
  - `NativeBridgeNotImplementedException`: thrown when `MissingPluginException` occurs.
  - `MalformedNativeResponseException`: thrown when unexpected data is returned.
- **State Discrimination:** Callers can distinguish between:
  1. Gate enabled by user (`status.isGateEnabled`).
  2. Accessibility permission granted (`status.isAccessibilityGranted`).
  3. Native bridge available (`await bridge.isAvailable()`).
  4. Temporary access active (`status.isAccessActive`).
- **Testability:**
  - `INativeBridge` interface allows mock injection.
  - `NativeBridge` accepts custom `MethodChannel` instances for unit testing without third-party mocking libraries.

### 4.2 Native API Gaps (Proposed for Future Modules)
The following features are **not supported by the current Kotlin layer** and must not be fabricated:
1. **EventChannel / Reactive Stream:** Kotlin does not push events to Dart when windows change. Status must be queried on lifecycle resume (`didChangeAppLifecycleState`) or polled.
2. **Dynamic Application List:** Android Manifest `<queries>` and Kotlin `allowedTargets` restrict targets strictly to YouTube, Instagram, and TikTok.
3. **Camera Permission Status:** Handled via Flutter `camera` plugin; not exposed via `levelup_test/control`.
4. **Workout Telemetry Persistence:** Not saved in native `SharedPreferences`; handled in Dart data layer.

---

## 5. How Future Services Should Use This Bridge

Higher-level application services (e.g. `FocusService`, `AccessService`) should depend on `INativeBridge` rather than calling `MethodChannel` directly:

```dart
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/services/native_bridge.dart';

class FocusService {
  final INativeBridge _bridge;

  FocusService({INativeBridge? bridge}) : _bridge = bridge ?? const NativeBridge();

  Future<NativeFocusStatus> getFocusStatus() => _bridge.getState();

  Future<void> enableFocus(bool enable) async {
    final status = await _bridge.getState();
    if (enable && !status.isAccessibilityGranted) {
      throw StateError('Accessibility service must be enabled before activating focus.');
    }
    await _bridge.setEnabled(enable);
  }

  Future<void> openSettings() => _bridge.openAccessibilitySettings();
}

class AccessService {
  final INativeBridge _bridge;

  AccessService({INativeBridge? bridge}) : _bridge = bridge ?? const NativeBridge();

  Future<DateTime> unlockAfterExercise({int minutes = 5}) async {
    return _bridge.grantAccess(minutes: minutes);
  }

  Future<void> lockImmediately() async {
    await _bridge.resetAccess();
  }
}
```
