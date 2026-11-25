import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/android_app_catalog.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/data/levelup_permissions.dart';
import 'package:levelup_test/focus_experience/focus_exercises.dart';
import 'package:levelup_test/focus_experience/focus_screens.dart';
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/screens/app_permissions_screen.dart';
import 'package:levelup_test/screens/levelup_app_selection_screen.dart';
import 'package:levelup_test/screens/levelup_focus_setup_screen.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/screens/levelup_permissions_screen.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';
import 'package:levelup_test/screens/manage_apps_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _youtube = 'com.google.android.youtube';
const _instagram = 'com.instagram.android';
const _catalog = MethodChannel('levelup/app_catalog');
const _permissions = MethodChannel('levelup/permissions');
const _apps = [
  {'packageId': _youtube, 'name': 'YouTube'},
  {'packageId': _instagram, 'name': 'Instagram'},
];

class _IdleFocus implements DashboardFocusGateway {
  const _IdleFocus();
  @override
  Future<FocusSnapshot> read() async =>
      const FocusSnapshot(enabled: false, serviceEnabled: true);
  @override
  Future<void> enable({String? target}) async {}
  @override
  Future<void> disable() async {}
}

class _PendingPermissions implements LevelUpPermissionGateway {
  final reads = <Completer<Map<LevelUpPermission, PermissionState>>>[];

