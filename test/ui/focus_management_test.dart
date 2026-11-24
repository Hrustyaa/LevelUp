import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/screens/levelup_focus_setup_screen.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:material_ui/material_ui.dart';

class _FakeGateway implements DashboardFocusGateway {
  bool enabled = true;
  int disables = 0, enables = 0;
  String? lastTarget;
  @override
  Future<FocusSnapshot> read() async => FocusSnapshot(
    enabled: enabled,
    serviceEnabled: true,
    targets: const ['youtube', 'instagram'],
  );

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

Widget _hostFocusManagement({
  required _FakeGateway gateway,
  FocusSetupDraft? initialDraft,
  ValueChanged<FocusSetupDraft>? onSaveFocusDraft,
  Future<void> Function()? onPauseFocus,
  Future<void> Function()? onEditFocus,
  Future<void> Function()? onEnableFocus,
}) => MaterialApp(
  home: LevelUpHomeScreen(
    gateway: gateway,
    language: DashboardLanguage.en,
    logoAsset: null,
    focusDraft: initialDraft,
    onSaveFocusDraft: onSaveFocusDraft,
    onPauseFocus: onPauseFocus,
    onEditFocus: onEditFocus,
    onEnableFocus: onEnableFocus,
    catalog: const [
      DashboardApp('youtube', 'YouTube'),
      DashboardApp('instagram', 'Instagram'),
      DashboardApp('tiktok', 'TikTok'),
    ],
    draftIds: initialDraft?.packageIds ?? const {'youtube', 'instagram'},
  ),
);

void main() {
  testWidgets('1. Tapping Focus card on Home switches to Focus tab', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(() => t.view.resetPhysicalSize());

    final gateway = _FakeGateway();
    await t.pumpWidget(_hostFocusManagement(gateway: gateway));
    await t.pumpAndSettle();

    // Home focus card header text exists
    final headerTitle = find.text('You’re in focus.');
    expect(headerTitle, findsOneWidget);

    await t.tap(headerTitle);
    await t.pumpAndSettle();

    // Now in Focus Management tab
    expect(find.text('Focus rules'), findsOneWidget);
    expect(find.text('Protected apps'), findsOneWidget);
  });

