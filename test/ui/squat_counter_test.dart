import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/test_kit/squat_counter.dart';

void main() {
  test('requires a stable standing, down, and standing sequence', () {
    final counter = SquatCounter();
    for (final angle in [110.0, 110.0, 170.0, 170.0, 110.0, 170.0]) {
      counter.update(angle);
    }
    expect(counter.phase, SquatPhase.lower);
    expect(counter.reps, 0);

    for (final angle in [110.0, 110.0, 170.0, 170.0]) {
      counter.update(angle);
    }
    expect(counter.reps, 1);
  });

  test('drops an interrupted squat when pose tracking is lost', () {
    final counter = SquatCounter();
    for (final angle in [170.0, 170.0, 110.0, 110.0, null, 170.0, 170.0]) {
      counter.update(angle);
    }
    expect(counter.reps, 0);
    expect(counter.phase, SquatPhase.lower);
  });

  test('finishes at five complete squats', () {
    final counter = SquatCounter()
      ..update(170)
      ..update(170);
    for (var i = 0; i < 6; i++) {
      for (final angle in [110.0, 110.0, 170.0, 170.0]) {
        counter.update(angle);
      }
    }
    expect(counter.isComplete, isTrue);
    expect(counter.reps, 5);
  });
}
