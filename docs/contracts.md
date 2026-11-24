# LevelUp — Interface Contracts & APIs

**Document:** Platform Bridge & Inter-Module Contracts  
**Status:** Canonical Reference for Developer 1 (Core) and Developer 2 (UI)  
**Source of Truth:** [README.md](../README.md) · [Module 01 Specification](module-01-native-bridge.md) · [Module 02 Specification](module-02-focus-engine.md) · [Module 03 Specification](module-03-challenge-engine.md) · [Module 04 Specification](module-04-pose-engine.md) · [Module 05 Specification](module-05-workout-session-manager.md) · [Module 06 Specification](module-06-access-engine.md) · [Module 07 Specification](module-07-local-database.md) · [Core Integration Phase A](core-integration-phase-a.md)

---

## 1. Overview & Separation of Concerns

Communication between the Flutter UI layer and the Android Kotlin operating system layer is strictly defined. 
- **Developer 2 (UI)** interacts with the high-level Dart abstraction layer (`INativeBridge`, `IFocusService`).
- **Developer 1 (Core)** maintains the Kotlin platform implementation in `MainActivity.kt`, `LevelUpAccessibilityService.kt`, and the Dart Native Bridge in `lib/services/native_bridge.dart`.

To prevent regressions, **existing native contracts remain immutable** during UI enhancements.

---

## 2. Active Platform Channel API

### 2.1 Channel Definition
```dart
const MethodChannel native = MethodChannel('levelup_test/control');
```
- **Channel Name:** `levelup_test/control` (defined in `ChannelConstants.controlChannel`)
- **Native Implementation:** `android/app/src/main/kotlin/com/levelup/levelup_test/MainActivity.kt`
- **Native Storage:** Android `SharedPreferences` titled `"levelup_gate"` (`Context.MODE_PRIVATE`)
- **Dart Bridge Wrapper:** `NativeBridge` (`lib/services/native_bridge.dart`) implementing `INativeBridge`

### 2.2 Active Methods Specification

| Method Name | Direction | Arguments (Dart Map) | Kotlin Return Type | Dart Bridge Return Type | Status & Purpose |
|---|---|---|---|---|---|
| `getState` | Flutter $\rightarrow$ Android | `null` | `Map<String, Object>` | `Future<NativeFocusStatus>` | **Active**: Reads current gate state from SharedPreferences and verifies Accessibility status. |
| `setTarget` | Flutter $\rightarrow$ Android | `{'target': String}` | `Boolean` (`true`) | `Future<bool>` | **Active**: Sets target package, clears access, and triggers service re-evaluation. |
| `setEnabled` | Flutter $\rightarrow$ Android | `{'enabled': Boolean}` | `Boolean` (`true`) | `Future<bool>` | **Active**: Toggles voluntary restriction on/off. |
| `openAccessibilitySettings` | Flutter $\rightarrow$ Android | `null` | `Boolean` (`true`) | `Future<bool>` | **Active**: Dispatches system intent `Settings.ACTION_ACCESSIBILITY_SETTINGS`. |
| `consumeChallengeRequest` | Flutter $\rightarrow$ Android | `null` | `Boolean` | `Future<bool>` | **Active**: Atomic check-and-clear for pending challenge triggered from native gate overlay. |
| `grantAccess` | Flutter $\rightarrow$ Android | `{'minutes': Int}` | `Long` (epoch ms) | `Future<DateTime>` | **Active**: Writes unlock expiration (`now + minutes`), closes gate, launches target app. |
| `resetAccess` | Flutter $\rightarrow$ Android | `null` | `Boolean` (`true`) | `Future<bool>` | **Active**: Clears unlock expiration, re-arms gate restriction. |

---

### 2.3 Detailed Method Schemas

#### `getState`
- **Low-Level Platform Call:**
  ```dart
  final Map<dynamic, dynamic>? state = await native.invokeMapMethod('getState');
  ```
