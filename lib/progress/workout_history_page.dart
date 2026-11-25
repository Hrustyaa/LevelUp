import 'package:material_ui/material_ui.dart';

import '../focus_experience/focus_style.dart';
import '../free_workout/workout_session.dart';
import 'progress_labels.dart';
import 'progress_models.dart';
import 'progress_repository.dart';
import 'workout_progress_detail_page.dart';

class WorkoutHistoryPage extends StatefulWidget {
  const WorkoutHistoryPage({
    super.key,
    required this.workouts,
    required this.language,
    this.loadHistory,
  });

  final List<WorkoutResult> workouts;
  final String language;
  final WorkoutHistoryLoader? loadHistory;

  @override
  State<WorkoutHistoryPage> createState() => _WorkoutHistoryPageState();
}

class _WorkoutHistoryPageState extends State<WorkoutHistoryPage> {
  String? _exercise;
  List<WorkoutResult>? _loadedWorkouts;
  int _loadedLimit = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadHistory != null) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    final load = widget.loadHistory;
    if (load == null) return;
    final limit = _loadedLimit + 50;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final page = await load(limit);
      if (!mounted) return;
      setState(() {
        _loadedLimit = limit;
        _loadedWorkouts = page.workouts;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    final now = DateTime.now();
    final workouts = _loadedWorkouts ?? widget.workouts;
    final allGroups = groupWorkoutHistory(workouts, now: now);
    final exercises = {
      for (final group in allGroups.values)
        for (final workout in group) workout.exercise,
    };
    final groups = _exercise == null
        ? allGroups
        : groupWorkoutHistory(workouts, now: now, exercise: _exercise);
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
    final footer = _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadFailed || _hasMore
        ? TextButton(
            onPressed: _loadMore,
            child: Text(
              _loadFailed
                  ? tr('Повторить', 'Retry', 'Қайталау')
                  : tr(
                      'Загрузить старые записи',
                      'Load older workouts',
                      'Бұрынғы жаттығуларды жүктеу',
                    ),
            ),
          )
        : null;
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
              ? footer ??
                    Center(
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
                  itemCount: rows.length + 1 + (footer == null ? 0 : 1),
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
                    if (index > rows.length) return footer!;
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
