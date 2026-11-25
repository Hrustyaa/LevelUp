import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../focus_experience/focus_style.dart';
import 'workout_camera_screen.dart';
import 'workout_history.dart';
import 'workout_session.dart';

class WorkoutChallengeTab extends StatelessWidget {
  const WorkoutChallengeTab({super.key, required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    String tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);
    final squat = tr('Приседания', 'Squats', 'Отырып-тұру');
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
            onTap: () => _openDetails(context),
            leading: const Icon(
              Icons.fitness_center_outlined,
              color: FocusStyle.accent,
            ),
            title: Text(squat, style: const TextStyle(color: FocusStyle.text)),
            subtitle: Text(
              tr(
                'Самостоятельная тренировка',
                'Free workout',
                'Өз бетіңше жаттығу',
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
              tr('Отжимания', 'Push-ups', 'Кеудені жерден көтеру'),
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
                subtitle: Text(tr('Скоро', 'Coming soon', 'Жақында')),
              ),
          ],
        ),
      ],
    );
  }

  void _openDetails(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutDetailsScreen(language: language),
      ),
    );
  }
}

class WorkoutDetailsScreen extends StatefulWidget {
  const WorkoutDetailsScreen({super.key, required this.language});

  final String language;

  @override
  State<WorkoutDetailsScreen> createState() => _WorkoutDetailsScreenState();
}

class _WorkoutDetailsScreenState extends State<WorkoutDetailsScreen> {
  bool _launching = false;

  String _tr(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  Future<void> _start() async {
    if (_launching) return;
    setState(() => _launching = true);
    try {
      final result = await Navigator.of(context).push<WorkoutResult>(
        MaterialPageRoute(
          builder: (_) => FreeWorkoutCameraScreen(language: widget.language),
        ),
      );
      if (result == null) return;
      bool saved = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        saved = await WorkoutHistory(prefs).add(result);
      } catch (error) {
        debugPrint('Free workout result not saved: $error');
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => WorkoutResultScreen(
            result: result,
            saved: saved,
            language: widget.language,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusStyle.theme(),
    child: Scaffold(
      appBar: AppBar(title: Text(_tr('Приседания', 'Squats', 'Отырып-тұру'))),
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
                'Выбирай свой темп и количество подходов. Остановиться можно в любой момент.',
                'Choose your pace and how many sets to do. You can stop at any time.',
                'Қарқын мен тәсіл санын өзің таңда. Кез келген уақытта тоқтай аласың.',
              ),
              style: const TextStyle(color: FocusStyle.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.all_inclusive,
                color: FocusStyle.accent,
              ),
              title: Text(
                _tr(
                  'Повторения без лимита',
                  'Unlimited repetitions',
                  'Қайталау саны шектеусіз',
                ),
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
              _tr(
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
            text: _tr('Начать тренировку', 'Start workout', 'Жаттығуды бастау'),
            onPressed: _launching ? null : _start,
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
  });

  final WorkoutResult result;
  final bool saved;
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
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}
