import 'package:material_ui/material_ui.dart';

/// Health status of a LevelUp backend module.
enum ModuleHealthStatus {
  /// Module is initialized and operational.
  ready('Ready', Color(0xFFC7FA5B), Icons.check_circle_outline),

  /// Module is blocked awaiting an Android system permission.
  needsPermission('Needs Permission', Color(0xFFFFA726), Icons.warning_amber_rounded),

  /// Module encountered a runtime or bridge failure.
  failed('Failed', Color(0xFFEF5350), Icons.error_outline),

  /// Module has not been queried or tested in the current session.
  notTested('Not Tested', Color(0xFF85919A), Icons.help_outline),

  /// Feature is unsupported on the current device or configuration.
  unsupported('Unsupported', Color(0xFFAB47BC), Icons.block);

  final String label;
  final Color color;
  final IconData icon;

  const ModuleHealthStatus(this.label, this.color, this.icon);
}
