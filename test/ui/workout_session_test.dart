import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:levelup_test/free_workout/workout_challenge_tab.dart';
import 'package:levelup_test/free_workout/workout_history.dart';
import 'package:levelup_test/free_workout/workout_session.dart';

void squat(WorkoutSession session) {
  for (final angle in [170.0, 170.0, 100.0, 100.0, 170.0, 170.0]) {
    session.onDetectedKneeAngle(angle);
  }
}

void main() {
  test('free workout counts beyond Focus limit of five', () {
    final session = WorkoutSession();
    for (var n = 0; n < 12; n++) {
      squat(session);
    }
    expect(session.currentReps, 12);
    expect(session.stage, WorkoutStage.counting);
  });

  test('pause and tracking loss do not count reps', () {
    final session = WorkoutSession();
    session.pause();
    for (var n = 0; n < 4; n++) {
      squat(session);
    }
    expect(session.currentReps, 0);
    session.resume();
    session.onDetectedKneeAngle(null);
    squat(session);
    expect(session.currentReps, 1);
  });

  test('sets are explicit, unlimited, and do not count zero sets', () {
    final session = WorkoutSession(startedAt: DateTime(2026, 11, 25));
    expect(session.finishSet(), isFalse);
    for (var n = 0; n < 12; n++) {
      squat(session);
    }
    expect(session.finishSet(), isTrue);
    session.nextSet();
    for (var n = 0; n < 9; n++) {
      squat(session);
    }
    expect(session.finishSet(), isTrue);
    session.nextSet();
    for (var n = 0; n < 7; n++) {
      squat(session);
    }
    final result = session.finish(endedAt: DateTime(2026, 11, 25, 0, 5));
    expect(result!.sets, [12, 9, 7]);
    expect(result.totalReps, 28);
    expect(session.stage, WorkoutStage.finished);
    expect(session.finish(), isNull);
  });

  test('an invalid frame or pause invalidates a partial movement', () {
    final session = WorkoutSession();
    for (final angle in [170.0, 170.0, 100.0, 100.0]) {
      session.onDetectedKneeAngle(angle);
    }
    session.onDetectedKneeAngle(double.nan);
    session.onDetectedKneeAngle(170);
    session.onDetectedKneeAngle(170);
    expect(session.currentReps, 0);
    squat(session);
    session.pause();
    expect(session.finishSet(), isFalse);
    expect(session.finish()!.sets, [1]);
  });

  testWidgets('workout results scroll through many sets', (tester) async {
    final startedAt = DateTime(2026, 11, 25);
    await tester.pumpWidget(
      MaterialApp(
        home: WorkoutResultScreen(
          result: WorkoutResult(
            exercise: 'squat',
            startedAt: startedAt,
            endedAt: startedAt.add(const Duration(minutes: 20)),
            sets: List.filled(40, 2),
          ),
          saved: true,
          language: 'en',
        ),
      ),
    );
    expect(find.text('Total: 80'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Set 40'), 300);
    expect(find.text('Set 40'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('zero-rep workout has no record', () {
    final session = WorkoutSession();
    expect(session.finish(), isNull);
  });

  test('history persists factual results only', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = WorkoutHistory(prefs);
    final session = WorkoutSession(startedAt: DateTime(2026, 11, 25));
    squat(session);
    final result = session.finish(endedAt: DateTime(2026, 11, 25, 0, 1))!;
    expect(await store.add(result), isTrue);
    expect(store.all().single.sets, [1]);
    expect(store.all().single.totalReps, 1);
  });
}
