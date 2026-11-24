import '../../core/constants/channel_constants.dart';
import '../../data/android_app_catalog.dart';
import '../../data/dashboard_data.dart';

/// Production adapter connecting UI app selection to the backend's allowed targets.
///
/// Restricts selectable apps strictly to [ChannelConstants.allowedTargets] (YouTube, Instagram, TikTok),
/// matching the Android Accessibility Service single-target blocker capabilities.
class CoreAppCatalogAdapter {
  const CoreAppCatalogAdapter();

  /// Canonical list of selectable applications supported by the native gate.
  static const List<SelectableApp> supportedApps = [
    SelectableApp(
      packageId: ChannelConstants.targetYouTube,
      name: 'YouTube',
      category: AppCategory.entertainment,
      suggested: true,
    ),
    SelectableApp(
      packageId: ChannelConstants.targetInstagram,
      name: 'Instagram',
      category: AppCategory.social,
      suggested: true,
    ),
    SelectableApp(
      packageId: ChannelConstants.targetTikTok,
      name: 'TikTok',
      category: AppCategory.entertainment,
      suggested: true,
    ),
  ];

  /// Canonical dashboard presentation models for allowed target applications.
  static final List<DashboardApp> dashboardApps = supportedApps
      .map((app) => DashboardApp(app.packageId, app.name, icon: app.icon))
      .toList(growable: false);

  /// Loads the supported applications catalog.
  Future<List<SelectableApp>> loadSupportedApps({bool forceRefresh = false}) async {
    return supportedApps;
  }

  /// Checks whether [packageId] is in the allowed targets set.
  static bool isSupported(String packageId) =>
      ChannelConstants.allowedTargets.contains(packageId);

  /// Sanitizes [packageId], falling back to [ChannelConstants.defaultTarget] if unsupported.
  static String sanitizeTarget(String packageId) {
    if (isSupported(packageId)) return packageId;
    return ChannelConstants.defaultTarget;
  }

  /// Resolves exactly one supported target from a set of selected package IDs.
  ///
  /// Returns null if [packageIds] does not contain any supported package.
  static String? resolveSingleTarget(Set<String> packageIds) {
    for (final id in packageIds) {
      if (isSupported(id)) return id;
    }
    return null;
  }
}
