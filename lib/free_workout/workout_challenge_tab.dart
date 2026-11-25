import 'package:material_ui/material_ui.dart';

import '../features/challenge/data/challenge_catalog.dart';
import '../focus_experience/focus_exercises.dart';
import '../focus_experience/focus_style.dart';
import '../models/exercise_type.dart';
import 'workout_session.dart';

class WorkoutChallengeTab extends StatelessWidget {
  const WorkoutChallengeTab({
    super.key,
    required this.language,
    this.onOpenWorkout,
  });

  final String language;
  final VoidCallback? onOpenWorkout;

  @override
  Widget build(BuildContext context) {
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: FocusStyle.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: FocusStyle.border),
          ),
          child: ListTile(
            key: const ValueKey('free_workout_open'),
            onTap: onOpenWorkout,
            leading: const Icon(
              Icons.fitness_center_outlined,
              color: FocusStyle.accent,
            ),
            title: Text(
              tr('Тренировка', 'Workout', 'Жаттығу'),
              style: const TextStyle(color: FocusStyle.text),
            ),
            subtitle: Text(
              tr(
                'Приседания · Отжимания',
                'Squats · Push-ups',
                'Отырып-тұру · Кеудені жерден көтеру',
              ),
              style: const TextStyle(color: FocusStyle.muted),
            ),
            trailing: const Icon(Icons.chevron_right, color: FocusStyle.accent),
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            tr('Другие упражнения', 'Other exercises', 'Басқа жаттығулар'),
          ),
          children: [
            for (final exercise in [
              tr('Выпады', 'Lunges', 'Алға адымдау'),
              tr('Планка', 'Plank', 'Планка'),
              tr('Джампинг-джеки', 'Jumping jacks', 'Қол-аяқты ашып секіру'),
            ])
              ListTile(
                enabled: false,
                leading: const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: FocusStyle.muted,
                ),
                title: Text(
                  exercise,
                  style: const TextStyle(color: FocusStyle.muted),
                ),
                subtitle: Text(tr('Недоступно', 'Unavailable', 'Қолжетімсіз')),
              ),
          ],
        ),
      ],
    );
  }
}

class WorkoutDetailsScreen extends StatefulWidget {
  const WorkoutDetailsScreen({
    super.key,
    required this.language,
    this.initialExercise = ExerciseType.squats,
  });

  final String language;
  final ExerciseType initialExercise;

  @override
  State<WorkoutDetailsScreen> createState() => _WorkoutDetailsScreenState();
}

class _WorkoutDetailsScreenState extends State<WorkoutDetailsScreen> {
  late ExerciseType _selected = widget.initialExercise;
  bool _submitted = false;

  String _tr(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusStyle.theme(),
    child: Scaffold(
      appBar: AppBar(title: Text(_tr('Тренировка', 'Workout', 'Жаттығу'))),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(
              _tr('Свободная тренировка', 'Free workout', 'Еркін жаттығу'),
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _tr(
                'Выбери упражнение. Можно остановиться в любой момент.',
                'Choose your exercise',
                'Жаттығуды таңдаңыз. Кез келген уақытта тоқтай аласыз.',
              ),
              style: const TextStyle(color: FocusStyle.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            for (final exercise in [
              FocusExerciseId.squat,
              FocusExerciseId.pushUp,
            ].map((id) => exerciseById(id)!))
              Card(
                color: FocusStyle.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: _selected == exercise.unlockType
                        ? FocusStyle.accent
                        : FocusStyle.border,
                  ),
                ),
                child: ListTile(
                  key: ValueKey('workout_exercise_${exercise.unlockType.name}'),
                  selected: _selected == exercise.unlockType,
                  selectedColor: FocusStyle.accent,
                  leading: const Icon(Icons.fitness_center_outlined),
                  trailing: Icon(
                    _selected == exercise.unlockType
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(exercise.name(widget.language)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_tr('5 повторений', '5 repetitions', '5 рет')),
                      Text(
                        '+${(exercise.unlockType == ExerciseType.pushUp ? ChallengeCatalog.pushUpFreeWorkout : ChallengeCatalog.squatFreeWorkout).toReward(isUnlockContext: false).xpAmount} XP',
                      ),
                    ],
                  ),
                  titleAlignment: ListTileTitleAlignment.center,
                  onTap: () => setState(() => _selected = exercise.unlockType),
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: FocusStyle.accent,
              ),
              title: Text(
                _tr(
                  'Подсчёт через камеру',
                  'Camera-based counting',
                  'Камера арқылы санау',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _selected == ExerciseType.pushUp
                  ? _tr(
                      'Поставь телефон устойчиво. Встань лицом к камере, чтобы всё тело было в кадре.',
                      'Set the phone down securely. Face the camera with your full body in frame.',
                      'Телефонды орнықты қойып, камераға қарап, денеңізді кадрға толық сыйғызыңыз.',
                    )
                  : _tr(
                      'Поставь телефон устойчиво. Встань боком так, чтобы корпус и ноги были в кадре.',
                      'Set the phone down securely. Stand sideways with your body and legs in frame.',
                      'Телефонды орнықты қой. Денең мен аяқтарың кадрда көрінетіндей қырыңмен тұр.',
                    ),
              style: const TextStyle(color: FocusStyle.muted, height: 1.5),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
    ),
  );
}

class WorkoutResultScreen extends StatelessWidget {
  const WorkoutResultScreen({
    super.key,
    required this.result,
    required this.saved,
    required this.language,
    this.onDone,
  });

  final WorkoutResult result;
  final bool saved;
  final VoidCallback? onDone;
  final String language;

  @override
  Widget build(BuildContext context) {
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            tr('Итоги тренировки', 'Workout results', 'Жаттығу нәтижесі'),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: result.sets.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: FocusStyle.accent,
                  ),
                  title: Text(
                    tr(
                      'Всего: ${result.totalReps}',
                      'Total: ${result.totalReps}',
                      'Барлығы: ${result.totalReps}',
                    ),
                  ),
                  subtitle: saved
                      ? null
                      : Text(
                          tr(
                            'Историю не удалось сохранить.',
                            'Could not save workout history.',
                            'Жаттығу тарихы сақталмады.',
                          ),
                        ),
                );
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Подход $index', 'Set $index', '$index-тәсіл')),
                trailing: Text('${result.sets[index - 1]}'),
              );
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FocusPrimaryButton(
              text: tr('Готово', 'Done', 'Дайын'),
              onPressed: onDone ?? () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}