  @override
  Future<Map<LevelUpPermission, PermissionState>> read() {
    final result = Completer<Map<LevelUpPermission, PermissionState>>();
    reads.add(result);
    return result.future;
  }

  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> request(LevelUpPermission permission) async {}
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'catalog shares in-flight reads and keeps identical rows stable',
    () async {
      AndroidAppCatalog.clearCache();
      final first = Completer<Object?>();
      var reads = 0;
      messenger.setMockMethodCallHandler(_catalog, (_) {
        reads++;
        return reads == 1 ? first.future : Future.value(_apps);
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(_catalog, null);
        AndroidAppCatalog.clearCache();
      });

      const gateway = AndroidAppCatalog();
      final a = gateway.load();
      final b = gateway.load(forceRefresh: true);
      first.complete(_apps);
      final initial = await a;
      expect(await b, same(initial));
      expect(reads, 1);
      expect(await gateway.load(forceRefresh: true), same(initial));
      expect(reads, 2);
    },
  );

  testWidgets('older permission responses cannot replace a newer grant', (
    tester,
  ) async {
    final gateway = _PendingPermissions();
    LevelUpPermission? managed;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPermissionsScreen(
          gateway: gateway,
          openPermissionSettings: (permission) async => managed = permission,
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(gateway.reads, hasLength(2));
    gateway.reads.last.complete({
      LevelUpPermission.usage: PermissionState.granted,
    });
    await tester.pumpAndSettle();
    expect(find.text('Granted'), findsOneWidget);
    gateway.reads.first.complete({
      LevelUpPermission.usage: PermissionState.denied,
    });
    await tester.pumpAndSettle();
    expect(find.text('Granted'), findsOneWidget);
    expect(find.text('Grant access'), findsNothing);
    await _tap(tester, find.text('Manage in OS'));
    expect(managed, LevelUpPermission.usage);
  });

  testWidgets('Manage Apps keeps save disabled when the catalog fails', (
    tester,
  ) async {
    final pending = Completer<List<SelectableApp>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ManageAppsScreen(
          loadApps: () => pending.future,
          initialSelectedIds: const {_youtube},
          onSave: (_) => fail('An unchecked catalog cannot be saved'),
        ),
      ),
    );
    final save = find.widgetWithText(FilledButton, 'Save changes');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    pending.completeError(StateError('catalog unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load installed apps.'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
  });

  testWidgets(
    'Focus requires a target choice and turns off when it is removed',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'levelup.onboarding.completed': true,
        'levelup.focus.selected_apps': [_youtube, _instagram],
      });
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      AndroidAppCatalog.clearCache();
      final switches = <bool>[];
      var enabled = false;
      var target = _youtube;
      const control = ExistingFocusGateway.channel;
      messenger.setMockMethodCallHandler(control, (call) async {
        switch (call.method) {
          case 'getState':
            return {
              'serviceEnabled': true,
              'enabled': enabled,
              'target': target,
            };
          case 'setTarget':
            target = call.arguments['target'] as String;
            return true;
          case 'setEnabled':
            enabled = call.arguments['enabled'] as bool;
            switches.add(enabled);
            return true;
          case 'hasChallengeRequest':
            return false;
          default:
            return null;
        }
      });
      messenger.setMockMethodCallHandler(_catalog, (_) async => _apps);
      messenger.setMockMethodCallHandler(
        _permissions,
        (_) async => {'accessibility': 'granted'},
      );
      addTearDown(() {
        dispatcher.clearAccessibilityFeaturesTestValue();
        AndroidAppCatalog.clearCache();
        for (final channel in [control, _catalog, _permissions]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });

      await tester.pumpWidget(const LevelUpIntroDemo());
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('home_enable')));
      expect(switches, isEmpty);
      await _tap(
        tester,
        find.byKey(const ValueKey('focus_target_$_instagram')),
      );
      expect(target, _instagram);
      expect(switches, [true]);

      await _tap(tester, find.byKey(const ValueKey('tab_1')));
      final edit = find.byKey(const ValueKey('edit_apps_button'));
      await _tap(tester, edit);
      expect(find.byType(ManageAppsScreen), findsOneWidget);
      await _tap(tester, find.text('Instagram'));
      await _tap(tester, find.text('Save changes'));
      expect(switches, [true, false]);
      final prefs = await SharedPreferences.getInstance();
      final draft =
          jsonDecode(prefs.getString('levelup.focus.draft_json')!) as Map;
      expect(draft['packageIds'], [_youtube]);
    },
  );

  for (final language in LevelUpLanguage.values) {
    testWidgets(
      'setup and exercise routes fit compact large type in ${language.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 580);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const selected = [SelectableApp(packageId: _youtube, name: 'YouTube')];
        final permissions = _PendingPermissions();
        final dashboardLanguage = DashboardLanguage.values.byName(
          language.name,
        );
        final routes = [
          LevelUpWelcomeScreen(initialLanguage: language, onGetStarted: (_) {}),
          LevelUpAppSelectionScreen(
            language: language,
            loadApps: () async => selected,
            initialSelectedIds: const {_youtube},
            onBack: () {},
            onSkip: () {},
            onContinue: (_) {},
          ),
          LevelUpFocusSetupScreen(
            language: language,
            selectedApps: selected,
            onBack: () {},
            onSkip: () {},
            onContinue: (_) {},
          ),
          LevelUpPermissionsScreen(
            language: language,
            gateway: permissions,
            onBack: () {},
            onFinish: (_) {},
          ),
          AppPermissionsScreen(
            language: dashboardLanguage,
            gateway: permissions,
          ),
          ManageAppsScreen(
            language: dashboardLanguage,
            initialSelectedIds: const {_youtube},
            loadApps: () async => selected,
            onSave: (_) {},
          ),
          FocusExerciseSettingsScreen(
            language: language.name,
            initialSelection: const {FocusExerciseId.squat},
            onSave: (_) {},
          ),
          FocusChallengeScreen(
            language: language.name,
            exercise: focusExercises.first,
            repetitions: 2,
            onCancel: () {},
            cameraPreview: const SizedBox(),
            trackingReady: true,
            cameraReady: true,
          ),
          FocusAccessGrantedScreen(
            language: language.name,
            appName: 'YouTube · 5',
            accessMinutes: 5,
            onDone: () {},
          ),
        ];
        for (final route in routes) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(route.runtimeType),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: route,
            ),
          );
          if (route is LevelUpPermissionsScreen ||
              route is AppPermissionsScreen) {
            permissions.reads.last.complete({
              for (final permission in LevelUpPermission.values)
                permission: PermissionState.granted,
            });
          }
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${route.runtimeType} in ${language.name}',
          );
        }
      },
    );
  }

  for (final language in DashboardLanguage.values) {
    testWidgets(
      'dashboard tabs fit compact display with large type in ${language.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 580);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: LevelUpHomeScreen(
              gateway: const _IdleFocus(),
              language: language,
              logoAsset: null,
              catalog: const [DashboardApp(_youtube, 'YouTube')],
              draftIds: const {_youtube},
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var tab = 0; tab < DashboardTab.values.length; tab++) {
          await _tap(tester, find.byKey(ValueKey('tab_$tab')));
          expect(
            find.byKey(PageStorageKey(DashboardTab.values[tab])),
            findsOneWidget,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'tab $tab in ${language.name}',
          );
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const PageStorageKey(DashboardTab.home)),
          findsOneWidget,
        );
      },
    );
  }
}
