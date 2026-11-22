import 'package:material_ui/material_ui.dart';

import 'features/developer_lab/dev_lab_app.dart';

/// Dedicated entrypoint for LevelUp Developer Lab QA and Backend Verification.
///
/// Run on device or emulator with:
///   flutter run -t lib/main_dev.dart
///
/// Build debug APK with:
///   flutter build apk --debug -t lib/main_dev.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DevLabApp());
}
