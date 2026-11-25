import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/focus_experience/focus_screens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:levelup_test/focus_experience/focus_exercises.dart';
import 'package:levelup_test/features/challenge/application/push_up_verification.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('only verified exercises are eligible in current MVP', () {
    final selected = FocusExerciseId.values.toSet();
    final first = nextFocusExercise(selected: selected);
    expect(first?.id, FocusExerciseId.squat);
    expect(first?.ready, true);
    final second = nextFocusExercise(selected: selected, previous: first?.id);
    expect(second?.id, FocusExerciseId.squat);
  });

  test('nothing selected means no task, not a fabricated challenge', () {
    expect(nextFocusExercise(selected: <FocusExerciseId>{}), isNull);
    expect(nextFocusExercise(selected: {FocusExerciseId.pushUp}), isNull);
  });

  test('round-robin works when additional detectors are actually ready', () {
    const available = [
      FocusExercise(
        id: FocusExerciseId.squat,
        nameRu: 'Приседания',
        nameEn: 'Squats',
        nameKk: 'Отырып-тұру',
        target: 5,
        ready: true,
      ),
      FocusExercise(
        id: FocusExerciseId.lunge,
        nameRu: 'Выпады',
        nameEn: 'Lunges',
        nameKk: 'Алға адымдау',
        target: 5,
        ready: true,
      ),
    ];
    const selected = {FocusExerciseId.squat, FocusExerciseId.lunge};
    final first = nextFocusExercise(selected: selected, catalogue: available);
    final second = nextFocusExercise(
      selected: selected,
      previous: first?.id,
      catalogue: available,
    );
    final third = nextFocusExercise(
      selected: selected,
      previous: second?.id,
      catalogue: available,
    );
    expect(first?.id, FocusExerciseId.squat);
    expect(second?.id, FocusExerciseId.lunge);
    expect(third?.id, FocusExerciseId.squat);
  });

  test(
    'a stored push-up selection is usable only in an enabled build',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      final selectable = FocusExercisePreferences(
        store,
        allowPushUpUnlock: true,
      );
      final saved = await selectable.save({FocusExerciseId.pushUp});
      expect(saved, PushUpVerification.unlockEnabled);
      SharedPreferences.resetStatic();
      final reopened = await SharedPreferences.getInstance();
      final preferences = FocusExercisePreferences(
        reopened,
        allowPushUpUnlock: true,
      );
      expect(preferences.selected, {
        PushUpVerification.unlockEnabled
            ? FocusExerciseId.pushUp
            : FocusExerciseId.squat,
      });
      expect(preferences.next()?.id, preferences.selected.single);
      expect(
        FocusExercisePreferences(reopened).next()?.id,
        FocusExerciseId.squat,
      );
    },
  );

  testWidgets('Focus rules accurately show push-up unlock availability', (
    tester,
  ) async {
    Set<FocusExerciseId>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusExerciseSettingsScreen(
          language: 'en',
          initialSelection: const {FocusExerciseId.squat},
          allowPushUpUnlock: true,
          onSave: (selection) => saved = selection,
        ),
      ),
    );

    final squat = find.widgetWithText(CheckboxListTile, 'Squats · 5 reps');
    final pushUp = find.widgetWithText(CheckboxListTile, 'Push-ups · 5 reps');
    expect(tester.widget<CheckboxListTile>(squat).onChanged, isNotNull);
    if (PushUpVerification.unlockEnabled) {
      expect(tester.widget<CheckboxListTile>(pushUp).onChanged, isNotNull);
      await tester.tap(pushUp);
      await tester.pump();
      await tester.tap(squat);
      await tester.pump();
      await tester.tap(find.text('Save'));
      expect(saved, {FocusExerciseId.pushUp});
    } else {
      expect(tester.widget<CheckboxListTile>(pushUp).onChanged, isNull);
      expect(find.text('Unlock unavailable in this build'), findsOneWidget);
    }
  });

  test('Russian task label is grammatically correct', () {
    expect(focusExercises.first.taskLabel('ru'), '5 приседаний');
  });
}
