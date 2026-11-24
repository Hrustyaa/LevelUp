import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppCategory { social, entertainment, messaging, other }

class SelectableApp {
  const SelectableApp({
    required this.packageId,
    required this.name,
    this.category = AppCategory.other,
    this.icon,
    this.suggested = false,
  });

  final String packageId;
  final String name;
  final AppCategory category;
  final Uint8List? icon;
  final bool suggested;
}

class AndroidAppCatalog {
  const AndroidAppCatalog();

  static const _channel = MethodChannel('levelup/app_catalog');
  static List<SelectableApp>? _cached;
  static Future<List<SelectableApp>>? _pending;

  Future<List<SelectableApp>> load({bool forceRefresh = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    if (_pending case final pending?) return pending;
    if (!forceRefresh && _cached != null) return _cached!;

    late final Future<List<SelectableApp>> request;
    request = _read()
        .then((apps) {
          if (!identical(_pending, request)) return apps;
          final cached = _cached;
          if (cached != null && _sameApps(cached, apps)) return cached;
          return _cached = apps;
        })
        .whenComplete(() {
          if (identical(_pending, request)) _pending = null;
        });
    return _pending = request;
  }

  Future<List<SelectableApp>> _read() async {
    final rows = await _channel.invokeListMethod<Object?>('listSupportedApps');
    if (rows == null) throw StateError('Missing Android app catalog');

    final apps = [
      for (final row in rows)
        if (row case {'packageId': final String id, 'name': final String name})
          SelectableApp(
            packageId: id,
            name: name,
            icon: switch (row['icon']) {
              final Uint8List bytes => bytes,
              _ => null,
            },
            suggested: row['suggested'] == true,
            category: switch (row['category']) {
              'social' => AppCategory.social,
              'entertainment' => AppCategory.entertainment,
              'messaging' => AppCategory.messaging,
              _ => AppCategory.other,
            },
          ),
    ];
    return List.unmodifiable(apps);
  }

  static bool _sameApps(List<SelectableApp> a, List<SelectableApp> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      final old = a[index], next = b[index];
      if (old.packageId != next.packageId ||
          old.name != next.name ||
          old.category != next.category ||
          old.suggested != next.suggested ||
          !listEquals(old.icon, next.icon)) {
        return false;
      }
    }
    return true;
  }

  static void clearCache() {
    _pending = null;
    _cached = null;
  }
}