  testWidgets(
    '2. Focus mode sheet opens, selecting a new mode and tapping Apply calls onSaveFocusDraft',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakeGateway();
      FocusSetupDraft? savedDraft;
      final initial = FocusSetupDraft(
        packageIds: const {'youtube'},
        mode: FocusMode.alwaysOn,
        unlockMinutes: 5,
        sessionMinutes: 60,
      );

      await t.pumpWidget(
        _hostFocusManagement(
          gateway: gateway,
          initialDraft: initial,
          onSaveFocusDraft: (d) => savedDraft = d,
        ),
      );
      await t.pumpAndSettle();

      // Switch to focus tab
      await t.tap(find.text('You’re in focus.'));
      await t.pumpAndSettle();

      // Tap Focus Mode tile
      final modeTile = find.byKey(const ValueKey('rule_mode_tile'));
      await t.ensureVisible(modeTile);
      await t.tap(modeTile);
      await t.pumpAndSettle();

      // Select Session
      expect(
        find.text('Select how LevelUp shields your focus time.'),
        findsOneWidget,
      );
      await t.tap(find.text('Session'));
      await t.pumpAndSettle();

      // Tap Apply
      await t.tap(find.byKey(const ValueKey('sheet_apply_mode')));
      await t.pumpAndSettle();

      expect(savedDraft, isNotNull);
      expect(savedDraft!.mode, FocusMode.timedSession);
    },
  );

  testWidgets(
    '3. Dismissing mode bottom sheet via Cancel does NOT apply changes',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakeGateway();
      FocusSetupDraft? savedDraft;
      final initial = FocusSetupDraft(
        packageIds: const {'youtube'},
        mode: FocusMode.alwaysOn,
        unlockMinutes: 5,
        sessionMinutes: 60,
      );

      await t.pumpWidget(
        _hostFocusManagement(
          gateway: gateway,
          initialDraft: initial,
          onSaveFocusDraft: (d) => savedDraft = d,
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('You’re in focus.'));
      await t.pumpAndSettle();

      final modeTile = find.byKey(const ValueKey('rule_mode_tile'));
      await t.ensureVisible(modeTile);
      await t.tap(modeTile);
      await t.pumpAndSettle();

      await t.tap(find.text('Session'));
      await t.pumpAndSettle();

      // Tap Cancel
      await t.tap(find.byKey(const ValueKey('sheet_cancel_mode')));
      await t.pumpAndSettle();

      expect(savedDraft, isNull);
    },
  );

  testWidgets('4. Temporary access sheet updates unlockMinutes on Apply', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.0;
    addTearDown(() => t.view.resetPhysicalSize());

    final gateway = _FakeGateway();
    FocusSetupDraft? savedDraft;
    final initial = FocusSetupDraft(
      packageIds: const {'youtube'},
      mode: FocusMode.alwaysOn,
      unlockMinutes: 5,
      sessionMinutes: 60,
    );

    await t.pumpWidget(
      _hostFocusManagement(
        gateway: gateway,
        initialDraft: initial,
        onSaveFocusDraft: (d) => savedDraft = d,
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.text('You’re in focus.'));
    await t.pumpAndSettle();

    final accessTile = find.byKey(const ValueKey('rule_access_tile'));
    await t.ensureVisible(accessTile);
    await t.tap(accessTile);
    await t.pumpAndSettle();

    expect(
      find.text(
        'A verified challenge grants 5 minutes. Other durations are saved as a draft.',
      ),
      findsOneWidget,
    );
    expect(find.text('Save draft'), findsOneWidget);
    await t.tap(find.text('15 minutes'));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const ValueKey('sheet_apply_access')));
    await t.pumpAndSettle();

    expect(savedDraft, isNotNull);
    expect(savedDraft!.unlockMinutes, 15);
  });

  testWidgets(
    '5. Session duration sheet updates sessionMinutes when mode is timedSession',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakeGateway();
      FocusSetupDraft? savedDraft;
      final initial = FocusSetupDraft(
        packageIds: const {'youtube'},
        mode: FocusMode.timedSession,
        unlockMinutes: 5,
        sessionMinutes: 30,
      );

      await t.pumpWidget(
        _hostFocusManagement(
          gateway: gateway,
          initialDraft: initial,
          onSaveFocusDraft: (d) => savedDraft = d,
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('You’re in focus.'));
      await t.pumpAndSettle();

      final durationTile = find.byKey(const ValueKey('rule_duration_tile'));
      await t.ensureVisible(durationTile);
      expect(durationTile, findsOneWidget);
      await t.tap(durationTile);
      await t.pumpAndSettle();

      // Select 60 minutes
      await t.tap(find.text('60 minutes'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('sheet_apply_duration')));
      await t.pumpAndSettle();

      expect(savedDraft, isNotNull);
      expect(savedDraft!.sessionMinutes, 60);
    },
  );

  testWidgets(
    '6. Schedule sheet updates weekdays and minutes when mode is customSchedule',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakeGateway();
      FocusSetupDraft? savedDraft;
      final initial = FocusSetupDraft(
        packageIds: const {'youtube'},
        mode: FocusMode.customSchedule,
        unlockMinutes: 5,
        sessionMinutes: 60,
        weekdays: const {1, 2, 3, 4, 5},
      );

      await t.pumpWidget(
        _hostFocusManagement(
          gateway: gateway,
          initialDraft: initial,
          onSaveFocusDraft: (d) => savedDraft = d,
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('You’re in focus.'));
      await t.pumpAndSettle();

      final scheduleTile = find.byKey(const ValueKey('rule_schedule_tile'));
      await t.ensureVisible(scheduleTile);
      expect(scheduleTile, findsOneWidget);
      await t.tap(scheduleTile);
      await t.pumpAndSettle();

      // Toggle Saturday (Sat)
      await t.tap(find.text('Sat'));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const ValueKey('sheet_apply_schedule')));
      await t.pumpAndSettle();

      expect(savedDraft, isNotNull);
      expect(savedDraft!.weekdays.contains(6), isTrue);
    },
  );

  testWidgets(
    '7. App details sheet opens on tapping protected app and allows removing it',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.0;
      addTearDown(() => t.view.resetPhysicalSize());

      final gateway = _FakeGateway();
      FocusSetupDraft? savedDraft;
      final initial = FocusSetupDraft(
        packageIds: const {'youtube', 'instagram'},
        mode: FocusMode.alwaysOn,
        unlockMinutes: 5,
        sessionMinutes: 60,
      );

      await t.pumpWidget(
        _hostFocusManagement(
          gateway: gateway,
          initialDraft: initial,
          onSaveFocusDraft: (d) => savedDraft = d,
        ),
      );
      await t.pumpAndSettle();

      await t.tap(find.text('You’re in focus.'));
      await t.pumpAndSettle();

      // Scroll down to Protected apps section
      final protectedAppsHeader = find.text('Protected apps');
      await t.scrollUntilVisible(
        protectedAppsHeader,
        100,
        scrollable: find.byType(Scrollable).first,
      );

      // Tap on YouTube in the protected apps list (last matching YouTube widget)
      final youtubeText = find.text('YouTube');
      await t.tap(youtubeText.last);
      await t.pumpAndSettle();

      // App details sheet is displayed
      expect(find.text('Remove from protected apps'), findsOneWidget);
      await t.tap(find.text('Remove from protected apps'));
      await t.pumpAndSettle();

      expect(savedDraft, isNotNull);
      expect(savedDraft!.packageIds.contains('youtube'), isFalse);
      expect(savedDraft!.packageIds.contains('instagram'), isTrue);
    },
  );
}
