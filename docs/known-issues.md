# LevelUp — Known Issues & Physical Hardware Diagnostic Log

**Application:** LevelUp (Android SportTech)  
**Branch:** `feature/core`  
**Last Updated:** November 24, 2026

This document records observed edge cases, OEM-specific limitations, and open hardware validation items discovered during developer testing on Android devices (Google Pixel 7 Pro and Samsung Galaxy S20).

---

## 1. Physical Device & Native Blocker Observations

### 1.1 Android Multitasking / Recent Apps Overlay Latching
- **Symptom:** When switching rapidly between a restricted app (e.g., YouTube) and other foreground applications via Android Recent Apps / Gesture Navigation without returning to the Home launcher, the full-screen overlay (`TYPE_ACCESSIBILITY_OVERLAY`) can occasionally linger momentarily or flash before the accessibility service recognizes the new foreground package.
- **Root Cause:** Android OS broadcasts window state transitions (`AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED`) asynchronously. System UI / Launcher transition events (event type `32` vs `4194304`) have slight OEM-dependent delivery latencies.
- **Current State:** Blocker v3 mitigates this by validating the foreground package and releasing the gate when non-target apps are detected, but physical device testing shows edge-case timing jitter during rapid 3-finger multitasking gestures.
- **Status:** **Open / Requires hardware regression profiling.**

### 1.2 Access Grant Expiration While Target Is In Foreground
- **Symptom:** If the 300-second access period expires while the user is actively inside the target application (e.g. uninterrupted YouTube playback), native re-blocking requires an accessibility event or a timer-based watchdog in the native service.
- **Current State:** The native service periodically checks `isAccessActive()`, but if the target app does not trigger new window state events, re-latching relies on the native watchdog handler.
- **Status:** **Open / Under device observation.**

### 1.3 Target Package Latch After Native Expiry
- **Symptom:** On rare occasions following native access expiration, tapping "Start Challenge" from a re-latched overlay can encounter a brief race where the previous session's native unlock flag has not completely flushed from SharedPreferences before the new session begins.
- **Mitigation:** The Coordinator Phase A refactor introduced strict single-consumption via `consumeChallengeRequest()`, preventing duplicate starts. However, physical device verification of multiple sequential workout loops (Endurance Testing) remains pending.
- **Status:** **Mitigated in software / Pending 10-cycle physical endurance confirmation.**

---

## 2. Camera & Pose Detection Hardware Variance

### 2.1 Front Camera Stream Orientation on Select OEMs
- **Symptom:** On certain Samsung devices running Android 13/14, the front-camera image buffer orientation metadata may report varying rotation degrees (e.g. 270° vs 90°), affecting the landmark coordinate frame if not normalized by ML Kit.
- **Current State:** Google ML Kit's `InputImage.fromBytes` handles rotation metadata automatically when passed `InputImageRotation.rotation270deg` / `rotation90deg`. Tested and verified on Google Pixel 7 Pro; secondary matrix test on Samsung Galaxy S20 is pending.
- **Status:** **Pending Samsung device matrix execution.**

### 2.2 Low-Light Landmark Confidence
- **Symptom:** Under poor lighting conditions ($< 50 \text{ lux}$), ML Kit pose detection landmark confidence for knee and hip landmarks drops below $0.5$, causing the squat angle calculator to reject frames.
- **Current State:** The squat counter correctly flags missing landmarks with human-readable UI guidance ("Person not detected" / "Step back"), but does not attempt to guess joint positions.
- **Status:** **Working as designed (safety invariant).**

---

## 3. Platform & Background Execution Policies

### 3.1 Aggressive Background App Killing (Battery Optimization)
- **Symptom:** If the LevelUp process is killed in the background by OEM aggressive power management (e.g. Samsung One UI Sleeping Apps), the Dart VM terminates. The native `LevelUpAccessibilityService` remains alive in the Android system process, but launching the workout challenge requires bringing the Flutter activity back into memory.
- **Current State:** `MainActivity` handles cold-start recovery by reading `open_challenge` from `SharedPreferences` in `onResume()`.
- **Status:** **Operational, but OEM background battery exemption guidelines should be recommended in future onboarding.**

---

## 4. Pending Verification Protocols

The following physical validation protocols from `docs/testing.md` remain open for execution on physical hardware:

- [ ] **10-Cycle Endurance Test:** Execute 10 consecutive loops of *Gate $\rightarrow$ Challenge $\rightarrow$ Access $\rightarrow$ Expiration $\rightarrow$ Re-arm* without memory leaks or crash.
- [ ] **Device Reboot Recovery:** Validate gate re-arming behavior immediately following a full device cold restart.
- [ ] **Secondary Device Matrix:** Complete full 6-screen audit on Samsung Galaxy S20 (One UI).
