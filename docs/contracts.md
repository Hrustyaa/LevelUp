# LevelUp — Interface Contracts & APIs

**Document:** Platform Bridge & Inter-Module Contracts  
**Status:** Canonical Reference for Developer 1 (Core) and Developer 2 (UI)  
**Source of Truth:** [README.md](../README.md)

---

## 1. Overview & Separation of Concerns

Communication between the Flutter UI layer and the Android Kotlin operating system layer is strictly defined. 
- **Developer 2 (UI)** interacts exclusively with the high-level Dart abstraction layer (`IFocusBridgeService`).
- **Developer 1 (Core)** maintains the Kotlin platform implementation in `MainActivity.kt` and `LevelUpAccessibilityService.kt`.

To prevent regressions, **existing native contracts must remain immutable** during UI enhancements.

---

## 2. Existing Platform Channel API (ACTIVE)

### 2.1 Channel Definition
```dart
const MethodChannel native = MethodChannel('levelup_test/control');
```
- **Channel Name:** `levelup_test/control`
- **Native Implementation:** `android/app/src/main/kotlin/com/levelup/levelup_test/MainActivity.kt`
- **Native Storage:** Android `SharedPreferences` titled `"levelup_gate"` (`Context.MODE_PRIVATE`)

### 2.2 Active Methods Specification

| Method Name | Direction | Arguments (Dart Map) | Return Type | Status & Purpose |
|---|---|---|---|---|
| `getState` | Flutter $\rightarrow$ Android | `null` | `Map<String, dynamic>` | **Active**: Reads current gate state from SharedPreferences and verifies Accessibility status. |
| `setTarget` | Flutter $\rightarrow$ Android | `{'target': String}` | `bool` (`true`) | **Active**: Sets target package, clears access, and triggers service re-evaluation. |
| `setEnabled` | Flutter $\rightarrow$ Android | `{'enabled': bool}` | `bool` (`true`) | **Active**: Toggles voluntary restriction on/off. |
| `openAccessibilitySettings` | Flutter $\rightarrow$ Android | `null` | `bool` (`true`) | **Active**: Dispatches system intent `Settings.ACTION_ACCESSIBILITY_SETTINGS`. |
| `consumeChallengeRequest` | Flutter $\rightarrow$ Android | `null` | `bool` | **Active**: Atomic check-and-clear for pending challenge triggered from native gate overlay. |
| `grantAccess` | Flutter $\rightarrow$ Android | `{'minutes': int}` | `int` (Long timestamp) | **Active**: Writes unlock expiration (`now + minutes`), closes gate, launches target app. |
| `resetAccess` | Flutter $\rightarrow$ Android | `null` | `bool` (`true`) | **Active**: Clears unlock expiration, re-arms gate restriction. |

---

### 2.3 Detailed Method Schemas

#### `getState`
- **Dart Call:**
  ```dart
  final Map<String, dynamic>? state = await native.invokeMapMethod<String, dynamic>('getState');
  ```
- **Kotlin Return Structure:**
  ```kotlin
  mapOf(
      "target" to prefs.getString("target", "com.google.android.youtube"), // String
      "enabled" to prefs.getBoolean("enabled", false),                      // Boolean
      "unlockUntil" to prefs.getLong("unlock_until", 0L),                   // Long (epoch ms)
      "serviceEnabled" to isServiceEnabled()                                // Boolean
  )
  ```

#### `setTarget`
- **Dart Call:**
  ```dart
  await native.invokeMethod('setTarget', {'target': 'com.google.android.youtube'});
  ```
- **Validation:** Must be in allowed packages:
  - `com.google.android.youtube`
  - `com.instagram.android`
  - `com.zhiliaoapp.musically`
- **Error Condition:** Throws `PlatformException(code: "TARGET", message: "Unsupported test package")` if target is outside allowed set.

#### `grantAccess`
- **Dart Call:**
  ```dart
  final int unlockUntil = await native.invokeMethod<int>('grantAccess', {'minutes': 5});
  ```
