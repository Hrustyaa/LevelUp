import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/settings/settings_permissions.dart';
import 'package:levelup_test/permission_apps/permission_apps_models.dart';
import 'package:levelup_test/permission_apps/levelup_permissions_screen.dart';
import 'package:levelup_test/permission_apps/levelup_manage_apps_screen.dart';

const youtube = LevelUpInstalledApp(
  packageId: 'com.google.android.youtube',
  displayName: 'YouTube',
);
const instagram = LevelUpInstalledApp(
  packageId: 'com.instagram.android',
  displayName: 'Instagram',
);

Widget permissionHost({
  LevelUpPermissionLoader? load,
  LevelUpPermissionOpener? opener,
  Future<void> Function()? openApps,
  DashboardLanguage language = DashboardLanguage.ru,
}) => MaterialApp(
  home: LevelUpPermissionsScreen(
    language: language,
    loadStates: load,
    openPermission: opener,
    openApps: openApps,
  ),
);

Widget pickerHost({
  required LevelUpAppsLoader loadApps,
  required LevelUpCurrentTargetLoader loadTarget,
  required LevelUpTargetSaver saveTarget,
  DashboardLanguage language = DashboardLanguage.ru,
}) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<String>(
              builder: (_) => LevelUpManageAppsScreen(
                language: language,
                loadApps: loadApps,
                loadSelectedTarget: loadTarget,
                saveTarget: saveTarget,
              ),
            ),
          ),
          child: const Text('OPEN PICKER'),
        ),
      ),
    ),
  ),
);

Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(find.text('OPEN PICKER'));
  await tester.pumpAndSettle();
}

void main() {
  test('filters known system-critical and duplicate apps', () {
    final selected = eligibleInstalledApps([
      youtube,
      instagram,
      youtube,
      const LevelUpInstalledApp(
        packageId: 'com.android.settings',
        displayName: 'Settings',
      ),
      const LevelUpInstalledApp(packageId: '', displayName: 'Invalid'),
    ]);
    expect(selected.map((app) => app.packageId), [
      'com.instagram.android',
      'com.google.android.youtube',
    ]);
  });

  testWidgets('unknown permission statuses are never displayed as granted', (
    tester,
  ) async {
    await tester.pumpWidget(permissionHost());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('access_permission_list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('access_status_usageAccess')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('access_status_accessibility')),
      findsOneWidget,
    );
    expect(find.text('Разрешено'), findsNothing);
  });

  testWidgets('real permission loader supplies actual statuses', (
    tester,
  ) async {
    await tester.pumpWidget(
      permissionHost(
        load: () async => const LevelUpPermissionSnapshot({
          LevelUpPermission.camera: LevelUpPermissionState.granted,
          LevelUpPermission.usageAccess: LevelUpPermissionState.denied,
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Разрешено'), findsOneWidget);
    expect(find.text('Не разрешено'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('access_status_usageAccess')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('access_permission_camera')),
    );
    expect(find.text('Разрешено'), findsOneWidget);
  });

  testWidgets(
    'permission tap goes through specific Android adapter and reloads',
    (tester) async {
      var granted = false;
      final opened = <LevelUpPermission>[];
      await tester.pumpWidget(
        permissionHost(
          load: () async => LevelUpPermissionSnapshot({
            LevelUpPermission.usageAccess: granted
                ? LevelUpPermissionState.granted
                : LevelUpPermissionState.denied,
          }),
          opener: (p) async {
            opened.add(p);
            granted = true;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('access_permission_usageAccess')),
      );
      await tester.pumpAndSettle();
      expect(opened, [LevelUpPermission.usageAccess]);
      expect(find.text('Разрешено'), findsOneWidget);
    },
  );

  testWidgets('picker does not save until explicit Save', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      pickerHost(
        loadApps: () async => [youtube, instagram],
        loadTarget: () async => null,
        saveTarget: (id) async => saved.add(id),
      ),
    );
    await openPicker(tester);
    expect(find.byKey(const ValueKey('access_save_app')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('access_app_com.google.android.youtube')),
    );
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    await tester.tap(find.byKey(const ValueKey('access_save_app')));
    await tester.pumpAndSettle();
    expect(saved, ['com.google.android.youtube']);
    expect(find.text('OPEN PICKER'), findsOneWidget);
  });

  testWidgets('search does not clear selection', (tester) async {
    final saved = <String>[];
    await tester.pumpWidget(
      pickerHost(
        loadApps: () async => [youtube, instagram],
        loadTarget: () async => null,
        saveTarget: (id) async => saved.add(id),
      ),
    );
    await openPicker(tester);
    await tester.tap(
      find.byKey(const ValueKey('access_app_com.google.android.youtube')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('access_app_search')),
      'insta',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('access_app_com.google.android.youtube')),
      findsNothing,
    );
    await tester.enterText(find.byKey(const ValueKey('access_app_search')), '');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('access_app_com.google.android.youtube')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('access_save_app')));
    await tester.pumpAndSettle();
    expect(saved, ['com.google.android.youtube']);
  });

  testWidgets('failed save keeps picker open for retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      pickerHost(
        loadApps: () async => [youtube],
        loadTarget: () async => null,
        saveTarget: (_) async {
          calls++;
          if (calls == 1) throw StateError('Native save failed');
        },
      ),
    );
    await openPicker(tester);
    await tester.tap(
      find.byKey(const ValueKey('access_app_com.google.android.youtube')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('access_save_app')));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось сохранить выбор. Попробуй ещё раз.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('access_app_search')), findsOneWidget);
    // Dismiss the SnackBar so the button is not obscured during hit test
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('access_save_app')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('OPEN PICKER'), findsOneWidget);
  });

  testWidgets('cannot save without a real app selection', (tester) async {
    var saves = 0;
    await tester.pumpWidget(
      pickerHost(
        loadApps: () async => const [],
        loadTarget: () async => null,
        saveTarget: (_) async {
          saves++;
        },
      ),
    );
    await openPicker(tester);
    expect(
      find.text('Нет поддерживаемых установленных приложений.'),
      findsOneWidget,
    );
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('access_save_app')),
    );
    expect(saveButton.onPressed, isNull);
    expect(saves, 0);
  });
}
