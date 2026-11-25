import '../data/levelup_permissions.dart';

enum SettingsPermissionCheck { unchecked, partial, checked }

/// Read-only summary. The existing App Permissions screen owns per-permission
/// statuses and requests.
Future<SettingsPermissionCheck> readSettingsPermissions(
  LevelUpPermissionGateway gateway,
) async {
  try {
    final states = await gateway.read();
    final known = LevelUpPermission.values.where((permission) {
      final state = states[permission];
      return state != null && state != PermissionState.unknown;
    }).length;
    if (known == LevelUpPermission.values.length) {
      return SettingsPermissionCheck.checked;
    }
    if (known > 0) return SettingsPermissionCheck.partial;
  } catch (_) {
    // The platform may not expose the permission bridge on this build.
  }
  return SettingsPermissionCheck.unchecked;
}
