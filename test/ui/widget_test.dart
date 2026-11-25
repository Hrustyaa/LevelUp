import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:levelup_test/data/android_app_catalog.dart';
import 'package:levelup_test/focus_experience/focus_screens.dart';
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/screens/levelup_focus_setup_screen.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/screens/levelup_permissions_screen.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';
import 'package:levelup_test/test_kit/challenge_screen.dart';
import 'package:levelup_test/test_kit/test_kit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  testWidgets('Welcome opens App Selection and keeps its draft on back', (
    tester,
  ) async {
    AndroidAppCatalog.clearCache();
    SharedPreferences.setMockInitialValues({});
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

    final focusMethods = <String>[];
    messenger.setMockMethodCallHandler(testKitChannel, (call) async {
      focusMethods.add(call.method);
      return switch (call.method) {
        'getState' => {'serviceEnabled': true, 'enabled': false, 'target': ''},
        'claimFocusChallenge' => null,
        _ => false,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(testKitChannel, null));

    const catalog = MethodChannel('levelup/app_catalog');
    var catalogReads = 0;
    messenger.setMockMethodCallHandler(catalog, (call) async {
      expect(call.method, 'listSupportedApps');
      catalogReads++;
      return [
        {'packageId': 'com.google.android.youtube', 'name': 'YouTube'},
        {'packageId': 'com.instagram.android', 'name': 'Instagram'},
        {'packageId': 'com.zhiliaoapp.musically', 'name': 'TikTok'},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(catalog, null));

    const permissionsChannel = MethodChannel('levelup/permissions');
    messenger.setMockMethodCallHandler(permissionsChannel, (call) async {
      return switch (call.method) {
        'getStates' => {
          'accessibility': 'denied',
          'camera': 'denied',
          'usage': 'unavailable',
          'notifications': 'unavailable',
        },
        _ => null,
      };
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(permissionsChannel, null),
    );

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(const LevelUpIntroDemo());
    await tester.pumpAndSettle();
    expect(find.byType(LevelUpWelcomeScreen), findsOneWidget);

    await tap(find.byKey(const Key('welcome_language_RU')));
    final start = find.byKey(const Key('welcome_get_started'));
    await tap(start);

    expect(find.text('ШАГ 1 ИЗ 3'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    await tap(find.text('Instagram'));
    await tap(find.text('TikTok'));
    expect(find.text('Выбрано: 2'), findsOneWidget);

    await tap(find.byTooltip('Назад'));
    expect(find.text('Начать'), findsOneWidget);
    await tap(start);
    expect(find.text('Выбрано: 2'), findsOneWidget);

    await tap(find.byKey(const ValueKey('continue')));
    final setup = find.byType(LevelUpFocusSetupScreen);
    expect(setup, findsOneWidget);
    expect(
      tester.widget<LevelUpFocusSetupScreen>(setup).language,
      LevelUpLanguage.ru,
    );
    expect(
      tester
          .widget<LevelUpFocusSetupScreen>(setup)
          .selectedApps
          .map((a) => a.packageId)
          .toSet(),
      {'com.instagram.android', 'com.zhiliaoapp.musically'},
    );

    await tap(find.byTooltip('Назад'));
    await tap(find.byKey(const ValueKey('skip')));
    final perms = find.byType(LevelUpPermissionsScreen);
    expect(perms, findsOneWidget);
    expect(
      tester.widget<LevelUpPermissionsScreen>(perms).language,
      LevelUpLanguage.ru,
    );

    await tap(find.byKey(const ValueKey('permissions_skip')));
    final home = find.byType(LevelUpHomeScreen);
    expect(home, findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('levelup.onboarding.completed'), isTrue);

    expect(catalogReads, 1);
  });

  testWidgets(
    'Boots directly to LevelUpHomeScreen when onboarding was already completed',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.welcome.language': 'ru',
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

      messenger.setMockMethodCallHandler(testKitChannel, (call) async {
        return switch (call.method) {
          'getState' => {
            'serviceEnabled': true,
            'enabled': false,
            'target': '',
          },
          'claimFocusChallenge' => null,
          _ => false,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(testKitChannel, null),
      );

      const catalog = MethodChannel('levelup/app_catalog');
      messenger.setMockMethodCallHandler(catalog, (call) async => []);
      addTearDown(() => messenger.setMockMethodCallHandler(catalog, null));

      await tester.pumpWidget(const LevelUpIntroDemo());
      await tester.pumpAndSettle();

      expect(find.byType(LevelUpHomeScreen), findsOneWidget);
      expect(find.byType(LevelUpWelcomeScreen), findsNothing);
    },
  );

  testWidgets('Gate opens real challenge directly and cancel grants nothing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'levelup.onboarding.completed': true,
      'levelup.welcome.language': 'ru',
      'levelup.focus.selected_apps': ['com.google.android.youtube'],
    });
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
    var pending = true;
    var consumed = 0;
    var grants = 0;
    final canceled = <String>[];
    const permissions = MethodChannel('levelup/permissions');
    messenger.setMockMethodCallHandler(
      permissions,
      (_) async => {'accessibility': 'granted'},
    );
    addTearDown(() => messenger.setMockMethodCallHandler(permissions, null));
    String? gateLanguage;
    messenger.setMockMethodCallHandler(testKitChannel, (call) async {
      switch (call.method) {
        case 'setGateLanguage':
          gateLanguage = call.arguments['language'] as String;
          return null;
        case 'claimFocusChallenge':
          if (!pending) return null;
          consumed++;
          pending = false;
          return {'id': 'gate-1', 'target': 'com.google.android.youtube'};
        case 'cancelChallenge':
          canceled.add(call.arguments['id'] as String);
          return true;
        case 'getState':
          return {
            'serviceEnabled': true,
            'enabled': true,
            'target': 'com.google.android.youtube',
          };
        case 'grantAccess':
          grants++;
          return DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch;
      }
      return null;
    });
    const catalog = MethodChannel('levelup/app_catalog');
    AndroidAppCatalog.clearCache();
    messenger.setMockMethodCallHandler(
      catalog,
      (_) async => [
        {'packageId': 'com.google.android.youtube', 'name': 'YouTube'},
      ],
    );
    const pose = MethodChannel('google_mlkit_pose_detector');
    messenger.setMockMethodCallHandler(pose, (call) async {
      expect(call.method, 'vision#closePoseDetector');
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(testKitChannel, null);
      messenger.setMockMethodCallHandler(catalog, null);
      messenger.setMockMethodCallHandler(pose, null);
      AndroidAppCatalog.clearCache();
    });

    await tester.pumpWidget(const LevelUpIntroDemo());
    final challenge = find.byType(ChallengeScreen);
    for (var frame = 0; frame < 40 && challenge.evaluate().isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(gateLanguage, 'ru');
    expect(consumed, 1);
    expect(challenge, findsOneWidget);
    expect(find.byType(TestKitScreen), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LevelUpHomeScreen), findsOneWidget);
    expect(grants, 0);
    expect(canceled, ['gate-1']);

    await tester.tap(find.byKey(const ValueKey('tab_1')));
    await tester.pumpAndSettle();
    final settings = find.byKey(const ValueKey('focus_exercise_settings'));
    await tester.scrollUntilVisible(settings, 240);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.byType(FocusExerciseSettingsScreen), findsOneWidget);
    final press = find.text('Сохранить');
    await tester.ensureVisible(press);
    await tester.tap(press);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('levelup.focus.exercise_selection'), ['squat']);
    expect(prefs.getString('levelup.focus.last_exercise'), 'squat');
    expect(grants, 0);
  });

  testWidgets('gate requires the Android service to be enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final methods = <String>[];
    messenger.setMockMethodCallHandler(testKitChannel, (call) async {
      methods.add(call.method);
      return switch (call.method) {
        'getState' => {'serviceEnabled': false, 'enabled': false},
        'claimFocusChallenge' => null,
        _ => false,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(testKitChannel, null));

    await tester.pumpWidget(const MaterialApp(home: TestKitScreen()));
    await tester.pumpAndSettle();

    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(methods, isNot(contains('setEnabled')));
  });
}
