import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';

void main() {
  late SquatCounter counter;

  setUp(() {
    counter = SquatCounter(targetGoal: 5);
  });

  group('Initial State', () {
    test('initializes with 0 reps, phase up, and goal not achieved', () {
      expect(counter.repetitionCount, equals(0));
      expect(counter.currentPhase, equals(SquatPhase.up));
      expect(counter.isGoalAchieved, isFalse);
    });

    test('initial standing pose (angle > 155) maintains phase up and 0 reps', () {
      final res1 = counter.processAngle(170.0);
      expect(res1.phase, equals(SquatPhase.up));
      expect(res1.repetitionCount, equals(0));
      expect(res1.isRepetitionCompleted, isFalse);
      expect(res1.feedbackMessage, equals('Присядь (опусти корпус)'));

      final res2 = counter.processAngle(168.0);
      expect(res2.phase, equals(SquatPhase.up));
      expect(res2.repetitionCount, equals(0));
      expect(res2.isRepetitionCompleted, isFalse);
    });
  });

  group('Full Squat Cycle', () {
    test('counts 1 repetition upon completing standing -> down -> standing transition', () {
      // 1. Standing: 170°
      counter.processAngle(170.0);

      // 2. Descending: Frame 1 below 125° (120°)
      final d1 = counter.processAngle(120.0);
      expect(d1.phase, equals(SquatPhase.up), reason: 'Debounce requires 2 consecutive frames');
      expect(d1.consecutiveDownFrames, equals(1));
      expect(d1.isRepetitionCompleted, isFalse);

      // 3. Descending: Frame 2 below 125° (115°)
      final d2 = counter.processAngle(115.0);
      expect(d2.phase, equals(SquatPhase.down), reason: 'Phase transitions to down on 2nd consecutive frame');
      expect(d2.consecutiveDownFrames, equals(0));
      expect(d2.feedbackMessage, equals('Отлично! Теперь встань'));
      expect(d2.isRepetitionCompleted, isFalse);

      // 4. In bottom position: 110°
      final bottom = counter.processAngle(110.0);
      expect(bottom.phase, equals(SquatPhase.down));
      expect(bottom.isRepetitionCompleted, isFalse);

      // 5. Ascending: Frame 1 above 155° (158°)
      final u1 = counter.processAngle(158.0);
      expect(u1.phase, equals(SquatPhase.down), reason: 'Debounce requires 2 consecutive frames');
      expect(u1.consecutiveUpFrames, equals(1));
      expect(u1.isRepetitionCompleted, isFalse);

      // 6. Ascending: Frame 2 above 155° (165°)
      final u2 = counter.processAngle(165.0);
      expect(u2.phase, equals(SquatPhase.up), reason: 'Transitions to up on 2nd consecutive frame');
      expect(u2.consecutiveUpFrames, equals(0));
      expect(u2.repetitionCount, equals(1));
      expect(u2.isRepetitionCompleted, isTrue);
      expect(u2.feedbackMessage, equals('Отлично!'));
    });

    test('counts multiple full squat cycles and achieves goal', () {
      void performSquat() {
        // Down phase (2 frames < 125°)
        counter.processAngle(120.0);
        counter.processAngle(115.0);
        // Up phase (2 frames > 155°)
        counter.processAngle(160.0);
        counter.processAngle(165.0);
      }

      for (var i = 1; i <= 5; i++) {
        performSquat();
        expect(counter.repetitionCount, equals(i));
      }

      expect(counter.isGoalAchieved, isTrue);
    });
  });

  group('Partial Movement & Thresholds', () {
    test('partial descent not reaching < 125 degrees never transitions to down', () {
      // User only dips to 130° (insufficient depth)
      counter.processAngle(170.0);
      counter.processAngle(140.0);
      counter.processAngle(130.0);
      counter.processAngle(128.0);
      counter.processAngle(130.0);
      counter.processAngle(170.0);

      expect(counter.currentPhase, equals(SquatPhase.up));
      expect(counter.repetitionCount, equals(0));
    });

    test('partial ascent not reaching > 155 degrees never completes repetition', () {
      // Full descent
      counter.processAngle(120.0);
      counter.processAngle(115.0);
      expect(counter.currentPhase, equals(SquatPhase.down));

      // Partial ascent: only rises to 148° (below 155° threshold)
      counter.processAngle(130.0);
      counter.processAngle(145.0);
      counter.processAngle(148.0);
      counter.processAngle(140.0);

      expect(counter.currentPhase, equals(SquatPhase.down));
      expect(counter.repetitionCount, equals(0));
    });

    test('no movement (constant angle) never triggers a count', () {
      for (var i = 0; i < 20; i++) {
        final res = counter.processAngle(170.0);
        expect(res.repetitionCount, equals(0));
        expect(res.isRepetitionCompleted, isFalse);
      }
    });
  });

  group('Repeated Frames & Anti-Duplication', () {
    test('repeating bottom position (110 degrees) does not cause multiple counts', () {
      // Transition to down
      counter.processAngle(120.0);
      counter.processAngle(115.0);
      expect(counter.currentPhase, equals(SquatPhase.down));

      // 10 consecutive frames staying at the bottom
      for (var i = 0; i < 10; i++) {
        final res = counter.processAngle(110.0);
        expect(res.phase, equals(SquatPhase.down));
        expect(res.repetitionCount, equals(0));
        expect(res.isRepetitionCompleted, isFalse);
      }
    });

    test('once standing is verified, continuing to stand does NOT increment count again', () {
      // Complete 1 squat
      counter.processAngle(120.0);
      counter.processAngle(115.0);
      counter.processAngle(160.0);
      final completeRes = counter.processAngle(165.0);
      expect(completeRes.isRepetitionCompleted, isTrue);
      expect(completeRes.repetitionCount, equals(1));

      // Subsequent 10 standing frames
      for (var i = 0; i < 10; i++) {
        final res = counter.processAngle(170.0);
        expect(res.phase, equals(SquatPhase.up));
        expect(res.repetitionCount, equals(1), reason: 'Count must remain 1');
        expect(res.isRepetitionCompleted, isFalse, reason: 'isRepetitionCompleted is only true on transition frame');
      }
    });
  });

  group('Angle Jitter Near Thresholds', () {
    test('jittering around down threshold (125 degrees) resets consecutive count', () {
      counter.processAngle(170.0);

      // Frame 1 below 125
      final f1 = counter.processAngle(124.0);
      expect(f1.consecutiveDownFrames, equals(1));
      expect(f1.phase, equals(SquatPhase.up));

      // Jitter above 125
      final f2 = counter.processAngle(126.0);
      expect(f2.consecutiveDownFrames, equals(0), reason: 'Consecutive down count reset');
      expect(f2.phase, equals(SquatPhase.up));

      // Another single frame below 125
      final f3 = counter.processAngle(123.0);
      expect(f3.consecutiveDownFrames, equals(1));
      expect(f3.phase, equals(SquatPhase.up));
    });

    test('jittering around up threshold (155 degrees) resets consecutive count', () {
      // Put in down phase
      counter.processAngle(120.0);
      counter.processAngle(115.0);
      expect(counter.currentPhase, equals(SquatPhase.down));

      // Frame 1 above 155
      final f1 = counter.processAngle(156.0);
      expect(f1.consecutiveUpFrames, equals(1));
      expect(f1.phase, equals(SquatPhase.down));

      // Jitter below 155
      final f2 = counter.processAngle(154.0);
      expect(f2.consecutiveUpFrames, equals(0), reason: 'Consecutive up count reset');
      expect(f2.phase, equals(SquatPhase.down));
      expect(counter.repetitionCount, equals(0));
    });
  });

  group('Invalid Landmarks & Person Leaving Frame', () {
    test('processing null angle marks invalid tracking and clears debounce counters', () {
      // Start descent with 1 frame
      counter.processAngle(120.0);

      // Landmark lost / invalid frame
      final lostRes = counter.processAngle(null);
      expect(lostRes.isValidTracking, isFalse);
      expect(lostRes.kneeAngle, isNull);
      expect(lostRes.consecutiveDownFrames, equals(0));
      expect(lostRes.feedbackMessage, contains('Не вижу бедро, колено и стопу'));

      // If user returns below threshold, it needs 2 fresh consecutive frames
      final r1 = counter.processAngle(120.0);
      expect(r1.consecutiveDownFrames, equals(1));
      expect(r1.phase, equals(SquatPhase.up));

      final r2 = counter.processAngle(118.0);
      expect(r2.consecutiveDownFrames, equals(0));
      expect(r2.phase, equals(SquatPhase.down));
    });

    test('person leaving and returning during down phase preserves phase', () {
      // Descend to down phase
      counter.processAngle(120.0);
      counter.processAngle(115.0);
      expect(counter.currentPhase, equals(SquatPhase.down));

      // Person leaves frame for 3 frames
      counter.processAngle(null);
      counter.processAngle(null);
      counter.processAngle(null);
      expect(counter.currentPhase, equals(SquatPhase.down), reason: 'Phase preserved across tracking dropout');

      // Returns in bottom position, then rises
      counter.processAngle(110.0);
      counter.processAngle(160.0);
      final completed = counter.processAngle(165.0);

      expect(completed.repetitionCount, equals(1));
      expect(completed.isRepetitionCompleted, isTrue);
      expect(counter.currentPhase, equals(SquatPhase.up));
    });
  });

  group('Resetting the Counter', () {
    test('reset clears reps, phase, and debounce counters', () {
      // Do 2 squats and stay down
      counter.processAngle(120.0);
      counter.processAngle(115.0);
      counter.processAngle(160.0);
      counter.processAngle(165.0); // Rep 1

      counter.processAngle(120.0);
      counter.processAngle(115.0);
      counter.processAngle(160.0);
      counter.processAngle(165.0); // Rep 2

      counter.processAngle(120.0);
      counter.processAngle(115.0); // Down phase

      expect(counter.repetitionCount, equals(2));
      expect(counter.currentPhase, equals(SquatPhase.down));

      counter.reset();

      expect(counter.repetitionCount, equals(0));
      expect(counter.currentPhase, equals(SquatPhase.up));
      expect(counter.isGoalAchieved, isFalse);
    });
  });

  group('SquatCounterResult Properties', () {
    test('implements equality, hashCode, and toString', () {
      final a = counter.processAngle(170.0);
      counter.reset();
      final b = counter.processAngle(170.0);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('reps: 0'));
    });
  });
}
