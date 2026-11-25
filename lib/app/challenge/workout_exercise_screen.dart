import 'package:material_ui/material_ui.dart';

import '../../features/challenge/data/challenge_catalog.dart';
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

  String _tr(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_tr('Тренировка', 'Workout', 'Жаттығу')),
          backgroundColor: FocusStyle.background,
          foregroundColor: FocusStyle.text,
          elevation: 0,
        ),
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _tr(
                          'Выбери своё упражнение',
                          'Choose your exercise',
                          'Жаттығуыңызды таңдаңыз',
                        ),
                        style: const TextStyle(
                          color: FocusStyle.text,
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _tr(
                          'Камера проверит повторы после начала тренировки.',
                          'The camera checks your reps once you start.',
                          'Жаттығу басталған соң камера қайталауларды тексереді.',
                        ),
                        style: const TextStyle(
                          color: FocusStyle.muted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      for (final exercise in focusExercises.where(
                        (exercise) =>
                            isExerciseAvailableForFreeWorkout(exercise.id),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _exerciseCard(exercise),
                        ),
                      const SizedBox(height: 12),
                      _cameraGuidance(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: FocusPrimaryButton(
            text: _tr('Начать тренировку', 'Start Workout', 'Жаттығуды бастау'),
            onPressed: () {
              if (_submitted) return;
              _submitted = true;
              Navigator.of(context).pop(_selected);
            },
          ),
        ),
      ),
    );
  }

  Widget _exerciseCard(FocusExercise exercise) {
    final type = exercise.unlockType;
    final selected = _selected == type;
    final pushUps = type == ExerciseType.pushUp;
    final definition = pushUps
        ? ChallengeCatalog.pushUpFreeWorkout
        : ChallengeCatalog.squatFreeWorkout;
    const radius = BorderRadius.all(Radius.circular(12));
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: FocusStyle.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: selected ? FocusStyle.accent : FocusStyle.border,
            ),
          ),
          child: InkWell(
            key: ValueKey('workout_exercise_${type.name}'),
            borderRadius: radius,
            onTap: () => setState(() => _selected = type),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      pushUps
                          ? Icons.fitness_center_rounded
                          : Icons.directions_walk_rounded,
                      color: selected ? FocusStyle.accent : FocusStyle.muted,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.name(widget.language),
                          style: const TextStyle(
                            color: FocusStyle.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          pushUps
                              ? _tr(
                                  'Из упора лёжа опустись и выпрями руки.',
                                  'Lower from a high plank, then press back up.',
                                  'Тіреніп жатып төмен түсіңіз, сосын қолыңызды жазыңыз.',
                                )
                              : _tr(
                                  'Присядь и вернись в положение стоя.',
                                  'Squat down and return to standing.',
                                  'Отырып, қайта тік тұрыңыз.',
                                ),
                          style: const TextStyle(
                            color: FocusStyle.muted,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            Text(
                              '${definition.targetRepetitions} ${_tr('повторений', 'reps', 'рет')}',
                              style: const TextStyle(color: FocusStyle.text),
                            ),
                            Text(
                              '+${definition.optionalXpReward} XP',
                              style: const TextStyle(
                                color: FocusStyle.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? FocusStyle.accent : FocusStyle.muted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cameraGuidance() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.videocam_outlined, color: FocusStyle.muted, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tr('Положение камеры', 'Camera setup', 'Камераны орналастыру'),
              style: const TextStyle(
                color: FocusStyle.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _selected == ExerciseType.pushUp
                  ? _tr(
                      'Поставь телефон чуть выше пола перед собой. Руки и стопы должны быть видны.',
                      'Place the phone just above the floor, facing you. Keep your hands and feet in frame.',
                      'Телефонды еденнен сәл жоғары, алдыңызға қойыңыз. Қол мен аяқ кадрда көрінсін.',
                    )
                  : _tr(
                      'Встань боком, чтобы в кадре были корпус и ноги.',
                      'Stand sideways with your body and legs in frame.',
                      'Денеңіз бен аяқтарыңыз кадрға сыятындай қырынан тұрыңыз.',
                    ),
              style: const TextStyle(color: FocusStyle.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );
}
