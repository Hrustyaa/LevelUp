import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/levelup_permissions.dart';
import 'package:levelup_test/screens/levelup_permissions_screen.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

class FakeGateway implements LevelUpPermissionGateway {
  final states = {
    for (final p in LevelUpPermission.values) p: PermissionState.denied,
  };
  final requests = <LevelUpPermission>[];
  bool grant = false, fail = false;
  @override
  Future<Map<LevelUpPermission, PermissionState>> read() async {
    if (fail) throw StateError('test');
    return Map.of(states);
  }

  @override
  Future<void> request(LevelUpPermission p) async {
    requests.add(p);
    if (grant) states[p] = PermissionState.granted;
  }

  @override
  Future<void> openAppSettings() async {}
}

Widget host(
  FakeGateway g, {
  ValueChanged<PermissionsOutcome>? finish,
  LevelUpLanguage lang = LevelUpLanguage.en,
}) => MaterialApp(
  home: LevelUpPermissionsScreen(
    gateway: g,
    language: lang,
    onBack: () {},
    onFinish: finish ?? (_) {},
  ),
);
void main() {
  testWidgets(
    'no permission requested on entry; missing accessibility does not prevent finish',
    (t) async {
      final g = FakeGateway();
      PermissionsOutcome? out;
      await t.pumpWidget(host(g, finish: (v) => out = v));
      await t.pumpAndSettle();
      expect(g.requests, isEmpty);
      await t.tap(find.byKey(const ValueKey('permissions_finish')));
      await t.pumpAndSettle();
      expect(out?.accessibilityGranted, isFalse);
      expect(out?.skipped, isFalse);
    },
  );
  testWidgets('camera state re-read after denial and grant', (t) async {
    final g = FakeGateway();
    await t.pumpWidget(host(g));
    await t.pumpAndSettle();
    final button = find.byKey(const ValueKey('permission_camera'));
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(button, findsOneWidget);
    g.grant = true;
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.text('Granted'), findsOneWidget);
    expect(g.requests, [LevelUpPermission.camera, LevelUpPermission.camera]);
  });
  testWidgets('unavailable features cannot request and skip stays available', (
    t,
  ) async {
    final g = FakeGateway();
    g.states[LevelUpPermission.usage] = PermissionState.unavailable;
    g.states[LevelUpPermission.notifications] = PermissionState.unavailable;
    PermissionsOutcome? out;
    await t.pumpWidget(host(g, finish: (v) => out = v));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('permission_usage')), findsNothing);
    expect(
      find.byKey(const ValueKey('permission_notifications')),
      findsNothing,
    );
    await t.tap(find.byKey(const ValueKey('permissions_skip')));
    await t.pumpAndSettle();
    expect(out?.skipped, isTrue);
    expect(g.requests, isEmpty);
  });
  testWidgets('accessibility dialog cancel never requests', (t) async {
    final g = FakeGateway();
    await t.pumpWidget(host(g));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('permission_accessibility')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(g.requests, isEmpty);
  });
  testWidgets('refresh error does not report grants', (t) async {
    final g = FakeGateway()..fail = true;
    PermissionsOutcome? out;
    await t.pumpWidget(host(g, finish: (v) => out = v));
    await t.pumpAndSettle();
    expect(find.text('Could not check permissions.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('permissions_finish')));
    await t.pumpAndSettle();
    expect(out?.accessibilityGranted, isFalse);
  });
  testWidgets('compact Russian screen fits and can scroll', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(host(FakeGateway(), lang: LevelUpLanguage.ru));
    await t.pumpAndSettle();
    expect(find.text('ШАГ 3 ИЗ 3'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
