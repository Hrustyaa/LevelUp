import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:levelup_test/focus_experience/focus_exercises.dart';
import 'package:levelup_test/focus_experience/focus_screens.dart';

void main() {
  testWidgets('challenge displays detector progress and can be canceled', (
    tester,
  ) async {
    var canceled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusChallengeScreen(
          exercise: focusExercises.first,
          repetitions: 2,
          cameraPreview: const SizedBox(),
          trackingReady: true,
          onCancel: () => canceled = true,
        ),
      ),
    );
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('Поза распознана'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .4,
    );
    await tester.tap(find.byTooltip('Отменить задание'));
    expect(canceled, isTrue);
  });

  testWidgets('access receipt can close without attempting a second grant', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusAccessGrantedScreen(
          appName: 'YouTube',
          accessMinutes: 5,
          onDone: () => closed = true,
        ),
      ),
    );
    expect(find.text('YouTube · Выдано 5 мин доступа'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    expect(closed, isTrue);
  });

  testWidgets('planned exercises cannot be selected as ready', (tester) async {
    Set<FocusExerciseId>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusExerciseSettingsScreen(
          initialSelection: const {FocusExerciseId.squat},
          onSave: (selection) => saved = selection,
        ),
      ),
    );
    final pushUps = find.widgetWithText(
      CheckboxListTile,
      'Отжимания · 5 повторений',
    );
    expect(pushUps, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(pushUps).onChanged, isNull);
    expect(find.text('Разблокировка недоступна в этой сборке'), findsOneWidget);
    await tester.tap(pushUps);
    await tester.tap(find.text('Сохранить'));
    expect(saved, {FocusExerciseId.squat});
  });
}
