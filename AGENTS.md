# LevelUp

- Preserve the existing Flutter UI and reuse its widgets and theme.
- Keep ML Kit pose counting separate from the presentation-only overlay.
- Route app unlocks through ChallengeService, CoreIntegrationCoordinator, AccessService, and the native Gate. The standard unlock is 300 seconds.
- Keep simulated and experimental workouts out of production XP and progress. Require physical-device validation before enabling a new exercise for production authorization.
- Preserve SQLite data and historical verification sources.
- Validate with `flutter pub get`, `flutter analyze --no-pub`, `flutter test --no-pub`, and debug APK builds with `--no-pub -t lib/main_ui.dart` and `--no-pub -t lib/main_dev.dart`.
