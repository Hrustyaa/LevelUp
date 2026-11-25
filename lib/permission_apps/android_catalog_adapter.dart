import 'package:flutter/services.dart';

import 'permission_apps_models.dart';

/// Optional read-only adapter for the pre-existing levelup/app_catalog channel
/// from the old app-picker prototype. This file DOES NOT register a channel.
/// If current LevelUp already uses another native app catalog, use that one.
class LevelUpAndroidCatalogAdapter {
  const LevelUpAndroidCatalogAdapter();

  static const MethodChannel _channel = MethodChannel('levelup/app_catalog');

  Future<List<LevelUpInstalledApp>> loadSupportedApps() async {
    final records = await _channel.invokeListMethod<dynamic>(
      'listSupportedApps',
    );
    if (records == null) {
      throw StateError('Android app catalog did not return a list');
    }
    final apps = <LevelUpInstalledApp>[];
    for (final record in records) {
      if (record is! Map) continue;
      final map = Map<Object?, Object?>.from(record);
      if (map['supported'] == false) continue;
      final id = map['packageId'];
      final name = map['name'];
      if (id is! String || name is! String || id.isEmpty || name.isEmpty) {
        continue;
      }
      final rawIcon = map['icon'];
      final icon = switch (rawIcon) {
        Uint8List value => value,
        List<int> value => Uint8List.fromList(value),
        _ => null,
      };
      apps.add(
        LevelUpInstalledApp(packageId: id, displayName: name, iconPng: icon),
      );
    }
    return eligibleInstalledApps(apps);
  }
}
