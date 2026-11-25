import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'squat_counter.dart';
import 'squat_geometry.dart';

/// Exact biomechanical thresholds for frontal push-up detection.
///
/// Phone is placed on a surface facing the user's upper body.
/// Shoulders, elbows and wrists must be visible in the front camera.
abstract final class PushUpThresholds {
  /// Maximum shoulder-elbow-wrist angle (°) to qualify as the bottom position.
  static const double downAngle = 100.0;

  /// Minimum shoulder-elbow-wrist angle (°) to qualify as the top position.
  static const double upAngle = 150.0;

  /// Consecutive frames required to confirm a phase transition.
  static const int consecutiveFrames = 2;

  /// Default repetition goal.
  static const int defaultGoal = 5;
}

/// Pure Dart state machine for counting frontal push-up repetitions.
///
/// Reuses [SquatCounterResult] and [SquatPhase] since the state machine is
/// structurally identical (top ↔ [SquatPhase.up], bottom ↔ [SquatPhase.down]).
///
/// The input is the average shoulder-elbow-wrist angle (in degrees) for the
/// most reliable arm visible to the front camera.
class PushUpCounter {
  final int targetGoal;

  int _reps = 0;
  SquatPhase _phase = SquatPhase.up;
  int _consecutiveDown = 0;
  int _consecutiveUp = 0;

  PushUpCounter({
    this.targetGoal = PushUpThresholds.defaultGoal,
  });

  int get repetitionCount => _reps;
  SquatPhase get currentPhase => _phase;
  bool get isGoalAchieved => _reps >= targetGoal;

  void reset() {
    _reps = 0;
    _phase = SquatPhase.up;
    _consecutiveDown = 0;
    _consecutiveUp = 0;
  }

  /// Processes a single frame's elbow angle and updates the state machine.
  ///
  /// Pass `null` when landmark confidence is insufficient.
  SquatCounterResult processAngle(double? angle, {bool isSimulated = false}) {
    if (angle == null) {
      _consecutiveDown = 0;
      _consecutiveUp = 0;
      return SquatCounterResult(
        repetitionCount: _reps,
        phase: _phase,
        isRepetitionCompleted: false,
        kneeAngle: null,
        isValidTracking: false,
        consecutiveDownFrames: 0,
        consecutiveUpFrames: 0,
        feedbackMessage: 'Не вижу плечи и локти — направь камеру на верхнюю часть тела',
        isSimulated: isSimulated,
      );
    }

    bool repetitionCompleted = false;
    String feedback;

    if (_phase == SquatPhase.up) {
      if (angle < PushUpThresholds.downAngle) {
        _consecutiveDown++;
        if (_consecutiveDown >= PushUpThresholds.consecutiveFrames) {
          _phase = SquatPhase.down;
          _consecutiveDown = 0;
        }
      } else {
        _consecutiveDown = 0;
      }

      feedback = _phase == SquatPhase.down
          ? 'Отлично! Теперь выжмись вверх'
          : 'Опусти грудь к полу';
    } else {
      // Phase is down (elbows bent)
      if (angle > PushUpThresholds.upAngle) {
        _consecutiveUp++;
        if (_consecutiveUp >= PushUpThresholds.consecutiveFrames) {
          _consecutiveUp = 0;
          _reps++;
          _phase = SquatPhase.up;
          repetitionCompleted = true;
        }
      } else {
        _consecutiveUp = 0;
      }

      feedback = repetitionCompleted ? 'Отлично!' : 'Выпрямляй руки полностью';
    }

    return SquatCounterResult(
      repetitionCount: _reps,
      phase: _phase,
      isRepetitionCompleted: repetitionCompleted,
      kneeAngle: angle,
      isValidTracking: true,
      consecutiveDownFrames: _consecutiveDown,
      consecutiveUpFrames: _consecutiveUp,
      feedbackMessage: feedback,
      isSimulated: isSimulated,
    );
  }
}

/// Extracts the frontal elbow angle from an ML Kit [Pose].
///
/// Uses the shoulder-elbow-wrist angle (in degrees) for the best visible arm.
/// Returns `null` when neither arm has sufficient landmark confidence.
///
/// NOTE: This is called on raw, unsmoothed landmarks. Smoothing is applied
/// separately to the visual overlay only.
abstract final class PushUpGeometry {
  /// Minimum landmark confidence threshold shared with [SquatGeometry].
  static const double defaultLikelihoodThreshold =
      SquatGeometry.defaultLikelihoodThreshold;

  /// Calculates the 2D interior angle at [elbow] formed by [shoulder] → [elbow]
  /// → [wrist], using the same dot-product formula as [SquatGeometry].
  static double? calculateElbowAngle(
      Offset shoulder, Offset elbow, Offset wrist) {
    final ab = shoulder - elbow;
    final cb = wrist - elbow;
    final denominator = ab.distance * cb.distance;
    if (denominator < 1e-5) return null;

    final dotProduct = ab.dx * cb.dx + ab.dy * cb.dy;
    final cosine = (dotProduct / denominator).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }

  /// Extracts the best available elbow angle from [pose].
  ///
  /// Tries left arm first, then right. Returns `null` if neither arm has
  /// all three joints (shoulder, elbow, wrist) with sufficient confidence.
  static double? estimateElbowAngle(Pose pose) {
    final map = pose.landmarks;

    double? side(
      PoseLandmarkType shoulderType,
      PoseLandmarkType elbowType,
      PoseLandmarkType wristType,
    ) {
      final shoulder = map[shoulderType];
      final elbow = map[elbowType];
      final wrist = map[wristType];
      if (shoulder == null || elbow == null || wrist == null) return null;
      if (shoulder.likelihood < defaultLikelihoodThreshold ||
          elbow.likelihood < defaultLikelihoodThreshold ||
          wrist.likelihood < defaultLikelihoodThreshold) {
        return null;
      }
      return calculateElbowAngle(
        Offset(shoulder.x, shoulder.y),
        Offset(elbow.x, elbow.y),
        Offset(wrist.x, wrist.y),
      );
    }

    return side(
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.leftWrist,
        ) ??
        side(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.rightWrist,
        );
  }
}
