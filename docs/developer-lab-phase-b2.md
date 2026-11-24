# LevelUp Developer Lab — Phase B2: Inspection, Diagnostics & Test Center

**Application:** LevelUp (Android SportTech)  
**Branch:** `feature/core`  
**Entry Point:** `lib/main_dev.dart`  
**Status:** Validated (296/296 unit/widget tests passing, zero analyzer issues, debug APK compiled)

---

## 1. Executive Summary

Developer Lab Phase B2 extends the original 3-screen developer environment (Phase B1) into a 6-screen diagnostic inspection and automated verification center. It enables complete white-box observation, state simulation, and SQLite transaction auditing across all seven backend modules without altering the production UI (`feature/ui`) or modifying release entry points (`lib/main.dart`).

---

## 2. Six-Screen Architecture

| Screen | File | Primary Responsibility |
|---|---|---|
| **Screen 1: System Hub** | `lib/features/developer_lab/screens/system_hub_screen.dart` | Live health monitoring of all 7 backend modules, single-tap mode switching (Real Device vs QA Simulation), native accessibility permission status, active gate state, and navigation router to Screens 2–6. |
| **Screen 2: Preflight & Focus** | `lib/features/developer_lab/screens/preflight_focus_screen.dart` | Inspection and manual toggling of Focus restrictions, target package selection (`YouTube`, `Instagram`, `TikTok`), accessibility service status, and camera permission preflight checks. |
| **Screen 3: Live Challenge** | `lib/features/developer_lab/screens/live_challenge_screen.dart` | Live front-camera pose detection feed with ML Kit, real-time skeleton overlay, squat angle and repetition state tracking, manual frame injection for simulation, and direct transition to Workout Result. |
| **Screen 4: Workout Result** | `lib/features/developer_lab/screens/workout_result_screen.dart` | Detailed inspection of completed or failed workouts. Strictly distinguishes active live access from historically confirmed (expired) access; displays journal attempt status, earned XP, exercise telemetry, and raw JSON export. |
| **Screen 5: History & SQLite Database** | `lib/features/developer_lab/screens/history_database_screen.dart` | Direct inspection of SQLite database tables (`workouts` and `access_attempts`). Provides real-time search across session IDs/packages, tabbed navigation, context filtering (`unlockChallenge` vs `freeWorkout`), and cross-table highlight navigation. |
| **Screen 6: Test Center** | `lib/features/developer_lab/screens/test_center_screen.dart` | Interactive automated test execution dashboard. Runs module-specific unit scenarios, full coordinator workflows in isolated memory SQLite databases, safe read-only device probes, and manages manual device checklists. |

---

## 3. Real Device vs Simulation Mode Isolation

To guarantee that diagnostic tests and developer explorations never contaminate real user data or accidentally issue unauthorized Android native grants, Developer Lab enforces strict separation:

```
                      ┌───────────────────────────────────────────────┐
                      │              DevLabScope / Controller         │
                      └───────────────────────┬───────────────────────┘
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
         [DevExecutionMode.realDevice]                  [DevExecutionMode.simulation]
         • NativeBridge (MethodChannel)                 • SimulationBridge (In-Memory IPC)
         • LevelUpDatabase (levelup.db)                 • LevelUpDatabase (levelup_simulation.db)
         • Real camera & system accessibility           • Simulated pose feed & mock permissions
         • Authoritative Android gate control           • Zero IPC / Zero native side effects
```

- **Real Device Mode**: Uses `const NativeBridge()` communicating over `levelup_test/control` and persists to `levelup.db`.
- **QA Simulation Mode**: Uses `SimulationBridge()` with mock states and isolates persistence to `levelup_simulation.db`. Real Android gate grants are never invoked.
- **Isolated Test Scenarios**: In-app test runners dynamically spawn temporary SQLite files (e.g., `test_disposable_*.db`) or use in-memory SQLite factories via `sqflite_common_ffi`, guaranteeing complete test isolation.

---

## 4. Test Center Diagnostic Suite

The Test Center runs scenarios categorized by execution type:

1. **Automated Test Reference (`automatedTestRef`)**: Validates headless unit invariants verified by the CI test suite.
2. **Isolated In-App Scenario (`isolatedScenario`)**: Runs dynamic algorithms (e.g. squat state transitions, coordinator state transitions, SQLite CRUD) using isolated mock bridges and disposable databases.
3. **Real Device Probe (`realDeviceProbe`)**: Non-destructive, read-only checks querying live native platform availability and gate status. Never executes write actions or grants access.
4. **Manual Device Checklist (`manualChecklist`)**: Physical device requirements (e.g., camera framing, physical overlay latency, audio attenuation). **Crucial invariant:** Manual checklist items have `action: null` and cannot be automatically passed by software batch runners; they require explicit human verification on the hardware.

---

## 5. Test Stabilization & Lifecycle Guarantees

During Phase B2 stabilization, asynchronous widget test stability was hardened against fake-async clock lockups:

1. **Lazy Periodic Timers**: Countdown tickers in `WorkoutResultScreen` and `SystemHubScreen` are initialized only when an active unlock window exists in the future, and auto-cancel immediately upon expiration or widget disposal.
2. **TextEditingController & TabController Disposal**: Controllers are created persistently in widget states and cleanly disposed in `dispose()`.
3. **DidChangeDependencies Guards**: State initialization in `TestCenterScreen` is protected by `_isRunnerInitialized` flags to prevent duplicate recreation or `LateInitializationError` during inherited widget notifications.
4. **SQLite FFI Isolation**: Unit and widget tests use `sqfliteFfiInit()` with `databaseFactory = databaseFactoryFfi`, pre-opening databases prior to widget pump cycles.

---

## 6. Verification & Build Commands

- **Run Flutter Analyzer:**
  ```bash
  flutter analyze
  ```
- **Execute Full Test Suite (296 tests):**
  ```bash
  flutter test
  ```
- **Build Developer Lab Debug APK (Pixel / Android Device):**
  ```bash
  flutter build apk --debug -t lib/main_dev.dart
  ```
- **Verify Production Prototype Build:**
  ```bash
  flutter build apk --debug -t lib/main.dart
  ```
- **Launch on Connected Physical Device:**
  ```bash
  flutter run -t lib/main_dev.dart
  ```
