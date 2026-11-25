import 'dart:math' show max;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'focus_v2_models.dart';
import 'focus_v2_style.dart';

/// Shared icon for Gate and Success. Uses bytes from PackageManager or app list.
/// If the source cannot load the icon, show a neutral icon rather than a fake logo.
class FocusV2AppIcon extends StatelessWidget {
  const FocusV2AppIcon({super.key, required this.iconBytes, this.size = 76});
  final Uint8List? iconBytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = iconBytes == null || iconBytes!.isEmpty
        ? const Icon(
            Icons.apps_rounded,
            color: FocusV2Style.secondary,
            size: 34,
          )
        : Image.memory(
            iconBytes!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const Icon(
              Icons.apps_rounded,
              color: FocusV2Style.secondary,
              size: 34,
            ),
          );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FocusV2Style.surface,
        border: Border.all(color: FocusV2Style.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: icon,
    );
  }
}

class FocusV2Wordmark extends StatelessWidget {
  const FocusV2Wordmark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/images/levelup_mark.png',
        width: 27,
        height: 27,
        errorBuilder: (_, _, _) => const Icon(
          Icons.bolt_rounded,
          color: FocusV2Style.accent,
          size: 28,
        ),
      ),
      const SizedBox(width: 4),
      const Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'LevelUp',
            style: TextStyle(
              color: FocusV2Style.foreground,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ],
  );
}

/// UI-only Gate for a Flutter-hosted flow. The actual device gate is rendered
/// by the existing Android Accessibility overlay; use the optional Kotlin view
/// from this bundle for the same visual composition.
class FocusV2GateScreen extends StatelessWidget {
  const FocusV2GateScreen({
    super.key,
    required this.target,
    required this.onStart,
    required this.language,
    this.goalReps = 5,
    this.accessMinutes = 5,
  });

  final FocusTarget target;
  final VoidCallback onStart;
  final String language;
  final int goalReps;
  final int accessMinutes;