- **Kotlin Behavior:**
  - `minutes` coerced into range `1..15` (defaults to 5).
  - Calculates: `System.currentTimeMillis() + minutes * 60_000L`.
  - Saves `unlock_until` to `SharedPreferences`.
  - Re-evaluates accessibility gate (releasing overlay if active).
  - Dispatches `packageManager.getLaunchIntentForPackage(target)` with `FLAG_ACTIVITY_NEW_TASK`.

#### `consumeChallengeRequest`
- **Dart Call:**
  ```dart
  final bool challengeRequested = await native.invokeMethod<bool>('consumeChallengeRequest') ?? false;
  ```
- **Kotlin Behavior:** Reads `"open_challenge"` boolean from preferences and immediately resets it to `false`. Used by Flutter when resuming from background after user tapped "Start challenge" on native overlay.

---

## 3. Native Data Storage Specification (SharedPreferences)

| Key | Type | Default | Description |
|---|---|---|---|
| `"target"` | `String` | `"com.google.android.youtube"` | Package identifier of the application currently restricted. |
| `"enabled"` | `Boolean` | `false` | Master toggle for voluntary app gating. |
| `"unlock_until"` | `Long` | `0L` | Epoch millisecond timestamp until which access is granted. |
| `"open_challenge"` | `Boolean` | `false` | Transient flag set when user taps "Start challenge" on overlay. |

---

## 4. Proposed Clean Architecture Dart Interfaces (PROPOSED)

For modular UI development in `lib/features/` and `lib/services/`, Developer 2 should implement and consume these Dart domain abstractions wrapping the low-level MethodChannel.

### 4.1 Domain Models (`lib/models/`)

```dart
/// Represents the live status of the restriction gate
class FocusStatus {
  final String selectedApp;
  final bool isGateEnabled;
  final bool isServiceEnabled;
  final DateTime? accessUntil;

  const FocusStatus({
    required this.selectedApp,
    required this.isGateEnabled,
    required this.isServiceEnabled,
    this.accessUntil,
  });

  bool get isUnlocked => accessUntil != null && accessUntil!.isAfter(DateTime.now());
  Duration get remainingAccess => isUnlocked ? accessUntil!.difference(DateTime.now()) : Duration.zero;
}

/// Represents an exercise completion record
class WorkoutResult {
  final String sessionId;
  final String exerciseId;
  final int repetitions;
  final Duration duration;
  final DateTime completedAt;
  final String source; // 'camera' | 'manual' | 'test'

  const WorkoutResult({
    required this.sessionId,
    required this.exerciseId,
    required this.repetitions,
    required this.duration,
    required this.completedAt,
    required this.source,
  });
}
```

### 4.2 Focus Bridge Service Contract (`lib/services/focus_service.dart`)

```dart
abstract class IFocusService {
  /// Fetches current native state and parses it into FocusStatus
  Future<FocusStatus> getStatus();

  /// Updates the target package
  Future<void> setTarget(String packageId);

  /// Toggles gate enforcement
  Future<void> setEnabled(bool enabled);

  /// Opens Android Accessibility Settings screen
  Future<void> openAccessibilitySettings();

  /// Consumes pending challenge request from native overlay
  Future<bool> consumeChallengeRequest();

  /// Grants access for the specified duration (default: 5 minutes)
  Future<DateTime> grantAccess({int minutes = 5});

  /// Immediately resets access and locks the app
  Future<void> resetAccess();
}
```

### 4.3 Pose Detection Contract (`lib/features/pose_detection/application/`)

```dart
abstract class IPoseDetectorService {
  /// Stream of validated completed repetitions
  Stream<int> get repCountStream;

  /// Stream of real-time biomechanical feedback
  Stream<String> get feedbackStream;

  /// Processes camera frame buffer
  Future<void> processFrame(CameraImage frame, CameraDescription camera, DeviceOrientation orientation);

  /// Resets counter and state machine
  void reset();

  /// Disposes resources
  Future<void> dispose();
}
```

---

## 5. Invariant Integrity Rules

1. **Anti-Duplication**: A completed workout session cannot grant access twice or multiply XP rewards for the same `sessionId`.
2. **Calendar Time**: Unlock time is strictly calendar time (`unlock_until` timestamp), not active foreground usage time.
3. **Fail-Open Security**: If native communication fails, the app must not trap the user or freeze the OS navigation.
