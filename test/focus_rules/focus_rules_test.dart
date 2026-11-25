import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/screens/levelup_focus_setup_screen.dart';
import 'package:levelup_test/focus_rules/focus_rules_panel.dart';
import 'package:levelup_test/focus_rules/focus_rules_policy.dart';

FocusSetupDraft baseDraft() => FocusSetupDraft(
  packageIds: {'com.example.video'},
  mode: FocusMode.alwaysOn,
  unlockMinutes: 5,
);

Widget host({
  required FocusSetupDraft draft,
  Future<void> Function(FocusSetupDraft)? onSave,
  Future<void> Function()? onDisable,
  FocusCapabilities capabilities = const FocusCapabilities(),
  bool? focusActive = false,
}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LevelUpFocusRulesPanel(
            language: DashboardLanguage.ru,
            draft: draft,
            capabilities: capabilities,
            focusActive: focusActive,
            onSaveDraft: onSave,
            onDisableFocus: onDisable,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('draft schedule validates days and chronological local clock', () {
    final draft = baseDraft().copyWith(
      mode: FocusMode.customSchedule,
      weekdays: {1, 3, 5},
      startMinute: 540,
      endMinute: 1050,
    );
    expect(FocusRulesPolicy.validSchedule(draft), isTrue);
    expect(FocusRulesPolicy.canSaveDraft(draft), isTrue);
    expect(
      FocusRulesPolicy.validSchedule(draft.copyWith(endMinute: 540)),
      isFalse,
    );
    expect(
      FocusRulesPolicy.validSchedule(draft.copyWith(endMinute: 500)),
      isFalse,
    );
    expect(
      FocusRulesPolicy.validSchedule(draft.copyWith(weekdays: <int>{})),
      isFalse,
    );
    expect(
      FocusRulesPolicy.validSchedule(draft.copyWith(weekdays: {8})),
      isFalse,
    );
    expect(FocusRulesPolicy.clock(480), '08:00');
    expect(FocusRulesPolicy.clock(1115), '18:35');
  });

  test('unsupported modes and access are draft-only', () {
    final c = const FocusCapabilities();
    final draft = baseDraft();
    expect(FocusRulesPolicy.eligibleForActivation(draft, c), isTrue);
    expect(
      FocusRulesPolicy.eligibleForActivation(
        draft.copyWith(mode: FocusMode.timedSession),
        c,
      ),
      isFalse,
    );
    expect(
      FocusRulesPolicy.eligibleForActivation(
        draft.copyWith(mode: FocusMode.customSchedule),
        c,
      ),
      isFalse,
    );
    expect(
      FocusRulesPolicy.eligibleForActivation(
        draft.copyWith(unlockMinutes: 10),
        c,
      ),
      isFalse,
    );
    expect(
      FocusRulesPolicy.eligibleForActivation(
        draft.copyWith(packageIds: {'one', 'two'}),
        c,
      ),
      isFalse,
    );
    expect(
      FocusRulesPolicy.canSaveDraft(
        draft.copyWith(packageIds: <String>{}, mode: FocusMode.customSchedule),
      ),
      isTrue,
    );
  });

  testWidgets('changing mode without Save does not call persistence', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        draft: baseDraft(),
        onSave: (_) async {
          calls++;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focus_rules_mode_row')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('focus_rules_mode_timedSession')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('focus_rules_session_30')),
      findsOneWidget,
    );
    expect(calls, 0);
    // Tap outside bottom sheet (or barrier) to dismiss modal bottom sheet
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('До ручного отключения'), findsOneWidget);
  });

  testWidgets('saving session mode passes the same draft with changed fields', (
    tester,
  ) async {
    FocusSetupDraft? saved;
    await tester.pumpWidget(
      host(
        draft: baseDraft(),
        onSave: (next) async {
          saved = next;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focus_rules_mode_row')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('focus_rules_mode_timedSession')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_rules_session_30')));
    await tester.tap(find.byKey(const ValueKey('focus_rules_save')));
    await tester.pumpAndSettle();
    expect(saved?.mode, FocusMode.timedSession);
    expect(saved?.sessionMinutes, 30);
    expect(saved?.unlockMinutes, 5);
    expect(saved?.packageIds, {'com.example.video'});
  });

  testWidgets('custom schedule allows compact 24h clock editing', (
    tester,
  ) async {
    FocusSetupDraft? saved;
    await tester.pumpWidget(
      host(
        draft: baseDraft(),
        onSave: (next) async {
          saved = next;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focus_rules_mode_row')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('focus_rules_mode_customSchedule')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_rules_day_7')));
    await tester.tap(find.byKey(const ValueKey('focus_rules_start')));
    await tester.pumpAndSettle();
    // A nested compact picker, rather than the stock full-screen time dialog.
    expect(find.byKey(const ValueKey('focus_clock_hour')), findsOneWidget);
    expect(find.byKey(const ValueKey('focus_clock_minute')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('focus_clock_confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_rules_save')));
    await tester.pumpAndSettle();
    expect(saved?.mode, FocusMode.customSchedule);
    expect(saved?.weekdays.contains(7), true);
    expect(saved?.startMinute, 540);
    expect(saved?.endMinute, 1020);
  });

  testWidgets('temporary access is only saved on confirmation', (tester) async {
    FocusSetupDraft? saved;
    await tester.pumpWidget(
      host(
        draft: baseDraft(),
        onSave: (next) async {
          saved = next;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focus_rules_access_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_rules_access_10')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('Сохранить черновик'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('focus_rules_save')));
    await tester.pumpAndSettle();
    expect(saved?.unlockMinutes, 10);
    expect(saved?.mode, FocusMode.alwaysOn);
  });

  testWidgets('save failure stays open and shows error', (tester) async {
    await tester.pumpWidget(
      host(
        draft: baseDraft(),
        onSave: (_) async {
          throw StateError('write failed');
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focus_rules_mode_row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('focus_rules_save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Не удалось сохранить изменения. Попробуй ещё раз.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('focus_rules_save')), findsOneWidget);
  });

  testWidgets('active Focus has an independent voluntary off action', (
    tester,
  ) async {
    var disabled = 0;
    await tester.pumpWidget(
      host(
        draft: baseDraft(),
        onDisable: () async {
          disabled++;
        },
        focusActive: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('focus_rules_disable')));
    await tester.pump();
    expect(disabled, 1);
  });
}
