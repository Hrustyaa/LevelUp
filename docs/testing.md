# LevelUp — Quality Assurance & Testing Protocol

**Application:** LevelUp (Android SportTech)  
**Primary Device:** Google Pixel 7 Pro (Android 16 / API 36)  
**Secondary Device:** Samsung Galaxy S20 (Android 13 / One UI)  
**Source of Truth:** [README.md](../README.md)

---

## 1. Current Verified Features & Baseline (As of Nov 20, 2026)

Verified on **Google Pixel 7 Pro**:
- [x] Flutter SDK and Android SDK compile and execute on physical hardware.
- [x] Front camera initialization and stream acquisition using `NV21` format.
- [x] Google ML Kit Pose Detection stream pipeline operating on-device.
- [x] Squat state machine detects knee flexion ($<125^\circ$) and extension ($>155^\circ$) with 2-frame debouncing.
- [x] Blocker v3 latches overlay across targeted packages (`YouTube`, `Instagram`, `TikTok`).
- [x] Blocker v3 `GLOBAL_ACTION_HOME` mitigation pauses ordinary background audio in tested flows.
- [x] 5-minute unlock grant writes to `SharedPreferences` and launches target app.
- [x] Safe exit options available on gate overlay ("Return home", "Turn off restriction").

---

## 2. Pending Tests & Known Limitations

- [ ] **Cross-Device Matrix**: Samsung Galaxy S20 protocol pending completion.
- [ ] **10-Cycle Endurance Test**: Execute 10 consecutive loops of *Gate $\rightarrow$ Challenge $\rightarrow$ Access $\rightarrow$ Expiration $\rightarrow$ Re-arm* without memory leaks or crash.
- [ ] **Device Reboot Recovery**: Validate behavior when phone restarts while gate is enabled.
- [ ] **In-Foreground Expiration**: Confirm that when 5 minutes expire while the user is actively viewing YouTube, the gate immediately re-latches.
- [ ] **Revocation Resilience**: Verify graceful UI behavior when Accessibility or Camera permissions are revoked via system settings during runtime.
- [ ] **Anti-Farming / Replay Prevention**: Confirm that re-executing or spoofing an already completed workout session does not issue repeated unlock grants or duplicate XP.

---

## 3. Camera & Pose Detection Regression Protocol

| Test ID | Scenario | Steps | Expected Result | Pass/Fail Criteria |
|---|---|---|---|---|
| **CAM-01** | Camera Stream Init | Launch Challenge screen. | Camera preview displays front camera feed within 2 seconds; no black frames. | Preview renders cleanly. |
| **CAM-02** | Backgrounding Lifecycle | App minimized (`AppLifecycleState.paused`) while camera active. | Camera stream stops; `CameraController.dispose()` executed cleanly; camera released. | No camera resource lock on OS. |
| **CAM-03** | Foreground Resumption | Restore app from background. | Camera reconnects; stream resumes without restart crash. | Normal stream restored. |
| **CAM-04** | Sub-Threshold Flexion | User bends knees slightly ($>135^\circ$). | Knee angle calculated; state remains `up`; repetition count does not increment. | Rep counter unchanged. |
| **CAM-05** | Full Squat Cycle | Deep squat ($<120^\circ$) held for $\ge 2$ frames, then return to upright ($>155^\circ$) for $\ge 2$ frames. | State transitions `up` $\rightarrow$ `down` $\rightarrow$ `up`; rep counter increments exactly by 1. | Accurate count (+1). |
| **CAM-06** | Out of Frame Handling | User walks out of frame during active challenge. | UI displays "Человек не найден — отойди дальше от телефона"; no crash or spurious counts. | Clean guidance prompt. |
| **CAM-07** | Target Completion | Rep counter reaches 5/5. | Challenge finishes; camera released; `grantAccess` invoked; target app launched. | Seamless transition. |

---

## 4. Android Blocker v3 Regression Protocol

| Test ID | Scenario | Steps | Expected Result | Pass/Fail Criteria |
|---|---|---|---|---|
| **BLK-01** | Gate Latched on Target | With restriction ON, launch YouTube. | LevelUp overlay attaches instantly (`TYPE_ACCESSIBILITY_OVERLAY`); `GLOBAL_ACTION_HOME` sent. | Target app hidden; overlay visible. |
| **BLK-02** | No Overlay Flashing | Keep overlay visible on screen for 10 seconds. | Overlay does not blink, tear, or flicker on focus changes. | Rock-solid visual latch. |
| **BLK-03** | Audio Mitigation | Launch YouTube playing video while gate triggers. | Native app sent to HOME; ordinary audio pauses automatically. | No audible video background sound. |
| **BLK-04** | Overlay "Start Challenge" | Tap "Start challenge" on overlay. | `open_challenge` flag saved; LevelUp `MainActivity` brought to foreground; Camera opens. | Challenge opens immediately. |
| **BLK-05** | Overlay "Return Home" | Tap "Return home (skip)" on overlay. | Overlay dismisses; device navigates to Android home screen; target app remains gated. | Clean exit to home. |
| **BLK-06** | Voluntary Disable | Tap "Turn off restriction" on overlay. | Gate disables; `enabled` flag set to `false`; overlay closes. | App restriction removed. |
| **BLK-07** | Lock Screen Resilience | Lock device (`KeyguardManager.isKeyguardLocked`). | Gate overlay clears immediately (`clearGate('keyguard')`). | No overlay over lock screen. |
| **BLK-08** | Non-Target App Launch | Launch Phone, Settings, or Calculator while gate enabled. | Non-target apps open normally without any blocker interference. | Zero interference. |

---

## 5. Device Compatibility Checklist

| Verification Category | Google Pixel 7 Pro (Android 16) | Samsung Galaxy S20 (One UI / Android 13) |
|---|---|---|
| **Accessibility Registration** | Tested & functional | Pending hardware test |
| **Camera NV21 Support** | Confirmed supported | Verify YUV/NV21 stream format |
| **Sensor Orientation** | 270° front sensor compensation | Verify 90° vs 270° mapping |
| **Aggressive Battery Killer** | Stock Android (Doze standard) | Disable "Put unused apps to sleep" |
| **Overlay Window Permission** | Granted via Accessibility | Check if system overlay permission needed |
| **Navigation Grace Period** | 1800ms uptime debounce verified | Verify launcher transition duration |
