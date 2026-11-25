import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/app/challenge/workout_exercise_screen.dart';
import 'package:levelup_test/models/exercise_type.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('exercise cards stay usable with large text on a small display', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ExerciseType? selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  selected = await Navigator.of(context).push<ExerciseType>(
                    MaterialPageRoute(
                      builder: (_) => const WorkoutExerciseScreen(
                        initialExercise: ExerciseType.squats,
                        language: 'en',
                      ),
                    ),
                  ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final squat = find.byKey(const ValueKey('workout_exercise_squats'));
    final pushUp = find.byKey(const ValueKey('workout_exercise_pushUp'));
    final start = find.text('Start Workout');
    expect(
      find.descendant(
        of: squat,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );

    final pushUpTitle = find.text('Push-ups');
    await tester.scrollUntilVisible(pushUpTitle.hitTestable(), 120);
    await tester.tap(pushUpTitle);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: pushUp,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: squat,
        matching: find.byIcon(Icons.radio_button_unchecked_rounded),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.text('Camera setup').hitTestable(), 120);
    expect(find.textContaining('hands and feet'), findsOneWidget);
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(selected, ExerciseType.pushUp);
  });

  for (final (language, title, squat, pushUp, repetitions, start) in [
    (
      'en',
      'Choose your exercise',
      'Squats',
      'Push-ups',
      '5 reps',
      'Start Workout',
    ),
    (
      'ru',
      'Выбери своё упражнение',
      'Приседания',
      'Отжимания',
      '5 повторений',
      'Начать тренировку',
    ),
    (
      'kk',
      'Жаттығуыңызды таңдаңыз',
      'Отырып-тұру',
      'Қолды бүгіп-жазу',
      '5 рет',
      'Жаттығуды бастау',
    ),
  ]) {
    testWidgets('chooser localizes both exercises and rewards in $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutExerciseScreen(
            initialExercise: ExerciseType.squats,
            language: language,
          ),
        ),
      );
      expect(find.text(title), findsOneWidget);
      expect(find.text(squat), findsOneWidget);
      expect(find.text(pushUp), findsOneWidget);
      expect(find.text(repetitions), findsNWidgets(2));
      expect(find.text('+50 XP'), findsNWidgets(2));
      expect(find.text(start), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