- **Typed Bridge Call:**
  ```dart
  final NativeFocusStatus status = await nativeBridge.getState();
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
- **Error Behavior:** Missing or malformed fields are safely resolved with fallbacks by `NativeFocusStatus.fromMap`. Throws `NativeBridgeException` if the platform channel fails.

#### `setTarget`
- **Low-Level Platform Call:**
  ```dart
  await native.invokeMethod('setTarget', {'target': 'com.google.android.youtube'});
  ```
- **Typed Bridge Call:**
  ```dart
  await nativeBridge.setTarget(ChannelConstants.targetYouTube);
  ```
- **Supported Targets (Strict Set):**
  - `com.google.android.youtube` (`ChannelConstants.targetYouTube`)
  - `com.instagram.android` (`ChannelConstants.targetInstagram`)
  - `com.zhiliaoapp.musically` (`ChannelConstants.targetTikTok`)
- **Error Behavior:** If `target` is outside the supported set, Kotlin returns `PlatformException(code: "TARGET", message: "Unsupported test package")`. The bridge translates this into `UnsupportedTargetPackageException`.

#### `setEnabled`
- **Typed Bridge Call:**
  ```dart
  await nativeBridge.setEnabled(true);
  ```
- **Kotlin Behavior:** Saves `"enabled"` boolean in `SharedPreferences` and calls `LevelUpAccessibilityService.instance?.reevaluate()`.

#### `openAccessibilitySettings`
- **Typed Bridge Call:**
  ```dart
  await nativeBridge.openAccessibilitySettings();
  ```
- **Kotlin Behavior:** Launches `Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)`.

#### `consumeChallengeRequest`
- **Typed Bridge Call:**
  ```dart
  final bool challengeRequested = await nativeBridge.consumeChallengeRequest();
  ```
- **Kotlin Behavior:** Reads `"open_challenge"` flag and resets it to `false`. Used on app resume to determine if the user pressed "Start challenge" on the native overlay.

#### `grantAccess`
- **Typed Bridge Call:**
  ```dart
  final DateTime unlockUntil = await nativeBridge.grantAccess(minutes: 5);
  ```
- **Kotlin Behavior:**
  - `minutes` coerced into range `1..15` (defaults to 5).
  - Calculates: `System.currentTimeMillis() + minutes * 60_000L`.
  - Saves `unlock_until` to `SharedPreferences`.
  - Re-evaluates accessibility gate (releasing overlay if active).
  - Dispatches `packageManager.getLaunchIntentForPackage(target)` with `FLAG_ACTIVITY_NEW_TASK`.
- **Return Value:** Parsed into a Dart `DateTime` object.

#### `resetAccess`
- **Typed Bridge Call:**
  ```dart
  await nativeBridge.resetAccess();
  ```
- **Kotlin Behavior:** Sets `unlock_until` = `0L`, re-evaluates gate.

---

## 3. Supported vs. Unsupported Capabilities

| Capability | Current Status | Notes / Location |
|---|---|---|
| Query gate status (`target`, `enabled`, `unlockUntil`, `serviceEnabled`) | **Supported** | Kotlin `MainActivity.kt` & Dart `NativeBridge.getState()` |
| Target app restriction (YouTube, Instagram, TikTok) | **Supported** | Hardcoded package filter in `MainActivity.kt` |
| Voluntary restriction toggle | **Supported** | `setEnabled` |
| Accessibility settings intent launch | **Supported** | `openAccessibilitySettings` |
| Detect "Start Challenge" tap from overlay | **Supported** | `consumeChallengeRequest` |
| Temporary unlock (1..15 min) + Target launch | **Supported** | `grantAccess` |
| Immediate access reset | **Supported** | `resetAccess` |
| Arbitrary third-party app selection | **Unsupported (Proposed)** | Requires Android `QUERY_ALL_PACKAGES` or dynamic package manager queries |
| Real-time EventChannel events from service | **Unsupported (Proposed)** | Currently queried on lifecycle resume or polled |
| Camera permission query via MethodChannel | **Unsupported (Handled in Dart)** | Handled directly by Flutter `camera` plugin |
| System Alert Window permission check | **Not Required** | App uses `TYPE_ACCESSIBILITY_OVERLAY` via AccessibilityService |
| Workout history / streak persistence in native | **Unsupported (Proposed)** | Managed in Flutter local data layer |
| Background service heartbeat / watchdog | **Unsupported (Proposed)** | Best-effort Android AccessibilityService lifecycle |

---

## 4. Error Hierarchy & Exception Handling

All platform exceptions thrown across `levelup_test/control` are mapped into typed exceptions in `lib/core/errors/native_bridge_exception.dart`:

```text
NativeBridgeException (base)
 ├── UnsupportedTargetPackageException (code: 'TARGET')
 ├── NativeBridgeNotImplementedException (code: 'NOT_IMPLEMENTED', wraps MissingPluginException)
 └── MalformedNativeResponseException (code: 'MALFORMED_RESPONSE')
