import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/android_app_catalog.dart';
import 'package:levelup_test/screens/levelup_focus_setup_screen.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';

const apps = [
  SelectableApp(packageId: 'com.google.android.youtube', name: 'YouTube'),
];
Widget host({
  List<SelectableApp> selected = apps,
  FocusSetupDraft? initial,
  ValueChanged<FocusSetupDraft>? onContinue,
  VoidCallback? onSkip,
  VoidCallback? onEdit,
  LevelUpLanguage language = LevelUpLanguage.en,
}) => MaterialApp(
  home: LevelUpFocusSetupScreen(
    selectedApps: selected,
    initialDraft: initial,
    language: language,
    onContinue: onContinue ?? (_) {},
    onBack: () {},
    onSkip: onSkip ?? () {},
    onEditApps: onEdit,
  ),
);

void main() {
  test('draft validation and capability gates', () {
    final d = FocusSetupDraft(packageIds: {'youtube'});
    expect(d.isValid, isTrue);
    expect(const FocusCapabilities().supports(d), isTrue);
    expect(
      const FocusCapabilities().supports(d.copyWith(unlockMinutes: 10)),
      isFalse,
    );
    expect(
      const FocusCapabilities(
        configurableAccess: true,
      ).supports(d.copyWith(unlockMinutes: 10)),
      isTrue,
    );
    expect(
      const FocusCapabilities().supports(
        d.copyWith(packageIds: {'youtube', 'instagram'}),
      ),
      isFalse,
    );
    expect(d.copyWith(packageIds: {}).isValid, isFalse);
    expect(
      d.copyWith(mode: FocusMode.customSchedule, weekdays: {}).isValid,
      isFalse,
    );
    expect(
      d
          .copyWith(
            mode: FocusMode.customSchedule,
            startMinute: 1000,
            endMinute: 200,
          )
          .isValid,
      isFalse,
    );
    expect(d.copyWith(mode: FocusMode.customSchedule).isValid, isTrue);
    expect(
      d.copyWith(mode: FocusMode.timedSession).toJson()['mode'],
      'timedSession',
    );
  });
  testWidgets('session and temporary access settings reach parent', (t) async {
    t.view.physicalSize = const Size(600, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    FocusSetupDraft? result;
    await t.pumpWidget(host(onContinue: (d) => result = d));
    await t.pumpAndSettle();

    final mode = find.byKey(const ValueKey('mode_timedSession'));
    await t.tap(mode);
    await t.pumpAndSettle();

    final scrollable = find.byType(Scrollable);
    final session = find.byKey(const ValueKey('session_30'));
    await t.scrollUntilVisible(session, 100, scrollable: scrollable);
    await t.tap(session);
    await t.pumpAndSettle();

    final access = find.byKey(const ValueKey('access_10'));
    await t.scrollUntilVisible(access, 100, scrollable: scrollable);
    await t.tap(access);
    await t.pumpAndSettle();

    final continueBtn = find.byKey(const ValueKey('focus_continue'));
    await t.scrollUntilVisible(continueBtn, 100, scrollable: scrollable);
    await t.tap(continueBtn);
    await t.pumpAndSettle();

    expect(result?.mode, FocusMode.timedSession);
    expect(result?.sessionMinutes, 30);
    expect(result?.unlockMinutes, 10);
  });
  testWidgets('no apps disables continue but skip remains available', (
    t,
  ) async {
    bool skipped = false;
    await t.pumpWidget(host(selected: const [], onSkip: () => skipped = true));
    expect(
      t
          .widget<FilledButton>(find.byKey(const ValueKey('focus_continue')))
          .onPressed,
      isNull,
    );
    await t.tap(find.byKey(const ValueKey('focus_skip')));
    expect(skipped, isTrue);
  });
  testWidgets('edit callback and Russian copy', (t) async {
    bool edited = false;
    await t.pumpWidget(
      host(language: LevelUpLanguage.ru, onEdit: () => edited = true),
    );
    expect(find.text('ШАГ 2 ИЗ 3'), findsOneWidget);
    await t.tap(find.text('Изменить'));
    expect(edited, isTrue);
  });
  testWidgets('compact screen with schedule can scroll to actions', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      host(
        initial: FocusSetupDraft(
          packageIds: {apps.first.packageId},
          mode: FocusMode.customSchedule,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('focus_continue')), findsOneWidget);
  });
}
