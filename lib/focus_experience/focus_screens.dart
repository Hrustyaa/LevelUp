import 'package:material_ui/material_ui.dart';

import 'focus_exercises.dart';
import 'focus_style.dart';

/// Displays the camera and detector state supplied by the challenge controller.
class FocusChallengeScreen extends StatelessWidget {
  const FocusChallengeScreen({
    super.key,
    required this.exercise,
    required this.repetitions,
    required this.onCancel,
    required this.cameraPreview,
    required this.trackingReady,
    this.cameraReady = false,
    this.language = 'ru',
    this.hint,
    this.error,
    this.onRetry,
  });

  final FocusExercise exercise;
  final int repetitions;
  final bool trackingReady, cameraReady;
  final Widget? cameraPreview;
  final VoidCallback? onCancel, onRetry;
  final String language;
  final String? hint, error;

  @override
  Widget build(BuildContext context) {
    final count = repetitions.clamp(0, exercise.target);
    final status = trackingReady
        ? focusTr(
            language,
            'Поза распознана',
            'Pose detected',
            'Дене қалпы анықталды',
          )
        : cameraReady
        ? focusTr(
            language,
            'Поиск позы',
            'Finding your pose',
            'Дене қалпы ізделуде',
          )
        : focusTr(
            language,
            'Подготовка камеры',
            'Starting camera',
            'Камера дайындалуда',
          );
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name(language),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCancel,
                      tooltip: focusTr(
                        language,
                        'Отменить задание',
                        'Cancel challenge',
                        'Тапсырмадан бас тарту',
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: count / exercise.target,
                  semanticsLabel: exercise.name(language),
                  minHeight: 4,
                  color: FocusStyle.accent,
                  backgroundColor: FocusStyle.border,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                if (cameraPreview != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: FocusStyle.surface,
                      child: SizedBox(
                        height: (constraints.maxHeight * .54).clamp(
                          144.0,
                          450.0,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(child: cameraPreview),
                            if (error == null)
                              Positioned(
                                left: 12,
                                right: 12,
                                top: 12,
                                child: Align(
                                  alignment: AlignmentDirectional.topStart,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: FocusStyle.background,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                          color: trackingReady
                                              ? FocusStyle.accent
                                              : FocusStyle.text,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  '$count / ${exercise.target}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (error ?? hint case final message?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: error == null
                            ? FocusStyle.muted
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton(
                      onPressed: onRetry,
                      child: Text(
                        focusTr(language, 'Повторить', 'Try again', 'Қайталау'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A receipt for a confirmed access grant. Native automatic launch remains in charge.
class FocusAccessGrantedScreen extends StatelessWidget {
  const FocusAccessGrantedScreen({
    super.key,
    required this.appName,
    required this.accessMinutes,
    required this.onDone,
    this.language = 'ru',
  });

  final String appName;
  final int accessMinutes;
  final VoidCallback onDone;
  final String language;

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusStyle.theme(),
    child: Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Brand(),
                  const SizedBox(height: 38),
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 64,
                    color: FocusStyle.accent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    focusTr(
                      language,
                      'Задание выполнено',
                      'Challenge complete',
                      'Тапсырма орындалды',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    focusTr(
                      language,
                      '$appName · Выдано $accessMinutes мин доступа',
                      '$appName · $accessMinutes min of access granted',
                      '$appName · $accessMinutes минутқа рұқсат берілді',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FocusStyle.muted,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),
                  FocusPrimaryButton(
                    text: focusTr(language, 'Готово', 'Done', 'Дайын'),
                    onPressed: onDone,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Settings only offers EXERCISES THAT ACTUALLY HAVE A VERIFIED detector.
/// Planned exercises are shown disabled; never let them reach the camera flow.
class FocusExerciseSettingsScreen extends StatefulWidget {
  const FocusExerciseSettingsScreen({
    super.key,
    required this.initialSelection,
    required this.onSave,
    this.language = 'ru',
  });

  final Set<FocusExerciseId> initialSelection;
  final ValueChanged<Set<FocusExerciseId>> onSave;
  final String language;

  @override
  State<FocusExerciseSettingsScreen> createState() =>
      _FocusExerciseSettingsState();
}

class _FocusExerciseSettingsState extends State<FocusExerciseSettingsScreen> {
  late Set<FocusExerciseId> selected = widget.initialSelection
      .where(
        (id) => focusExercises.any(
          (exercise) => exercise.id == id && exercise.ready,
        ),
      )
      .toSet();

  @override
  Widget build(BuildContext context) {
    String t(String ru, String en, String kk) =>
        focusTr(widget.language, ru, en, kk);
    return Theme(
      data: FocusStyle.theme(),
      child: Scaffold(
        backgroundColor: FocusStyle.background,
        appBar: AppBar(
          title: Text(t('Упражнения', 'Exercises', 'Жаттығулар')),
          backgroundColor: FocusStyle.background,
          foregroundColor: FocusStyle.text,
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    'Выбери упражнения для Focus.',
                    'Choose exercises for Focus.',
                    'Focus үшін жаттығуларды таңда.',
                  ),
                  style: const TextStyle(color: FocusStyle.muted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.separated(
                    itemCount: focusExercises.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final exercise = focusExercises[index];
                      final checked = selected.contains(exercise.id);
                      return Material(
                        color: FocusStyle.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: checked
                                ? FocusStyle.accent
                                : FocusStyle.border,
                          ),
                        ),
                        child: CheckboxListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                          title: Text(
                            exercise.name(widget.language),
                            style: TextStyle(
                              color: exercise.ready
                                  ? FocusStyle.text
                                  : FocusStyle.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: exercise.ready
                              ? null
                              : Text(
                                  t('Скоро', 'Coming soon', 'Жақында'),
                                  style: const TextStyle(
                                    color: FocusStyle.muted,
                                    fontSize: 12,
                                  ),
                                ),
                          activeColor: FocusStyle.accent,
                          checkColor: FocusStyle.background,
                          side: const BorderSide(
                            color: FocusStyle.muted,
                            width: 1.5,
                          ),
                          value: checked,
                          onChanged: exercise.ready
                              ? (value) => setState(() {
                                  if (value == true) {
                                    selected.add(exercise.id);
                                  } else {
                                    selected.remove(exercise.id);
                                  }
                                })
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                FocusPrimaryButton(
                  text: t('Сохранить', 'Save', 'Сақтау'),
                  onPressed: selected.isEmpty
                      ? null
                      : () => widget.onSave(Set.unmodifiable(selected)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 28,
        height: 28,
        child: Image(image: AssetImage('assets/images/levelup_mark.png')),
      ),
      SizedBox(width: 8),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'LevelUp',
            style: TextStyle(
              color: FocusStyle.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ],
  );
}