```

### Callers State Discrimination Matrix

Callers can distinguish between all core states without ambiguity:
1. **Focus enabled by user**: `status.isGateEnabled == true`
2. **Accessibility permission granted**: `status.isAccessibilityGranted == true` (or `status.isServiceEnabled`)
3. **Native bridge available**: `await nativeBridge.isAvailable() == true`
4. **Temporary access active**: `status.isAccessActive == true` (`unlockUntil > DateTime.now()`)

---

## 5. Usage Example for Developer 2 (UI)

```dart
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/native_bridge_exception.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/services/native_bridge.dart';

class FocusViewModel {
  final INativeBridge _bridge;

  FocusViewModel({INativeBridge? bridge}) : _bridge = bridge ?? const NativeBridge();

  Future<void> loadState() async {
    try {
      final NativeFocusStatus status = await _bridge.getState();
      print('Selected app: ${status.targetPackage}');
      print('Gate enabled: ${status.isGateEnabled}');
      print('Accessibility granted: ${status.isAccessibilityGranted}');
      print('Access active: ${status.isAccessActive} (remaining: ${status.remainingAccess})');
    } on NativeBridgeException catch (e) {
      print('Bridge error: $e');
    }
  }

  Future<void> toggleRestriction(bool enable) async {
    await _bridge.setEnabled(enable);
  }

  Future<void> selectTargetApp(String packageId) async {
    try {
      await _bridge.setTarget(packageId);
    } on UnsupportedTargetPackageException catch (e) {
      print('Package not supported: ${e.targetPackage}');
    }
  }

  Future<void> onChallengeCompleted() async {
    final DateTime accessUntil = await _bridge.grantAccess(minutes: 5);
    print('Access granted until: $accessUntil');
  }
}
```

---

## 6. Invariant Integrity Rules

1. **Anti-Duplication**: A completed workout session cannot grant access twice or multiply rewards for the same `sessionId`.
2. **Calendar Time**: Unlock time is strictly calendar time (`unlock_until` timestamp), not active foreground usage time.
3. **Fail-Open Security**: If native communication fails, the app must not trap the user or freeze the OS navigation.
4. **Channel Name Immutability**: The channel name `levelup_test/control` and method identifiers must not be modified.

---

## 7. Module 08 — Settings & Permissions Engine Contract

Module 08 (`ISettingsService`) provides reactive application configuration and OS permission coordination:

### Core Contract
- **Contract Interface:** `ISettingsService` (`lib/features/settings/application/settings_service.dart`)
- **State Model:** `SettingsState` (`settings`, `permissions`, `activeTargetPackage`, `isFocusEnabled`)
- **Persistence:** `SqliteSettingsRepository` storing to `app_settings` table in `LevelUpDatabase`
- **Permissions Monitored:**
  - Android Accessibility Service (`isAccessibilityGranted` via `INativeBridge.getState()`)
  - Device Camera (`CameraPermissionStatus` via `ICameraPermissionChecker` / `camera` plugin)
- **Lifecycle Integration:** Dispatches `refresh()` on app resume (`AppLifecycleState.resumed`) to detect OS settings changes or external revocations.
- **Authority Preservation:** SettingsService never issues native access grants or bypasses `FocusService` authority. Target switching delegates to `focusService.selectTargetApp()`.

