import 'dart:ui';

import 'package:flutter/rendering.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:levelup_test/features/pose_detection/application/push_up_counter.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';
import 'package:levelup_test/features/pose_detection/models/pose_overlay_state.dart';
import 'package:levelup_test/features/pose_detection/presentation/pose_overlay_painter.dart';

import '../../support/push_up_pose.dart';

class _RecordingCanvas implements Canvas {
  final lines = <(Offset, Offset, double, StrokeCap, double)>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) {
    lines.add((p1, p2, paint.strokeWidth, paint.strokeCap, paint.color.a));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected drawing operation: ${invocation.memberName}',
  );
}

void main() {
  final top = plank();
  final bottom = plank(shoulderDrop: 40, hipDrop: 17, elbowDepth: -73);
  const tick = Duration(milliseconds: 85);

  late PushUpCounter counter;
  late DateTime now;
  SquatCounterResult frame(Pose? pose, {Duration after = tick}) {
    now = now.add(after);
    return counter.processPose(pose, timestamp: now);
  }

  setUp(() {
    counter = PushUpCounter();
    now = DateTime.utc(2026);
  });

  test(
    'counts frontal top/down/top despite a brief loss and foreshortening',
    () {
      expect(PushUpGeometry.estimateElbowAngle(bottom), closeTo(180, 0.1));
      frame(top);
      frame(top);
      for (var rep = 1; rep <= 5; rep++) {
        frame(bottom);
        expect(frame(bottom).phase, SquatPhase.down);
        expect(frame(null).isValidTracking, isFalse);
        expect(frame(top).isRepetitionCompleted, isFalse);
        expect(frame(top).isRepetitionCompleted, isTrue);
        expect(frame(top).repetitionCount, rep);
      }
      expect(counter.isGoalAchieved, isTrue);
    },
  );

  test(
    'normal-speed frontal movement with reduced projected hip travel counts once',
    () {
      final lowAngleTop = plank(handY: 150);
      final approach = plank(
        handY: 150,
        shoulderDrop: 13,
        hipDrop: 4,
        elbowDepth: -59,
        rightElbowFlare: 12,
      );
      final lowest = plank(
        handY: 150,
        shoulderDrop: 20,
        hipDrop: 5,
        elbowDepth: -62,
        rightElbowFlare: 17,
      );
      frame(lowAngleTop);
      frame(lowAngleTop);
      final descending = frame(approach);
      expect(descending.feedbackMessage, 'hold');
      frame(null, after: const Duration(milliseconds: 45));
      expect(
        frame(lowest, after: const Duration(milliseconds: 60)).phase,
        SquatPhase.down,
      );
      frame(lowAngleTop);
      expect(frame(lowAngleTop).isRepetitionCompleted, isTrue);
      expect(frame(lowAngleTop).repetitionCount, 1);
    },
  );

  test(
    'hand-relative hip depth can corroborate small projected hip travel',
    () {
      final lowAngleTop = plank(handY: 150);
      final lowAngleBottom = plank(
        handY: 150,
        shoulderDrop: 21,
        hipDrop: 1,
        hipDepthFromHandsDelta: 10,
        elbowDepth: -62,
      );
      frame(lowAngleTop);
      frame(lowAngleTop);
      frame(lowAngleBottom);
      expect(frame(lowAngleBottom).phase, SquatPhase.down);
      frame(lowAngleTop);
      expect(frame(lowAngleTop).repetitionCount, 1);
    },
  );

  test('diagnostics name missing hip motion without requesting more depth', () {
    final diagnostics = <String>[];
    counter = PushUpCounter(onDiagnostic: diagnostics.add);
    final shoulderOnly = plank(shoulderDrop: 37, elbowDepth: -77);
    frame(top);
    frame(top);
    expect(frame(shoulderOnly).feedbackMessage, 'move');
    expect(frame(shoulderOnly).phase, SquatPhase.up);
    frame(top);
    expect(frame(top).repetitionCount, 0);
    expect(diagnostics, contains(contains('hip movement')));
  });

  test('bottom-first and sustained confidence loss require a fresh top', () {
    frame(bottom);
    frame(bottom);
    frame(top);
    expect(frame(top).repetitionCount, 0);
    frame(bottom);
    frame(bottom);
    frame(null, after: const Duration(milliseconds: 500));
    frame(top);
    expect(frame(top).repetitionCount, 0);
  });

  test('rejects standing, seated, arm-only and partial motions', () {
    frame(top);
    frame(top);
    for (final invalid in [
      plank(shoulderDrop: 40, elbowDepth: -73, footDepth: 0),
      plank(shoulderDrop: 40, hipDrop: 17, elbowDepth: -73, kneeX: 60),
      plank(elbowDepth: -100),
      plank(shoulderDrop: 40, elbowDepth: -73), // Shoulders only.
      plank(shoulderDrop: 18, hipDrop: 12, elbowDepth: -85), // Shallow.
    ]) {
      frame(invalid);
      expect(frame(invalid).phase, SquatPhase.up);
      frame(top);
      expect(frame(top).repetitionCount, 0);
    }
  });

  test('rejects a single anomalous bottom frame and camera jumps', () {
    frame(top);
    frame(top);
    frame(bottom);
    frame(top);
    expect(frame(top).repetitionCount, 0);
    frame(bottom);
    frame(bottom);
    expect(frame(plank(shift: 160)).isValidTracking, isFalse);
    frame(top);
    expect(frame(top).repetitionCount, 0);
  });

  test(
    'paints every skeleton edge in both modes with front-camera mapping',
    () {
      final joints = <PoseLandmarkType, PoseJointPoint>{
        for (final entry in top.landmarks.entries)
          entry.key: PoseJointPoint(
            imagePoint: Offset(entry.value.x, entry.value.y),
            likelihood: entry.value.likelihood,
          ),
      };
      for (final exercise in ExerciseMode.values) {
        final canvas = _RecordingCanvas();
        PoseOverlayPainter(
          state: PoseOverlayState(
            joints: joints,
            uncertainJoints: const {PoseLandmarkType.leftAnkle},
            imageSize: const Size(200, 320),
            rotation: InputImageRotation.rotation90deg,
            exerciseMode: exercise,
            isValidForm: true,
          ),
          fit: BoxFit.contain,
        ).paint(canvas, const Size(640, 440));
        expect(canvas.lines, hasLength(12));
        expect(canvas.lines.first.$1, const Offset(420, 220));
        expect(canvas.lines.first.$2, const Offset(220, 220));
        expect(
          canvas.lines.every(
            (line) => line.$3 == 5.5 && line.$4 == StrokeCap.round,
          ),
          isTrue,
        );
        expect(canvas.lines.where((line) => line.$5 < 0.5), hasLength(1));
      }

      joints.remove(PoseLandmarkType.leftAnkle);
      final canvas = _RecordingCanvas();
      PoseOverlayPainter(
        state: PoseOverlayState(
          joints: joints,
          imageSize: const Size(320, 200),
        ),
      ).paint(canvas, const Size(320, 200));
      expect(canvas.lines, hasLength(11));
    },
  );
}
