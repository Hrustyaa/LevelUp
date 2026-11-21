# Module 02 — Focus Engine

**Component:** Application-Level Focus Engine & Restriction Coordinator  
**Layer:** Feature Application Layer (`lib/features/focus/application/`, `lib/models/`)  
**Status:** Completed & Validated  
**Working Branch:** `feature/core`

---

## 1. Purpose and Architecture

The **Focus Engine** serves as the application-level domain coordinator for voluntary screen-time restrictions in LevelUp. Sitting directly above **Module 01 Native Bridge**, it encapsulates all logic around:
- Enabling and voluntarily disabling the restriction gate.
- Selecting and verifying single target applications.
- Enforcing system permission prerequisites (Android Accessibility Service).
- Evaluating whether restrictions are actively effective or temporarily unlocked.
- Exposing a reactive state stream to Flutter UI screens without polling.

```text
┌────────────────────────────────────────────────────────┐
│  Flutter UI Layer (feature/ui)                         │
│  - FocusScreen / HomeTab                               │
│  - Consumes FocusService (IFocusService)               │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│  Module 02: Focus Engine                               │
│  - FocusService (lib/features/focus/application/)      │
│  - FocusState (lib/models/focus_state.dart)            │
│  - Error hierarchy (lib/core/errors/focus_exceptions)  │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│  Module 01: Native Bridge                              │
│  - INativeBridge / NativeBridge (lib/services/)        │
│  - MethodChannel('levelup_test/control')               │
└──────────────────────────┬─────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────┐
│  Android OS Layer (Kotlin)                             │
│  - MainActivity.kt & LevelUpAccessibilityService.kt   │
│  - SharedPreferences ('levelup_gate')                 │
└────────────────────────────────────────────────────────┘
```

---

## 2. Public FocusService API (`IFocusService`)

The service is defined by the `IFocusService` contract and implemented in `FocusService`:

| Method | Return Type | Description |
|---|---|---|
| `getFocusStatus()` | `Future<FocusState>` | Queries the native layer and returns the verified `FocusState`. |
| `enableFocus()` | `Future<FocusState>` | Voluntarily turns on restrictions. Throws `AccessibilityPermissionRequiredException` if permission is missing. |
| `disableFocus()` | `Future<FocusState>` | Voluntarily turns off restrictions (Safe exit guaranteed). |
| `selectTargetApp(String packageName)` | `Future<FocusState>` | Updates the targeted app. **Side effect: revokes any active temporary unlock.** |
| `getSelectedTarget()` | `Future<String>` | Returns the package name of the active target app. |
| `getPermissionStatus()` | `Future<NativePermissionStatus>` | Returns current accessibility permission status. |
| `openAccessibilitySettings()` | `Future<bool>` | Dispatches the Android system intent to open Accessibility Settings. |
| `refreshState()` | `Future<FocusState>` | Queries the native bridge, updates `currentState`, and emits on `stateStream`. |
| `currentState` | `FocusState?` | Synchronous getter for the latest cached snapshot. |
| `stateStream` | `Stream<FocusState>` | Broadcast stream emitting on state mutations. |
| `dispose()` | `void` | Closes the internal broadcast stream controller. |

---

## 3. Supported App Packages & Single-Target Limitation

### 3.1 Supported Targets
LevelUp Blocker v3 strictly allows only three target packages defined in `ChannelConstants`:
1. **YouTube**: `com.google.android.youtube`
2. **Instagram**: `com.instagram.android`
3. **TikTok**: `com.zhiliaoapp.musically`

Attempting to pass any package outside this set throws an `UnsupportedTargetException`.

### 3.2 Single-Target Limitation
The current Android Kotlin architecture (`MainActivity.kt` and `LevelUpAccessibilityService.kt`) stores and evaluates **one active target package** at a time in `SharedPreferences` (`"target"` key).

> [!IMPORTANT]
> The Focus Engine truthfully supports only **one active target package**. Do not fake multi-app selection in the Dart layer.

### 3.3 Target Switch Side Effect
When `selectTargetApp` is called:
- Kotlin native sets `unlock_until = 0L` in `SharedPreferences`.
- Any active temporary unlock earned through squats is **immediately invalidated**.
- The Focus Engine verifies this native reset and reflects `isAccessActive: false` in the returned `FocusState`.

---

## 4. Permission Handling & Fail-Open Philosophy

