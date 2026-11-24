import 'package:flutter/services.dart';

enum LevelUpPermission { accessibility, camera, usage, notifications }

enum PermissionState { unknown, denied, granted, unavailable }

abstract class LevelUpPermissionGateway {
  Future<Map<LevelUpPermission, PermissionState>> read();
  Future<void> request(LevelUpPermission permission);
  Future<void> openAppSettings();
}

/// No auto-requests, no activation of Focus, no data collection.
class AndroidPermissionGateway implements LevelUpPermissionGateway {
  const AndroidPermissionGateway();
  static const _channel = MethodChannel('levelup/permissions');

  /// The team's legacy blocker does not register this UI bridge.
  Future<bool> isAvailable() async {
    try {
      final values = await _channel.invokeMapMethod<String, String>(
        'getStates',
      );
      return values?.containsKey('accessibility') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Map<LevelUpPermission, PermissionState>> read() async {
    final values = await _channel.invokeMapMethod<String, String>('getStates');
    if (values == null) throw StateError('Missing permission states');
    return {
      for (final p in LevelUpPermission.values)
        p: switch (values[p.name]) {
          'granted' => PermissionState.granted,
          'denied' => PermissionState.denied,
          'unavailable' => PermissionState.unavailable,
          _ => PermissionState.unknown,
        },
    };
  }

  @override
  Future<void> request(LevelUpPermission permission) =>
      _channel.invokeMethod<void>('request', {'permission': permission.name});
  Future<void> openPermissionSettings(LevelUpPermission permission) =>
      _channel.invokeMethod<void>('openPermissionSettings', {
        'permission': permission.name,
      });

  @override
  Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');
}

class PermissionsOutcome {
  PermissionsOutcome({
    required this.skipped,
    required Map<LevelUpPermission, PermissionState> states,
  }) : states = Map.unmodifiable(states);
  final bool skipped;
  final Map<LevelUpPermission, PermissionState> states;
  bool get accessibilityGranted =>
      states[LevelUpPermission.accessibility] == PermissionState.granted;
}
