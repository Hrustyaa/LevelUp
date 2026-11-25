import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../data/dashboard_data.dart';

/// Use only the native app catalog's actually installed, launchable,
/// voluntarily restrictable apps. This Flutter model does not enumerate apps.
@immutable
class LevelUpInstalledApp {
  const LevelUpInstalledApp({
    required this.packageId,
    required this.displayName,
    this.iconPng,
  });

  final String packageId;
  final String displayName;
  final Uint8List? iconPng;
}

typedef LevelUpAppsLoader = Future<List<LevelUpInstalledApp>> Function();
typedef LevelUpCurrentTargetLoader = Future<String?> Function();
typedef LevelUpTargetSaver = Future<void> Function(String packageId);

/// The native Focus engine currently supports one active target; do not
/// expose a multi-select UI until the engine truly supports multiple targets.
/// System-critical apps must be excluded at the native catalog boundary.
List<LevelUpInstalledApp> eligibleInstalledApps(
  Iterable<LevelUpInstalledApp> source,
) {
  const forbidden = <String>{
    'android',
    'com.android.settings',
    'com.android.systemui',
    'com.android.phone',
    'com.android.dialer',
    'com.google.android.dialer',
    'com.android.emergency',
    'com.google.android.apps.safetyhub',
    'com.google.android.permissioncontroller',
    'com.google.android.packageinstaller',
  };
  final byId = <String, LevelUpInstalledApp>{};
  for (final app in source) {
    final id = app.packageId.trim();
    final name = app.displayName.trim();
    if (id.isEmpty || name.isEmpty || forbidden.contains(id)) continue;
    byId[id] = app;
  }
  final result = byId.values.toList(growable: false);
  result.sort((a, b) {
    final compare = a.displayName.toLowerCase().compareTo(
      b.displayName.toLowerCase(),
    );
    return compare != 0 ? compare : a.packageId.compareTo(b.packageId);
  });
  return List.unmodifiable(result);
}

abstract final class LevelUpAccessPalette {
  static const background = Color(0xFF0A0F10);
  static const surface = Color(0xFF111718);
  static const accent = Color(0xFFC7FA5B);
  static const foreground = Color(0xFFF7F8F8);
  static const secondary = Color(0xFFB0B8BA);
  static const border = Color(0xFF293334);
}

String levelUpAccessTr(
  DashboardLanguage language,
  String russian,
  String english,
  String kazakh,
) => switch (language) {
  DashboardLanguage.ru => russian,
  DashboardLanguage.en => english,
  DashboardLanguage.kk => kazakh,
};

ThemeData levelUpAccessTheme() => ThemeData.dark(useMaterial3: true).copyWith(
  scaffoldBackgroundColor: LevelUpAccessPalette.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: LevelUpAccessPalette.background,
    foregroundColor: LevelUpAccessPalette.foreground,
    elevation: 0,
    centerTitle: false,
  ),
  colorScheme: const ColorScheme.dark(
    primary: LevelUpAccessPalette.accent,
    onPrimary: LevelUpAccessPalette.background,
    surface: LevelUpAccessPalette.surface,
    onSurface: LevelUpAccessPalette.foreground,
    outline: LevelUpAccessPalette.border,
  ),
);
