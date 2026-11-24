import 'package:shared_preferences/shared_preferences.dart';

import '../test_kit/squat_counter.dart';

/// Exercise catalogue used by Focus Gate. This file contains NO camera/ML logic.
/// `ready` is a product capability, not a label that the UI may toggle.
/// Enabling new exercises requires a verified detector from the native team.
enum FocusExerciseId { squat, pushUp, lunge, jumpingJack, plank }

class FocusExercise {
  const FocusExercise({
    required this.id,
    required this.nameRu,
    required this.nameEn,
    required this.nameKk,
    required this.target,
    required this.ready,
    this.isTimed = false,
  });

  final FocusExerciseId id;
  final String nameRu, nameEn, nameKk;
  final int target;
  final bool ready;
  final bool isTimed;

  String name(String lang) => switch (lang) {
    'en' => nameEn,
    'kk' => nameKk,
    _ => nameRu,
  };

  String taskLabel(String lang) {
    final units = switch (lang) {
      'en' => isTimed ? 'seconds' : 'reps',
      'kk' => isTimed ? 'секунд' : 'рет',
      _ => isTimed ? 'секунд' : 'повторений',
    };
    if (lang == 'ru' && id == FocusExerciseId.squat) {
      return '$target приседаний';
    }
    return '${name(lang)} · $target $units';
  }
}

/// Keep the values in sync with the *verified*, not planned, native detectors.
const focusExercises = <FocusExercise>[
  FocusExercise(
    id: FocusExerciseId.squat,
    nameRu: 'Приседания',
    nameEn: 'Squats',
    nameKk: 'Отырып-тұру',
    target: SquatCounter.goal,
    ready: true,
  ),
  FocusExercise(
    id: FocusExerciseId.pushUp,
    nameRu: 'Отжимания',
    nameEn: 'Push-ups',
    nameKk: 'Қолды бүгіп-жазу',
    target: 5,
    ready: false,
  ),
  FocusExercise(
    id: FocusExerciseId.lunge,
    nameRu: 'Выпады',
    nameEn: 'Lunges',
    nameKk: 'Алға адымдау',
    target: 5,
    ready: false,
  ),
  FocusExercise(
    id: FocusExerciseId.jumpingJack,
    nameRu: 'Джампинг-джеки',
    nameEn: 'Jumping jacks',
    nameKk: 'Секіріп жаттығу',
    target: 5,
    ready: false,
  ),
  FocusExercise(
    id: FocusExerciseId.plank,
    nameRu: 'Планка',
    nameEn: 'Plank',
    nameKk: 'Планка',
    target: 20,
    ready: false,
    isTimed: true,
  ),
];

/// Deterministic rotation, with no fake availability. If nothing is ready,
/// returns null. The Focus UI must offer a safe way to disable Focus.
FocusExercise? nextFocusExercise({
  required Set<FocusExerciseId> selected,
  FocusExerciseId? previous,
  List<FocusExercise> catalogue = focusExercises,
}) {
  final eligible = catalogue
      .where((exercise) => exercise.ready && selected.contains(exercise.id))
      .toList(growable: false);
  if (eligible.isEmpty) return null;
  final index = eligible.indexWhere((exercise) => exercise.id == previous);
  return eligible[(index + 1) % eligible.length];
}

class FocusExercisePreferences {
  const FocusExercisePreferences(this.preferences);

  final SharedPreferences preferences;
  static const _selectionKey = 'levelup.focus.exercise_selection';
  static const _lastAssignmentKey = 'levelup.focus.last_exercise';

  Set<FocusExerciseId> get selected {
    final saved = preferences.getStringList(_selectionKey) ?? const [];
    final enabled = {
      for (final exercise in focusExercises)
        if (exercise.ready && saved.contains(exercise.id.name)) exercise.id,
    };
    if (enabled.isNotEmpty) return enabled;
    return {
      if (nextFocusExercise(selected: FocusExerciseId.values.toSet())
          case final first?)
        first.id,
    };
  }

  Future<bool> save(Set<FocusExerciseId> selection) {
    final ready = [
      for (final exercise in focusExercises)
        if (exercise.ready && selection.contains(exercise.id)) exercise.id.name,
    ];
    if (ready.isEmpty) return Future.value(false);
    return preferences.setStringList(_selectionKey, ready);
  }

  FocusExercise? next() {
    final last = preferences.getString(_lastAssignmentKey);
    return nextFocusExercise(
      selected: selected,
      previous: FocusExerciseId.values
          .where((id) => id.name == last)
          .firstOrNull,
    );
  }

  Future<bool> recordAssignment(FocusExerciseId id) =>
      preferences.setString(_lastAssignmentKey, id.name);
}
