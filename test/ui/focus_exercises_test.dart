import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/focus_experience/focus_screens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:levelup_test/focus_experience/focus_exercises.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('only verified exercises are eligible in current MVP', () {
    final selected = FocusExerciseId.values.toSet();
    final first = nextFocusExercise(selected: selected);
    expect(first?.id, FocusExerciseId.squat);
    expect(first?.ready, true);
    final second = nextFocusExercise(selected: selected, previous: first?.id);
    expect(second?.id, FocusExerciseId.pushUp);
    expect(second?.ready, true);
    expect(
      nextFocusExercise(selected: selected, previous: second?.id)?.id,
      FocusExerciseId.squat,
    );
  });

  test('nothing selected means no task, not a fabricated challenge', () {
    expect(nextFocusExercise(selected: <FocusExerciseId>{}), isNull);
    expect(nextFocusExercise(selected: {FocusExerciseId.lunge}), isNull);
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
    'a saved push-up unlock choice survives SharedPreferences reload',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      final store = await SharedPreferences.getInstance();
      expect(
        await FocusExercisePreferences(store).save({FocusExerciseId.pushUp}),
        isTrue,
      );
      SharedPreferences.resetStatic();
      final reopened = await SharedPreferences.getInstance();
      final preferences = FocusExercisePreferences(reopened);
      expect(preferences.selected, {FocusExerciseId.pushUp});
      expect(preferences.next()?.id, FocusExerciseId.pushUp);
      expect(
        FocusExercisePreferences(reopened, supportsPushUps: false).next()?.id,
        FocusExerciseId.squat,
      );
      expect(preferences.next()?.id, FocusExerciseId.pushUp);
    },
  );

  testWidgets('Focus rules enable both supported unlock exercises', (
    tester,
  ) async {
    Set<FocusExerciseId>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusExerciseSettingsScreen(
          language: 'en',
          initialSelection: const {FocusExerciseId.squat},
          onSave: (selection) => saved = selection,
        ),
      ),
    );

    final squat = find.widgetWithText(CheckboxListTile, 'Squats · 5 reps');
    final pushUp = find.widgetWithText(CheckboxListTile, 'Push-ups · 5 reps');
    expect(tester.widget<CheckboxListTile>(squat).onChanged, isNotNull);
    expect(tester.widget<CheckboxListTile>(pushUp).onChanged, isNotNull);
    await tester.tap(pushUp);
    await tester.pump();
    await tester.tap(squat);
    await tester.pump();
    await tester.tap(find.text('Save'));
    expect(saved, {FocusExerciseId.pushUp});
  });

  test('Russian task label is grammatically correct', () {
    expect(focusExercises.first.taskLabel('ru'), '5 приседаний');
  });
}
