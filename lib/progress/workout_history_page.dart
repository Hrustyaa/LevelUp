import 'package:material_ui/material_ui.dart';

import '../focus_experience/focus_style.dart';
import '../free_workout/workout_session.dart';
import 'progress_labels.dart';
import 'progress_models.dart';
import 'workout_progress_detail_page.dart';

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({
    super.key,
    required this.workouts,
    required this.language,
  });

  final List<WorkoutResult> workouts;
  final String language;

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  String? _exercise;

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    final now = DateTime.now();
    final allGroups = groupWorkoutHistory(widget.workouts, now: now);
    final exercises = {
      for (final group in allGroups.values)
        for (final workout in group) workout.exercise,
    };
    final groups = _exercise == null
        ? allGroups
        : groupWorkoutHistory(widget.workouts, now: now, exercise: _exercise);
    final rows = [
      for (final entry in groups.entries) ...[
        (date: entry.key, workout: null),
        for (final workout in entry.value) (date: entry.key, workout: workout),
      ],
    ];
    final allExercises = tr(
      'Все упражнения',
      'All exercises',
      'Барлық жаттығулар',
    );
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            tr('История тренировок', 'Workout history', 'Жаттығу тарихы'),
          ),
        ),
        body: SafeArea(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    tr(
                      'Пока нет тренировок',
                      'No workouts yet',
                      'Әзірге жаттығу жоқ',
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: PopupMenuButton<String>(
                          key: const ValueKey('workout_exercise_filter'),
                          tooltip: tr(
                            'Фильтр по упражнениям',
                            'Filter by exercise',
                            'Жаттығу бойынша сүзу',
                          ),
                          initialValue: _exercise ?? '',
                          onSelected: (value) => setState(
                            () => _exercise = value.isEmpty ? null : value,
                          ),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: '', child: Text(allExercises)),
                            for (final exercise in exercises)
                              PopupMenuItem(
                                value: exercise,
                                child: Text(
                                  progressExerciseLabel(exercise, language),
                                ),
                              ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              _exercise == null
                                  ? allExercises
                                  : progressExerciseLabel(_exercise!, language),
                            ),
                          ),
                        ),
                      );
                    }
                    final row = rows[index - 1];
                    final workout = row.workout;
                    if (workout != null) {
                      return WorkoutHistoryRow(
                        workout: workout,
                        language: language,
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                      child: Semantics(
                        header: true,
                        child: Text(
                          progressDate(row.date),
                          style: const TextStyle(color: FocusStyle.muted),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class WorkoutHistoryRow extends StatelessWidget {
  const WorkoutHistoryRow({
    super.key,
    required this.workout,
    required this.language,
    this.includeDate = false,
  });

  final WorkoutResult workout;
  final String language;
  final bool includeDate;

  @override
  Widget build(BuildContext context) {
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    final sets = tr('подх.', 'sets', 'тәсіл');
    final reps = tr('повт.', 'reps', 'қайталау');
    final date = includeDate ? '${progressDate(workout.endedAt)} · ' : '';
    return ListTile(
      title: Text(progressExerciseLabel(workout.exercise, language)),
      subtitle: Text(
        '$date${progressTime(workout.endedAt)} · ${workout.sets.length} $sets · ${workout.totalReps} $reps',
        style: const TextStyle(color: FocusStyle.muted),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: FocusStyle.muted,
        size: 18,
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              WorkoutProgressDetailPage(result: workout, language: language),
        ),
      ),
    );
  }
}
