import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/data/levelup_permissions.dart';
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/screens/app_permissions_screen.dart';
import 'package:levelup_test/screens/manage_apps_screen.dart';
import 'package:levelup_test/settings/settings_permissions.dart';
import 'package:levelup_test/settings/settings_tab.dart';
import 'package:levelup_test/test_kit/test_kit_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _permissionsChannel = MethodChannel('levelup/permissions');
const _settingsTab = ValueKey('tab_4');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockChannel(
    MethodChannel channel,
    Future<Object?> Function(MethodCall) handler,
  ) {
    messenger.setMockMethodCallHandler(channel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  void mockOnboardedApp(WidgetTester tester) {
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

    SharedPreferences.setMockInitialValues({
      'levelup.onboarding.completed': true,
      'levelup.welcome.language': 'en',
    });
    mockChannel(
      testKitChannel,
      (call) async => call.method == 'getState'
          ? {'serviceEnabled': false, 'enabled': false, 'target': ''}
          : null,
    );
    mockChannel(const MethodChannel('levelup/app_catalog'), (_) async => []);
  }

  test(
    'the permission summary reflects checked, missing and partial states',
    () async {
      const gateway = AndroidPermissionGateway();
      expect(
        await readSettingsPermissions(gateway),
        SettingsPermissionCheck.unchecked,
      );

      var nativeStates = <String, String>{'camera': 'denied'};
      mockChannel(_permissionsChannel, (call) async {
        expect(call.method, 'getStates');
        return nativeStates;
      });
      expect(
        await readSettingsPermissions(gateway),
        SettingsPermissionCheck.partial,
      );

      nativeStates = {
        'accessibility': 'granted',
        'camera': 'denied',
        'usage': 'denied',
        'notifications': 'unavailable',
      };
      expect(
        await readSettingsPermissions(gateway),
        SettingsPermissionCheck.checked,
      );

      nativeStates = {'camera': 'unsupported value'};
      expect(
        await readSettingsPermissions(gateway),
        SettingsPermissionCheck.unchecked,
      );
    },
  );

  testWidgets('missing actions are disabled and cannot open another page', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHost());
    for (final row in [
      'settings_permissions',
      'settings_notifications',
      'settings_manage_apps',
    ]) {
      final finder = find.byKey(ValueKey(row));
      expect(
        find.descendant(of: finder, matching: find.text('Недоступно')),
        findsOneWidget,
      );
      final tile = tester.widget<InkWell>(
        find.descendant(of: finder, matching: find.byType(InkWell)),
      );
      expect(tile.onTap, isNull);
      await _tap(tester, finder);
      expect(find.byType(LevelUpSettingsTab), findsOneWidget);
    }
  });

  testWidgets('notifications use their own callback when available', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _settingsHost(
        onNotifications: () async {
          calls++;
        },
      ),
    );
    await _tap(tester, find.byKey(const ValueKey('settings_notifications')));
    expect(calls, 1);
  });

  testWidgets('permission checks refresh after Android resumes', (
    tester,
  ) async {
    var reads = 0;
    mockChannel(_permissionsChannel, (call) async {
      expect(call.method, 'getStates');
      if (++reads == 1) throw PlatformException(code: 'unavailable');
      return {'camera': 'granted'};
    });
    await tester.pumpWidget(_settingsHost(onPermissions: () async {}));
    await tester.pumpAndSettle();
    expect(find.text('Не проверено'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(reads, 2);
    expect(find.text('Часть не проверена'), findsOneWidget);
    expect(find.text('Разрешено'), findsNothing);
  });

  testWidgets('Focus challenge is read-only and Back returns to Settings', (
    tester,
  ) async {
    await tester.pumpWidget(_settingsHost());
    await _tap(tester, find.byKey(const ValueKey('settings_focus_challenge')));
    expect(find.byType(LevelUpUnlockChallengeSettingsScreen), findsOneWidget);
    expect(find.text('Приседания'), findsOneWidget);
    expect(find.text('5 повторений'), findsOneWidget);
    expect(find.text('Недоступно'), findsNWidgets(4));
    expect(
      find.text('Фокус можно выключить в любой момент без выполнения задания.'),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LevelUpSettingsTab), findsOneWidget);
  });

  testWidgets(
    'dashboard opens the real app and permission screens and Focus tab',
    (tester) async {
      mockOnboardedApp(tester);
      mockChannel(_permissionsChannel, (call) async {
        expect(call.method, 'getStates');
        throw PlatformException(code: 'bridge_unavailable');
      });
      await tester.pumpWidget(const LevelUpIntroDemo());
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(_settingsTab));

      expect(find.text('Not checked'), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('settings_manage_apps')));
      expect(find.byType(ManageAppsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LevelUpSettingsTab), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('settings_permissions')));
      expect(find.byType(AppPermissionsScreen), findsOneWidget);
      expect(find.text('Could not read permissions.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LevelUpSettingsTab), findsOneWidget);

      await _tap(tester, find.byKey(const ValueKey('settings_focus_rules')));
      final focusTab = find
          .ancestor(
            of: find.byKey(const ValueKey('tab_1')),
            matching: find.byType(Semantics),
          )
          .first;
      expect(tester.widget<Semantics>(focusTab).properties.selected, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const PageStorageKey(DashboardTab.home)),
        findsOneWidget,
      );
    },
  );

  testWidgets('uses the saved locale across app restarts', (tester) async {
    mockOnboardedApp(tester);
    await tester.pumpWidget(const LevelUpIntroDemo());
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(_settingsTab));
    final languageRow = find.byKey(const ValueKey('settings_language'));
    final prefs = await SharedPreferences.getInstance();

    for (final (label, code, title) in [
      ('Русский', 'ru', 'Общие'),
      ('Қазақша', 'kk', 'Жалпы'),
      ('English', 'en', 'General'),
    ]) {
      await _tap(tester, languageRow);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(label),
        ),
      );
      expect(find.text(title.toUpperCase()), findsOneWidget);
      expect(prefs.getString('levelup.welcome.language'), code);
    }

    await _tap(tester, languageRow);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Қазақша'),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const LevelUpIntroDemo());
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(_settingsTab));
    expect(find.text('ЖАЛПЫ'), findsOneWidget);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('dashboard Settings fits ${width.toInt()} dp with 200% text', (
      tester,
    ) async {
      mockOnboardedApp(tester);
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const LevelUpIntroDemo());
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(_settingsTab));
      await _tap(tester, find.byKey(const ValueKey('settings_language')));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Қазақша'),
        ),
      );
      final scrollable = find.descendant(
        of: find.byKey(const PageStorageKey(DashboardTab.settings)),
        matching: find.byType(Scrollable),
      );
      for (final (row, page) in [
        ('settings_focus_challenge', LevelUpUnlockChallengeSettingsScreen),
        ('settings_privacy', LevelUpPrivacySettingsScreen),
        ('settings_about', LevelUpAboutSettingsScreen),
      ]) {
        final finder = find.byKey(ValueKey(row));
        await tester.scrollUntilVisible(finder, 110, scrollable: scrollable);
        await _tap(tester, finder);
        expect(find.byType(page), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _settingsHost({
  Future<void> Function()? onPermissions,
  Future<void> Function()? onNotifications,
}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        LevelUpSettingsTab(
          language: DashboardLanguage.ru,
          onLanguageChanged: (_) {},
          onFocusRules: () {},
          onOpenPermissions: onPermissions,
          onOpenNotifications: onNotifications,
        ),
      ],
    ),
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
