## Summary
<!-- Provide a concise 2-3 sentence overview of what this pull request introduces or fixes. -->

## Branch & Subsystem
- **Target Branch:** `main`
- **Source Branch:** 
- **Developer Role:** [ ] Developer 1 (Core / Android / ML) | [ ] Developer 2 (UI / Flutter / Design)

## Changed Modules
<!-- Check all applicable areas modified in this PR -->
- [ ] `lib/app/` (Theme, Global Navigation)
- [ ] `lib/features/home/` (Dashboard, Status Overview)
- [ ] `lib/features/focus/` (Target Selection, Blocker UI)
- [ ] `lib/features/challenge/` (Camera View, Squat Workout UI)
- [ ] `lib/features/pose_detection/` (ML Kit Stream, Squat State Machine)
- [ ] `lib/features/progress/` (Telemetry, Session Persistence, XP)
- [ ] `lib/features/settings/` (Permissions, Duration, Debug)
- [ ] `lib/services/` or `lib/models/` (Bridge Abstractions, Entities)
- [ ] `android/` (Native Kotlin, Blocker v3, Manifest, A11y Config)
- [ ] `docs/` (Architecture, Contracts, Testing, Roadmap)

## Testing Completed
<!-- Describe the specific automated and manual tests executed -->
- [ ] `flutter pub get` executed cleanly
- [ ] `flutter analyze` completed with 0 errors / 0 warnings
- [ ] Manual full loop tested: Target Trigger $\rightarrow$ Overlay Latched $\rightarrow$ 5 Squats $\rightarrow$ Unlock $\rightarrow$ App Accessible
- [ ] Emergency safe exits tested (Skip to home, voluntary disable)

## Devices Tested
<!-- Check hardware tested. Mark N/A for pure documentation changes. -->
- [ ] Google Pixel 7 Pro (Physical Device — Android 16)
- [ ] Samsung Galaxy S20 (Physical Device — Android 13 / One UI)
- [ ] Android Emulator
- [ ] Not Applicable (Documentation / Config only)

## Screenshots or Screen Recordings (UI Changes)
<!-- Attach screenshots or short videos for any UI/visual adjustments. Required for feature/ui PRs. -->
| Light/Mockup | Dark/Actual (Theme: #101418 / #C7FA5B) |
|---|---|
| *N/A* | *Attach image/clip here* |

## Potential Regression Risks & Mitigation
<!-- Detail any risks to the core Blocker v3 or ML Kit pose counting loop. Note: UI developer must NOT alter LevelUpAccessibilityService.kt or MethodChannel contracts without prior architectural sign-off. -->
- **Core Loop Impact:** None / Described below:
- **Mitigation / Rollback Plan:** 
