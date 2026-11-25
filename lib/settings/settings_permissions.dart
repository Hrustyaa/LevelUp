import '../data/levelup_permissions.dart' as data_permissions;

enum SettingsPermissionCheck { unchecked, partial, checked }

enum LevelUpPermission { usageAccess, accessibility, camera, notifications }

enum LevelUpPermissionState { unknown, denied, granted }

class LevelUpPermissionSnapshot {
  const LevelUpPermissionSnapshot([this.states = const {}]);

  final Map<LevelUpPermission, LevelUpPermissionState> states;

  LevelUpPermissionState stateOf(LevelUpPermission permission) =>
      states[permission] ?? LevelUpPermissionState.unknown;
}

typedef LevelUpPermissionLoader = Future<LevelUpPermissionSnapshot> Function();

/// Read-only summary. The existing App Permissions screen owns per-permission
/// statuses and requests.
Future<SettingsPermissionCheck> readSettingsPermissions(
  data_permissions.LevelUpPermissionGateway gateway,
) async {
  try {
    final states = await gateway.read();
    final known = data_permissions.LevelUpPermission.values.where((permission) {
      final state = states[permission];
      return state != null && state != data_permissions.PermissionState.unknown;
    }).length;
    if (known == data_permissions.LevelUpPermission.values.length) {
      return SettingsPermissionCheck.checked;
    }
    if (known > 0) return SettingsPermissionCheck.partial;
  } catch (_) {
    // The platform may not expose the permission bridge on this build.
  }
  return SettingsPermissionCheck.unchecked;
}
