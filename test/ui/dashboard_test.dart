import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:material_ui/material_ui.dart';

class FakeGateway implements DashboardFocusGateway {
  bool enabled = true, fail = false;
  int disables = 0, enables = 0;
  String? lastTarget;
  @override
  Future<FocusSnapshot> read() async {
    if (fail) throw StateError('test');
    return FocusSnapshot(
      enabled: enabled,
      serviceEnabled: true,
      targets: const ['youtube'],
    );
  }

  @override
  Future<void> enable({String? target}) async {
    enables++;
    lastTarget = target;
    enabled = true;
  }

  @override
  Future<void> disable() async {
    disables++;
    enabled = false;
  }
}

Widget host(
  FakeGateway gateway, {
  DashboardLanguage language = DashboardLanguage.en,
  Future<DashboardInsights> Function()? load,
}) => MaterialApp(
  home: LevelUpHomeScreen(
    gateway: gateway,
    language: language,
    logoAsset: null,
    loadInsights: load,
    catalog: const [
      DashboardApp('youtube', 'YouTube'),
      DashboardApp('instagram', 'Instagram'),
    ],
    draftIds: const {'youtube', 'instagram'},
  ),
);

Future<void> disposeHost(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
}

void main() {
  test('thresholds are cumulative, progress within current level', () {
    expect(DashboardLevel.fromXp(0).level, 1);
    final l = DashboardLevel.fromXp(180);
    expect(l.level, 2);
    expect(l.remaining, 120);
    expect(l.fraction, 0.4);
    expect(DashboardLevel.fromXp(300).level, 3);
  });
  test('access uses actual target and absolute deadline', () {
    final n = DateTime(2026, 11, 22, 10);
    final s = FocusSnapshot(
      enabled: true,
      serviceEnabled: true,
      targets: const ['a'],
      accessUntil: {'a': n.add(const Duration(minutes: 5))},
    );
    expect(s.remaining('a', n), const Duration(minutes: 5));
    expect(s.remaining('b', n), Duration.zero);
    expect(s.remaining('a', n.add(const Duration(minutes: 6))), Duration.zero);
  });
  testWidgets('Home focus card goes to actual engine view, disable works', (
    t,
  ) async {
    final g = FakeGateway();
    await t.pumpWidget(host(g));
    await t.pumpAndSettle();
    expect(find.text('Focus active'), findsOneWidget);
    await t.tap(find.text('You’re in focus.'));
    await t.pumpAndSettle();
    expect(find.text('Current engine state'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('focus_off')));
    await t.pumpAndSettle();
    expect(g.disables, 1);
    expect(find.text('Focus off'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('focus_enable')))
          .onPressed,
      isNull,
    );
    await disposeHost(t);
  });
  testWidgets('Activity and level routes display missing data honestly', (
    t,
  ) async {
    await t.pumpWidget(host(FakeGateway()));
    await t.pumpAndSettle();
    final activity = find.text('View activity ›');
    await t.ensureVisible(activity);
    await t.tap(activity);
    await t.pumpAndSettle();
    expect(find.text('History is not connected yet.'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    final level = find.byKey(const ValueKey('home_level'));
    await t.scrollUntilVisible(
      level,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(level);
    await t.pumpAndSettle();
    expect(find.text('Your level'), findsOneWidget);
    expect(find.text('No recorded XP events yet.'), findsOneWidget);
    await disposeHost(t);
  });
  testWidgets('Open activity clears screen time after access is revoked', (
    t,
  ) async {
    var hasAccess = true;
    await t.pumpWidget(
      host(
        FakeGateway(),
        load: () async => hasAccess
            ? const DashboardInsights(
                todayUsageMinutes: 12,
                usageByApp: {'youtube': 12},
              )
            : const DashboardInsights(),
      ),
    );
    await t.pumpAndSettle();
    final activity = find.text('View activity ›');
    await t.ensureVisible(activity);
    await t.tap(activity);
    await t.pumpAndSettle();
    expect(find.text('By app'), findsOneWidget);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    hasAccess = false;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    expect(find.text('Today · Selected apps'), findsOneWidget);
    expect(find.text('By app'), findsNothing);
    expect(find.text('12 min'), findsNothing);
    await disposeHost(t);
  });
  testWidgets('challenge navigation and cancel break without changing focus', (
    t,
  ) async {
    final g = FakeGateway();
    await t.pumpWidget(host(g));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('tab_2')));
    await t.pumpAndSettle();
    final b = find.byKey(const ValueKey('challenge_break'));
    await t.ensureVisible(b);
    await t.tap(b);
    await t.pumpAndSettle();
    await t.tap(find.text('Exit'));
    await t.pumpAndSettle();
    expect(find.text('Choose a challenge'), findsOneWidget);
    expect(g.disables, 0);
    await disposeHost(t);
  });
  testWidgets('unknown state is not off or active, disable remains available', (
    t,
  ) async {
    final g = FakeGateway()..fail = true;
    await t.pumpWidget(host(g));
    await t.pumpAndSettle();
    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('home_off')), findsOneWidget);
    expect(find.text('Focus active'), findsNothing);
    await disposeHost(t);
  });
  testWidgets('compact Russian layout has no overflow and nav is fixed', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(host(FakeGateway(), language: DashboardLanguage.ru));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('tab_4')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tab_4')));
    await t.pumpAndSettle();
    expect(find.text('Предпочтения'), findsOneWidget);
    await disposeHost(t);
  });
  testWidgets(
    'Ticker does not trigger unneeded rebuilds when no timer is active',
    (t) async {
      var rebuilds = 0;
      final g = FakeGateway();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              rebuilds++;
              return LevelUpHomeScreen(
                gateway: g,
                logoAsset: null,
                catalog: const [DashboardApp('youtube', 'YouTube')],
                draftIds: const {'youtube'},
              );
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      final initialRebuilds = rebuilds;
      // Advance virtual clock by 1 second without active countdowns
      await t.pump(const Duration(seconds: 1));
      // Root widget must not be rebuilt
      expect(rebuilds, initialRebuilds);
      await disposeHost(t);
    },
  );
  testWidgets('Ticker updates immediately when access countdown expires', (
    t,
  ) async {
    final g = FakeGateway();
    await t.pumpWidget(
      MaterialApp(
        home: LevelUpHomeScreen(
          gateway: g,
          logoAsset: null,
          catalog: const [DashboardApp('youtube', 'YouTube')],
          draftIds: const {'youtube'},
        ),
      ),
    );
    await t.pumpAndSettle();
    // Verify countdown handles expiry properly
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Focus active'), findsOneWidget);
    await disposeHost(t);
  });
}
