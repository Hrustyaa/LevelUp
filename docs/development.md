# LevelUp — Development Guide

**Target Environment:** macOS (MacBook Pro/Air) & Android Physical Devices  
**Primary Test Target:** Google Pixel (Pixel 7 Pro, Android 16)  
**Secondary Test Target:** Samsung Galaxy S20  
**Source of Truth:** [README.md](../README.md)

---

## 1. Environment & Prerequisites

### 1.1 Toolchain Versions
- **Host OS:** macOS Sonoma / Sequoia (Apple Silicon or Intel).
- **Flutter SDK:** Flutter 3.27.0+ (Dart SDK `3.11.0` or higher as specified in `pubspec.yaml`).
- **JDK:** OpenJDK 17 (Zulu or Temurin) or Android Studio bundled JDK 17.
- **Android SDK:**
  - `compileSdk = 36`
  - `targetSdk = 36`
  - `minSdk = 24` (Android 7.0+)
  - Android SDK Build-Tools 36
  - Android Platform-Tools (latest `adb`)

---

## 2. MacBook Setup Step-by-Step

### 2.1 macOS System Setup
1. Install Command Line Tools:
   ```bash
   xcode-select --install
   ```
2. Install [Homebrew](https://brew.sh) (if not already installed).
3. If on Apple Silicon (M1/M2/M3/M4), ensure Rosetta 2 is available for legacy build tools:
   ```bash
   softwareupdate --install-rosetta --agree-to-license
   ```

### 2.2 Flutter SDK Installation
1. Download Flutter SDK (stable channel) or use Homebrew:
   ```bash
   brew install --cask flutter
   ```
2. Add Flutter to your shell profile (`~/.zshrc`):
   ```bash
   export PATH="$PATH:$HOME/development/flutter/bin"
   ```
3. Reload profile and verify:
   ```bash
   source ~/.zshrc
   flutter --version
   ```

### 2.3 Android Studio & SDK Setup
1. Install **Android Studio** via Homebrew or official installer:
   ```bash
   brew install --cask android-studio
   ```
2. Open Android Studio $\rightarrow$ **Settings** (or **Preferences**) $\rightarrow$ **Languages & Frameworks** $\rightarrow$ **Android SDK**:
   - In **SDK Platforms**: Check **Android 16 ("Baklava" / API 36)**.
   - In **SDK Tools**:
     - Android SDK Build-Tools 36
     - Android SDK Command-line Tools (latest)
     - Android SDK Platform-Tools
3. Set Android environment variables in `~/.zshrc`:
   ```bash
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   export PATH="$PATH:$ANDROID_HOME/platform-tools"
   export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
   ```
4. Accept Android SDK licenses:
   ```bash
   flutter doctor --android-licenses
   ```
5. Confirm complete health check:
   ```bash
   flutter doctor -v
   ```

---

## 3. Physical Android Device Deployment

LevelUp relies on hardware camera streaming (NV21 format) and Android OS `AccessibilityService`. **Testing must be conducted on physical hardware.**

### 3.1 Device Preparation (Google Pixel / Samsung)
1. Open **Settings** $\rightarrow$ **About phone**.
2. Tap **Build number** 7 times until Developer mode is enabled.
3. Open **Settings** $\rightarrow$ **System** $\rightarrow$ **Developer options**:
   - Turn **ON** **USB debugging**.
   - Optional: Enable **Stay awake while charging**.
4. Connect phone to MacBook with a high-quality USB-C data cable.
5. On the phone, accept the **Allow USB debugging?** prompt with your MacBook's RSA key.
6. Verify device discovery in terminal:
   ```bash
   adb devices
   flutter devices
   ```

### 3.2 Required Device Permissions
After first installation:
1. **Camera Permission**: Prompted on first launch of the challenge screen.
2. **Accessibility Service**:
   - Navigate to **Settings** $\rightarrow$ **Accessibility**.
   - Under **Downloaded apps** (or **Installed services**), find **LevelUp Test — voluntary app gate**.
   - Toggle to **ON** and confirm the Android system disclosure.
3. **Restricted Settings Notice (Android 13+)**:
   - If the toggle is grayed out: open **Settings** $\rightarrow$ **Apps** $\rightarrow$ **LevelUp Test** $\rightarrow$ tap the top-right three dots $\rightarrow$ **Allow restricted settings**. Then re-enable Accessibility.

### 3.3 Running and Debugging
Run the app targeting the connected device:
```bash
flutter pub get
flutter run -d <DEVICE_ID>
```

To monitor native AccessibilityService and gate lifecycle logs:
```bash
adb logcat -s LevelUpGate:V Flutter:V
```

---

## 4. Git Collaboration Workflow

To ensure seamless collaboration between Developer 1 (Core) and Developer 2 (UI):

### 4.1 Branch Model
```text
           [main] (Production & demo stable; always deployable)
             ^
             | PR / Merge after verification
     +-------+-------+
     |               |
[feature/ui]    [feature/core]
Developer 2     Developer 1
(Flutter UI,    (Accessibility,
Theme, Tabs)    ML Kit, Bridge)
```

1. **`main`**:
   - Protected branch. Only contains code that compiles, passes `flutter analyze`, and does not crash the core unlock loop.
2. **`feature/ui`**:
   - Owned by Developer 2 (Product & Design Lead).
   - Focus: Flutter screens, 5 tabs, Minimal Dark SportTech theme, typography, user feedback.
3. **`feature/core`**:
   - Owned by Developer 1 (Technical Lead).
   - Focus: Kotlin `LevelUpAccessibilityService`, MethodChannel adapters, ML Kit pose processing, local storage.

### 4.2 Collaboration Rules
- **Never push directly to `main` without testing on hardware.**
- Create atomic pull requests against `main` using the Pull Request template (`.github/pull_request_template.md`).
- Always run before committing:
  ```bash
  flutter pub get
  flutter analyze
  ```

---

## 5. Rules for AI-Assisted Coding (Vibe Coding Guidelines)

1. **Scope Discipline**: Every AI prompt must target **one specific task** (e.g. "Implement the Focus tab view", not "Redesign the entire app").
2. **Preserve Native Core**:
   - **DO NOT MODIFY** `LevelUpAccessibilityService.kt`, `MainActivity.kt`, or `levelup_accessibility_service.xml` during UI tasks.
   - Any change to native contracts requires prior alignment between developers.
3. **No Phantom Code**:
   - Never implement dummy buttons that pretend to perform an action.
   - Always provide real loading, empty, permission-denied, and error states.
4. **Hardware Verification**:
   - Never claim a feature is "verified" unless actually compiled and tested on the physical Pixel or Samsung phone.
5. **No Package Inflation**:
   - Do not add random dependencies or upgrade packages solely for newer versions before the competition pitch.
