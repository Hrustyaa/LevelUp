import 'package:material_ui/material_ui.dart';

import '../../focus_experience/focus_exercises.dart';
import '../../focus_experience/focus_style.dart';
import '../../models/exercise_type.dart';

/// Collects the Free Workout choice before a session or camera is created.
class WorkoutExerciseScreen extends StatefulWidget {
  const WorkoutExerciseScreen({
    super.key,
    required this.initialExercise,
    required this.language,
  });

  final ExerciseType initialExercise;
  final String language;

  @override
  State<WorkoutExerciseScreen> createState() => _WorkoutExerciseScreenState();
}

class _WorkoutExerciseScreenState extends State<WorkoutExerciseScreen> {
  late ExerciseType _selected = widget.initialExercise;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    String tr(String ru, String en, String kk) =>
        focusTr(widget.language, ru, en, kk);
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            tr('Выбери упражнение', 'Choose exercise', 'Жаттығуды таңда'),
          ),
          backgroundColor: FocusStyle.background,
          foregroundColor: FocusStyle.text,
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final exercise in focusExercises.where(
                          (exercise) =>
                              isExerciseAvailableForFreeWorkout(exercise.id),
                        ))
                          ChoiceChip(
                            label: Text(exercise.name(widget.language)),
                            selected: _selected == exercise.unlockType,
                            onSelected: (_) =>
                                setState(() => _selected = exercise.unlockType),
                            selectedColor: FocusStyle.accent,
                            backgroundColor: FocusStyle.surface,
                            labelStyle: TextStyle(
                              color: _selected == exercise.unlockType
                                  ? FocusStyle.background
                                  : FocusStyle.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            side: BorderSide(
                              color: _selected == exercise.unlockType
                                  ? FocusStyle.accent
                                  : FocusStyle.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                FocusPrimaryButton(
                  text: tr(
                    'Начать тренировку',
                    'Start Workout',
                    'Жаттығуды бастау',
                  ),
                  onPressed: () {
                    if (_submitted) return;
                    _submitted = true;
                    Navigator.of(context).pop(_selected);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
