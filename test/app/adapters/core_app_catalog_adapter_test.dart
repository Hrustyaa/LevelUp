import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/adapters/core_app_catalog_adapter.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/android_app_catalog.dart';

void main() {
  group('CoreAppCatalogAdapter Tests', () {
    const adapter = CoreAppCatalogAdapter();

    test('1. Supported target catalog contains exactly the 3 allowed targets', () async {
      final apps = await adapter.loadSupportedApps();

      expect(apps.length, 3);
      final packageIds = apps.map((a) => a.packageId).toSet();
      expect(packageIds, ChannelConstants.allowedTargets);
      expect(packageIds, {
        'com.google.android.youtube',
        'com.instagram.android',
        'com.zhiliaoapp.musically',
      });
    });

    test('2. Apps have valid names and categories', () async {
      final apps = await adapter.loadSupportedApps();

      final youtube = apps.firstWhere((a) => a.packageId == ChannelConstants.targetYouTube);
      expect(youtube.name, 'YouTube');
      expect(youtube.category, AppCategory.entertainment);
      expect(youtube.suggested, isTrue);

      final instagram = apps.firstWhere((a) => a.packageId == ChannelConstants.targetInstagram);
      expect(instagram.name, 'Instagram');
      expect(instagram.category, AppCategory.social);
      expect(instagram.suggested, isTrue);

      final tiktok = apps.firstWhere((a) => a.packageId == ChannelConstants.targetTikTok);
      expect(tiktok.name, 'TikTok');
      expect(tiktok.category, AppCategory.entertainment);
      expect(tiktok.suggested, isTrue);
    });

    test('3. Single-target resolution enforces exactly one supported target', () {
      // Empty set resolves to null
      expect(CoreAppCatalogAdapter.resolveSingleTarget({}), isNull);

      // Unsupported packages resolve to null
      expect(CoreAppCatalogAdapter.resolveSingleTarget({'com.unsupported.app'}), isNull);

      // Single supported target resolves directly
      expect(
        CoreAppCatalogAdapter.resolveSingleTarget({'com.google.android.youtube'}),
        ChannelConstants.targetYouTube,
      );

      // Multiple targets resolves to the first supported target (single-target invariant)
      final resolved = CoreAppCatalogAdapter.resolveSingleTarget({
        'com.unsupported.random',
        ChannelConstants.targetInstagram,
        ChannelConstants.targetYouTube,
      });
      expect(resolved, ChannelConstants.targetInstagram);
    });

    test('4. Sanitize target falls back to default YouTube when given invalid package', () {
      expect(
        CoreAppCatalogAdapter.sanitizeTarget(ChannelConstants.targetTikTok),
        ChannelConstants.targetTikTok,
      );
      expect(
        CoreAppCatalogAdapter.sanitizeTarget('com.unknown.bad.package'),
        ChannelConstants.defaultTarget,
      );
    });

    test('5. isSupported strictly validates allowedTargets', () {
      expect(CoreAppCatalogAdapter.isSupported(ChannelConstants.targetYouTube), isTrue);
      expect(CoreAppCatalogAdapter.isSupported(ChannelConstants.targetInstagram), isTrue);
      expect(CoreAppCatalogAdapter.isSupported(ChannelConstants.targetTikTok), isTrue);
      expect(CoreAppCatalogAdapter.isSupported('com.facebook.katana'), isFalse);
      expect(CoreAppCatalogAdapter.isSupported(''), isFalse);
    });
  });
}
