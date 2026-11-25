import 'package:material_ui/material_ui.dart';

import '../focus_experience/focus_style.dart';
import '../free_workout/workout_session.dart';
import 'progress_labels.dart';
import 'progress_models.dart';

class WorkoutProgressDetailPage extends StatelessWidget {
  const WorkoutProgressDetailPage({
    super.key,
    required this.result,
    required this.language,
  });

  final WorkoutResult result;
  final String language;

  @override
  Widget build(BuildContext context) {
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    final reps = tr('повторений', 'reps', 'қайталау');
    final sets = tr('Подходы', 'Sets', 'Тәсілдер');
    final total = tr('Итого', 'Total', 'Барлығы');
    final duration = result.endedAt.difference(result.startedAt);
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(progressExerciseLabel(result.exercise, language)),
        ),
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            itemCount: result.sets.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${progressDate(result.startedAt)} · ${progressTime(result.startedAt)}',
                      style: const TextStyle(color: FocusStyle.muted),
                    ),
                    const SizedBox(height: 12),
                    Text('$sets · ${result.sets.length}'),
                    Text(
                      '${tr('Повторения', 'Repetitions', 'Қайталаулар')} · ${result.totalReps}',
                    ),
                    Text(
                      '${tr('Продолжительность', 'Duration', 'Ұзақтығы')} · ${progressDuration(duration, language)}',
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }
              if (index > result.sets.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '$total · ${result.totalReps} $reps',
                    style: const TextStyle(
                      color: FocusStyle.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        tr('Подход $index', 'Set $index', '$index-тәсіл'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${result.sets[index - 1]} $reps',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: FocusStyle.muted),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