  String tr(String ru, String en, String kk) => focusV2Tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusV2Style.theme(),
    child: Scaffold(
      backgroundColor: FocusV2Style.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FocusV2Wordmark(),
                  Text(
                    'FOCUS',
                    style: TextStyle(
                      color: FocusV2Style.secondary,
                      fontSize: 11,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Align(
                alignment: Alignment.center,
                child: FocusV2AppIcon(iconBytes: target.iconBytes, size: 88),
              ),
              const SizedBox(height: 24),
              Text(
                tr(
                  '${target.appName} на паузе',
                  '${target.appName} is paused',
                  '${target.appName} кідіртілді',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: FocusV2Style.foreground,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Чтобы продолжить, выполни короткое задание.',
                  'Complete a short task to continue.',
                  'Жалғастыру үшін қысқа тапсырманы орында.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: FocusV2Style.secondary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 26),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: FocusV2Style.surface,
                  border: Border.all(color: FocusV2Style.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 18,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.fitness_center_outlined,
                        color: FocusV2Style.accent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          tr(
                            '$goalReps приседаний',
                            '$goalReps squats',
                            '$goalReps рет отырып-тұру',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: FocusV2Style.foreground,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr(
                  'После выполнения получишь $accessMinutes минут доступа.',
                  'Finish to get $accessMinutes minutes of access.',
                  'Аяқтаған соң $accessMinutes минут қолжетімділік беріледі.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: FocusV2Style.secondary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              FocusV2PrimaryButton(
                title: tr(
                  'Начать задание',
                  'Start challenge',
                  'Тапсырманы бастау',
                ),
                onPressed: onStart,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Only the overlay rebuilds on counter changes; the [cameraPreview] widget is
/// supplied by the existing ML Kit camera screen and stays in a separate layer.
class FocusV2CameraScreen extends StatelessWidget {
  const FocusV2CameraScreen({
    super.key,
    required this.cameraPreview,
    required this.repetitions,
    required this.poseDetected,
    required this.language,
    this.goalReps = 5,
    this.verifying = false,
    this.status,
    this.exerciseName,
    this.onCancel,
    this.isFreeWorkout = false,
  });

  final Widget cameraPreview;
  final int repetitions;
  final int goalReps;
  final bool poseDetected;
  final bool verifying;
  final String? status;
  final String? exerciseName;
  final VoidCallback? onCancel;
  final bool isFreeWorkout;
  final String language;

  String tr(String ru, String en, String kk) => focusV2Tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) {
    final reps = repetitions.clamp(0, goalReps).toInt();
    return Theme(
      data: FocusV2Style.theme(),
      child: Scaffold(
        backgroundColor: FocusV2Style.background,
        body: Stack(
          children: [
            Positioned.fill(child: RepaintBoundary(child: cameraPreview)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  color: const Color(0xE80A0F10),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exerciseName ??
                                  tr('Приседания', 'Squats', 'Отырып-тұру'),
                              style: const TextStyle(
                                color: FocusV2Style.foreground,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (onCancel != null)
                            IconButton(
                              key: const ValueKey('production_workout_close'),
                              onPressed: onCancel,
                              tooltip: tr('Отмена', 'Cancel', 'Болдырмау'),
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tr(
                          'Сделай $goalReps повторений',
                          'Complete $goalReps repetitions',
                          '$goalReps рет қайтала',
                        ),
                        style: const TextStyle(
                          color: FocusV2Style.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  color: const Color(0xF00A0F10),
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        liveRegion: true,
                        label: '$reps / $goalReps',
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$reps',
                                style: const TextStyle(
                                  color: FocusV2Style.accent,
                                  fontSize: 58,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                              Text(
                                ' / $goalReps',
                                style: const TextStyle(
                                  color: FocusV2Style.foreground,
                                  fontSize: 31,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: goalReps <= 0 ? 0 : reps / goalReps,
                          minHeight: 4,
                          color: FocusV2Style.accent,
                          backgroundColor: FocusV2Style.border,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            verifying
                                ? Icons.hourglass_empty_rounded
                                : poseDetected
                                ? Icons.check_circle_outline_rounded
                                : Icons.center_focus_strong_rounded,
                            size: 17,
                            color: verifying || poseDetected
                                ? FocusV2Style.accent
                                : FocusV2Style.secondary,
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              verifying
                                  ? tr(
                                      isFreeWorkout
                                          ? 'Сохраняем тренировку…'
                                          : 'Проверяем доступ…',
                                      isFreeWorkout
                                          ? 'Saving workout…'
                                          : 'Verifying access…',
                                      isFreeWorkout
                                          ? 'Жаттығу сақталуда…'
                                          : 'Қолжетімділік тексерілуде…',
                                    )
                                  : status ??
                                        (poseDetected
                                            ? tr(
                                                'Поза распознана',
                                                'Pose detected',
                                                'Дене қалпы анықталды',
                                              )
                                            : tr(
                                                'Встань полностью в кадр',
                                                'Keep your whole body in frame',
                                                'Денең толық кадрда болсын',
                                              )),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: FocusV2Style.foreground,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FocusV2SuccessScreen extends StatelessWidget {
  const FocusV2SuccessScreen({
    super.key,
    required this.target,
    required this.accessMinutes,
    required this.language,
    required this.onOpenApp,
    this.goalReps = 5,
    this.actionText,
  });

  final FocusTarget target;
  final int goalReps;
  final String? actionText;
  final int accessMinutes;
  final String language;
  final VoidCallback onOpenApp;

  String tr(String ru, String en, String kk) => focusV2Tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusV2Style.theme(),
    child: Scaffold(
      backgroundColor: FocusV2Style.background,
      body: _FocusV2ScrollFrame(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: FocusV2Wordmark(),
          ),
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: FocusV2Style.accent, width: 2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: FocusV2Style.accent,
              size: 53,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            tr('Готово', 'Done', 'Дайын'),
            style: const TextStyle(
              color: FocusV2Style.foreground,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'Выполнено повторений: $goalReps.',
              '$goalReps verified repetitions completed.',
              '$goalReps тексерілген қайталау орындалды.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: FocusV2Style.secondary, fontSize: 15),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            decoration: BoxDecoration(
              color: FocusV2Style.surface,
              border: Border.all(color: FocusV2Style.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                FocusV2AppIcon(iconBytes: target.iconBytes, size: 58),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.appName,
                        style: const TextStyle(
                          color: FocusV2Style.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        tr(
                          'Доступно $accessMinutes мин',
                          'Available for $accessMinutes min',
                          '$accessMinutes минут қолжетімді',
                        ),
                        style: const TextStyle(
                          color: FocusV2Style.secondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          FocusV2PrimaryButton(
            title:
                actionText ??
                tr(
                  'Открыть ${target.appName}',
                  'Open ${target.appName}',
                  '${target.appName} ашу',
                ),
            onPressed: onOpenApp,
          ),
        ],
      ),
    ),
  );
}

class FocusV2ErrorScreen extends StatelessWidget {
  const FocusV2ErrorScreen({
    super.key,
    required this.message,
    required this.language,
    this.onRetry,
    this.onCancel,
  });

  final String message;
  final String language;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  String tr(String ru, String en, String kk) => focusV2Tr(language, ru, en, kk);

  @override
  Widget build(BuildContext context) => Theme(
    data: FocusV2Style.theme(),
    child: Scaffold(
      backgroundColor: FocusV2Style.background,
      body: _FocusV2ScrollFrame(
        padding: const EdgeInsets.all(24),
        children: [
          const Spacer(),
          const Icon(
            Icons.error_outline_rounded,
            color: FocusV2Style.secondary,
            size: 52,
          ),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: FocusV2Style.foreground,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          if (onCancel != null)
            TextButton(
              key: const ValueKey('production_workout_close'),
              onPressed: onCancel,
              child: Text(tr('Назад', 'Go Back', 'Артқа')),
            ),
          if (onRetry != null)
            FocusV2PrimaryButton(
              title: focusV2Tr(language, 'Повторить', 'Retry', 'Қайталау'),
              onPressed: onRetry,
            ),
        ],
      ),
    ),
  );
}

/// Keeps the original spacing when it fits and exposes actions by scrolling
/// on short displays or when accessibility text scaling increases the height.
class _FocusV2ScrollFrame extends StatelessWidget {
  const _FocusV2ScrollFrame({required this.padding, required this.children});

  final EdgeInsets padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: max(0.0, constraints.maxHeight - padding.vertical),
          ),
          child: IntrinsicHeight(child: Column(children: children)),
        ),
      ),
    ),
  );
}
