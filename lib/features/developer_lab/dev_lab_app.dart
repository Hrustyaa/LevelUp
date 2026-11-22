import 'package:material_ui/material_ui.dart';

import 'di/dev_lab_scope.dart';
import 'models/dev_mode.dart';
import 'screens/system_hub_screen.dart';
import 'theme/dev_lab_theme.dart';

/// Root application widget for LevelUp Developer Lab.
///
/// Encapsulates the reactive [DevLabController] service composition root and
/// provides the shared QA theme to the entire testing interface.
class DevLabApp extends StatefulWidget {
  final DevExecutionMode initialMode;

  const DevLabApp({
    super.key,
    this.initialMode = DevExecutionMode.realDevice,
  });

  @override
  State<DevLabApp> createState() => _DevLabAppState();
}

class _DevLabAppState extends State<DevLabApp> {
  late final DevLabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DevLabController(initialMode: widget.initialMode);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DevLabScope(
      notifier: _controller,
      child: MaterialApp(
        title: 'LevelUp Dev Lab',
        debugShowCheckedModeBanner: false,
        theme: DevLabTheme.theme,
        home: const SystemHubScreen(),
      ),
    );
  }
}
