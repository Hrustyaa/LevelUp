import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/focus_experience/focus_exercises.dart';

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

  test('Russian task label is grammatically correct', () {
    expect(focusExercises.first.taskLabel('ru'), '5 приседаний');
  });
}
