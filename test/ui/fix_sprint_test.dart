import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/android_app_catalog.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/data/levelup_permissions.dart';
import 'package:levelup_test/screens/app_permissions_screen.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:levelup_test/screens/manage_apps_screen.dart';
import 'package:material_ui/material_ui.dart';

class _FakeControlGateway implements DashboardFocusGateway {
  bool enabled = false;
  bool serviceEnabled = true;
  String? target = 'com.google.android.youtube';
  int enables = 0;
  int disables = 0;
  bool failNext = false;

  @override
  Future<FocusSnapshot> read() async {
    if (failNext) throw StateError('Simulated channel failure');
    return FocusSnapshot(
      enabled: enabled && serviceEnabled,
      serviceEnabled: serviceEnabled,
      targets: target != null ? [target!] : const [],
    );
  }

  @override
  Future<void> enable({String? target}) async {
    if (failNext) throw StateError('Simulated channel failure');
    if (!serviceEnabled) {
      throw StateError('SERVICE_DISABLED');
    }
    this.target = target ?? this.target;
    enables++;
    enabled = true;
  }

  @override
  Future<void> disable() async {
    if (failNext) throw StateError('Simulated channel failure');
    disables++;
    enabled = false;
  }
}

class _FakePermissionGateway implements LevelUpPermissionGateway {
  Map<LevelUpPermission, PermissionState> states = {
    LevelUpPermission.accessibility: PermissionState.denied,
    LevelUpPermission.camera: PermissionState.denied,
    LevelUpPermission.usage: PermissionState.denied,
    LevelUpPermission.notifications: PermissionState.denied,
  };
  int requests = 0;
  int appSettingsOpened = 0;

  @override
  Future<Map<LevelUpPermission, PermissionState>> read() async => states;

  @override
  Future<void> request(LevelUpPermission permission) async {
    requests++;
    states[permission] = PermissionState.granted;
  }

  @override
  Future<void> openAppSettings() async {
    appSettingsOpened++;
  }
}

void main() {
  testWidgets('1. Enable Focus works and updates active status', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(() => t.view.resetPhysicalSize());

    final gateway = _FakeControlGateway();
    gateway.enabled = false;
    gateway.serviceEnabled = true;

    await t.pumpWidget(
      MaterialApp(
        home: LevelUpHomeScreen(
          gateway: gateway,
          catalog: const [
            DashboardApp('com.google.android.youtube', 'YouTube'),
          ],
          draftIds: const {'com.google.android.youtube'},
          onEnableFocus: () async {
            await gateway.enable(target: 'com.google.android.youtube');
          },
        ),
      ),
    );
    await t.pumpAndSettle();

    // Inactive status initially
    expect(find.text('Focus off'), findsOneWidget);

    // Tap quick enable button on Home
    final enableBtn = find.byKey(const ValueKey('home_enable'));
    expect(enableBtn, findsOneWidget);
    await t.tap(enableBtn);
    await t.pumpAndSettle();

    expect(gateway.enables, 1);
    expect(find.text('Focus active'), findsOneWidget);
  });

  testWidgets(
    '2. Turn off Focus works immediately without exercise challenge',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakeControlGateway();
      gateway.enabled = true;
      gateway.serviceEnabled = true;

      await t.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: gateway,
            catalog: const [
              DashboardApp('com.google.android.youtube', 'YouTube'),
            ],
            draftIds: const {'com.google.android.youtube'},
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Focus active'), findsOneWidget);

      // Tap Turn off Focus on home card
      final offBtn = find.byKey(const ValueKey('home_off'));
      expect(offBtn, findsOneWidget);
      await t.tap(offBtn);
      await t.pumpAndSettle();

      expect(gateway.disables, 1);
      expect(find.text('Focus off'), findsOneWidget);
    },
  );

  testWidgets('3. Focus tab Enable button calls onEnableFocus and refreshes', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(() => t.view.resetPhysicalSize());

    final gateway = _FakeControlGateway();
    gateway.enabled = false;
    gateway.serviceEnabled = true;

    await t.pumpWidget(
      MaterialApp(
        home: LevelUpHomeScreen(
          gateway: gateway,
          catalog: const [
            DashboardApp('com.google.android.youtube', 'YouTube'),
          ],
          draftIds: const {'com.google.android.youtube'},
          onEnableFocus: () async {
            await gateway.enable(target: 'com.google.android.youtube');
          },
        ),
      ),
    );
    await t.pumpAndSettle();

    // Switch to Focus tab via bottom navigation
    await t.tap(find.text('Focus'));
    await t.pumpAndSettle();

    final focusEnable = find.byKey(const ValueKey('focus_enable'));
    expect(focusEnable, findsOneWidget);
    await t.tap(focusEnable);
    await t.pumpAndSettle();

    expect(gateway.enables, 1);
    expect(find.text('Turn off Focus'), findsWidgets);
  });

  testWidgets(
    '4. ManageAppsScreen loads apps, allows toggling and saves selection',
    (t) async {
      Set<String>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: ManageAppsScreen(
            loadApps: () async => const [
              SelectableApp(
                name: 'YouTube',
                packageId: 'com.google.android.youtube',
                suggested: true,
              ),
              SelectableApp(
                name: 'Instagram',
                packageId: 'com.instagram.android',
                suggested: true,
              ),
            ],
            initialSelectedIds: const {'com.google.android.youtube'},
            onSave: (ids) => saved = ids,
          ),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Manage protected apps'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);

      // Toggle Instagram
      await t.tap(find.text('Instagram'));
      await t.pumpAndSettle();

      // Tap Save changes
      await t.tap(find.text('Save changes'));
      await t.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.contains('com.google.android.youtube'), isTrue);
      expect(saved!.contains('com.instagram.android'), isTrue);
    },
  );

  testWidgets(
    '5. AppPermissionsScreen displays real permissions and handles grant action',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakePermissionGateway();
      await t.pumpWidget(
        MaterialApp(home: AppPermissionsScreen(gateway: gateway)),
      );
      await t.pumpAndSettle();

      expect(find.text('App permissions'), findsOneWidget);
      expect(find.text('Accessibility Service'), findsOneWidget);
      expect(find.text('Usage Access (Screen Time)'), findsOneWidget);
      expect(find.text('Camera Access'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);

      // Grant notifications permission (index 3)
      final grantButtons = find.widgetWithText(FilledButton, 'Grant access');
      expect(grantButtons, findsWidgets);

      await t.tap(grantButtons.at(3));
      await t.pumpAndSettle();

      expect(gateway.requests, 1);
    },
  );

  testWidgets(
    '6. MethodChannel failure during read handles gracefully without crashing',
    (t) async {
      final gateway = _FakeControlGateway();
      gateway.failNext = true;

      await t.pumpWidget(
        MaterialApp(
          home: LevelUpHomeScreen(
            gateway: gateway,
            catalog: const [
              DashboardApp('com.google.android.youtube', 'YouTube'),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();

      // Verify error state is shown gracefully
      expect(find.text('Status unavailable'), findsOneWidget);
    },
  );
}