- **Permission Requirement**: Android Accessibility Service permission is required before focus restriction can be activated.
- **Fail-Open Policy**: If accessibility permission is not granted, `enableFocus()` throws `AccessibilityPermissionRequiredException` and does not call the native layer.
- **Safe Exit**: `disableFocus()` is **always permitted**, even if accessibility permission was revoked or interrupted, ensuring the user is never trapped in a broken state.
- **No Implicit Activation**: Instantiating `FocusService` performs zero platform calls and does not automatically enable focus.

---

## 5. Focus State Rules (`FocusState`)

The `FocusState` model clearly distinguishes six operational properties:

```text
FocusState
 ├── selectedTarget          (e.g. 'com.google.android.youtube')
 ├── isUserEnabled           (User turned on voluntary restriction)
 ├── isAccessibilityGranted  (Android Accessibility Service granted)
 ├── isBridgeAvailable       (Native MethodChannel reachable)
 ├── unlockUntil             (DateTime expiration of temporary access)
 ├── isAccessActive          (Calendar time check: unlockUntil > DateTime.now())
 ├── remainingAccess         (Remaining Duration of access)
 └── isRestrictionEffective  (Computed property)
```

### 5.1 When is Restriction Effective?
`isRestrictionEffective` is evaluated as:
```dart
bool get isRestrictionEffective =>
    isBridgeAvailable &&
    isUserEnabled &&
    isAccessibilityGranted &&
    !isAccessActive;
```
If temporary access is currently active (user completed squats), the gate is temporarily released, so `isRestrictionEffective` is `false`.

---

## 6. Error Hierarchy

All Focus Engine errors derive from `FocusEngineException`:

```text
FocusEngineException (base)
 ├── AccessibilityPermissionRequiredException (code: 'PERMISSION_REQUIRED')
 ├── NativeBridgeUnavailableException (code: 'BRIDGE_UNAVAILABLE')
 ├── UnsupportedTargetException (code: 'UNSUPPORTED_TARGET')
 └── FocusStateSyncException (code: 'SYNC_FAILED')
```

---

## 7. How the UI Developer Should Connect the Focus Screen

Developer 2 can connect the UI using either reactive `StreamBuilder` or standard `AsyncNotifier` / `ChangeNotifier` patterns:

### Example: StreamBuilder Integration in FocusScreen
```dart
import 'package:flutter/material.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/features/focus/application/focus_service.dart';

class FocusScreen extends StatefulWidget {
  final IFocusService focusService;

  const FocusScreen({super.key, required this.focusService});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  @override
  void initState() {
    super.initState();
    // Eagerly refresh state when screen loads
    widget.focusService.refreshState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FocusState>(
      stream: widget.focusService.stateStream,
      initialData: widget.focusService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Target Application Dropdown
            DropdownButton<String>(
              value: state.selectedTarget,
              items: ChannelConstants.allowedTargets.map((pkg) {
                return DropdownMenuItem(
                  value: pkg,
                  child: Text(ChannelConstants.targetDisplayNames[pkg] ?? pkg),
                );
              }).toList(),
              onChanged: (pkg) {
                if (pkg != null) widget.focusService.selectTargetApp(pkg);
              },
            ),

            // 2. Permission Indicator & Button
            if (!state.isAccessibilityGranted) ...[
              const Text('Accessibility permission required!', style: TextStyle(color: Colors.orange)),
              ElevatedButton(
                onPressed: widget.focusService.openAccessibilitySettings,
                child: const Text('Open Settings'),
              ),
            ],

            // 3. Voluntary Toggle
            SwitchListTile(
              title: const Text('Voluntary Focus Restriction'),
              value: state.isUserEnabled,
              onChanged: (enabled) async {
                try {
                  if (enabled) {
                    await widget.focusService.enableFocus();
                  } else {
                    await widget.focusService.disableFocus();
                  }
                } on AccessibilityPermissionRequiredException {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enable Accessibility Service first.')),
                  );
                }
              },
            ),

            // 4. Operational Status Indicator
            Text(state.isRestrictionEffective ? 'Blocking Active' : 'Idle / Unlocked'),
          ],
        );
      },
    );
  }
}
```

---

## 8. Future Extension: Multiple Selected Apps

In a future iteration (Module 04 / Phase 1 Stable Core), multi-app selection will require:
1. Updating `MainActivity.kt` and `LevelUpAccessibilityService.kt` to store a `Set<String>` in SharedPreferences rather than a single string.
2. Extending `ChannelConstants` and `INativeBridge` to pass `List<String> targets`.
3. Updating `FocusService.selectTargetApps(Set<String> packages)`.
4. Updating AndroidManifest.xml `<queries>` to support additional target applications as requested by the user.
