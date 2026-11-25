import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'squat_counter.dart';
import 'squat_geometry.dart';

/// Thresholds for push-up phase confirmation.
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
/// Live camera frames are evaluated with [processPose].
class PushUpCounter {
  final int targetGoal;
  final void Function(String message)? onDiagnostic;

  int _reps = 0;
  SquatPhase _phase = SquatPhase.up;
  int _consecutiveDown = 0;
  int _consecutiveUp = 0;
  DateTime? _lastTrackedAt;
  DateTime? _topAt;
  _PushUpFrame? _top;
  _PushUpFrame? _previousFrame;
  _PushUpFrame? _topCandidate;
  DateTime? _lastBottomEvidenceAt;
  double _bestTravel = 0;
  String? _bottomRejection;
  DateTime? _lastDiagnosticAt;

  static const _trackingGrace = Duration(milliseconds: 300);
  static const _bottomEvidenceWindow = Duration(milliseconds: 220);

  PushUpCounter({
    this.targetGoal = PushUpThresholds.defaultGoal,
    this.onDiagnostic,
  });

  int get repetitionCount => _reps;
  SquatPhase get currentPhase => _phase;
  bool get isGoalAchieved => _reps >= targetGoal;

  void reset() {
    _reps = 0;
    _lastDiagnosticAt = null;
    interruptTracking();
  }

  /// Discards an in-flight repetition while preserving completed repetitions.
  void interruptTracking() {
    _lastTrackedAt = null;
    _top = null;
    _topAt = null;
    _topCandidate = null;
    _previousFrame = null;
    _clearDescent();
    _phase = SquatPhase.up;
    _consecutiveDown = 0;
    _consecutiveUp = 0;
  }

  /// Evaluates raw landmarks in upright ML Kit image coordinates.
  SquatCounterResult processPose(
    Pose? pose, {
    required DateTime timestamp,
    bool isSimulated = false,
  }) {
    final sincePrevious = _lastTrackedAt == null
        ? null
        : timestamp.difference(_lastTrackedAt!);
    if (sincePrevious != null &&
        (sincePrevious > _trackingGrace || sincePrevious.isNegative)) {
      if (_bestTravel > 0 || _phase == SquatPhase.down) {
        _diagnose(
          timestamp,
          'Attempt ended: tracking gap or invalid timestamp.',
        );
      }
      interruptTracking();
    }

    var feedback = 'tracking';
    final frame = pose == null
        ? null
        : _PushUpFrame.fromPose(pose, (check, hint) {
            // A missing landmark is useful for setup but should not flood logs.
            _diagnose(timestamp, check, throttle: true);
            feedback = hint;
          });
    if (frame == null) {
      _consecutiveUp = 0;
      _topCandidate = null;
      return _result(false, null, feedback, isSimulated);
    }

    final previous = _previousFrame;
    if (previous != null &&
        (frame.shoulders - previous.shoulders).distance >
            previous.width * 0.55) {
      _diagnose(timestamp, 'Attempt ended: discontinuous shoulder tracking.');
      interruptTracking();
      return _result(false, null, 'tracking', isSimulated);
    }
    _previousFrame = frame;
    _lastTrackedAt = timestamp;

    final top = _top;
    if (top == null) {
      final candidate = _topCandidate;
      _topCandidate = frame.extended ? frame : null;
      if (frame.extended &&
          candidate != null &&
          frame.handsStableComparedWith(candidate) &&
          (frame.shoulders - candidate.shoulders).distance <
              candidate.width * 0.18) {
        _top = frame;
        _topAt = timestamp;
      } else {
        _diagnose(
          timestamp,
          'Waiting for a stable, extended starting pose.',
          throttle: true,
        );
      }
      return _result(
        false,
        frame,
        _top == null ? 'start' : 'move',
        isSimulated,
      );
    }

    final elapsed = timestamp.difference(_topAt!);
    if (!frame.handsStableComparedWith(top)) {
      _diagnose(
        timestamp,
        'Attempt ended: hand position or shoulder scale changed.',
      );
      interruptTracking();
      return _result(false, frame, 'hands', isSimulated);
    }
    if (elapsed > const Duration(seconds: 5) &&
        (_phase == SquatPhase.down || _bestTravel > 0)) {
      _diagnose(timestamp, 'Attempt ended: cycle timed out.');
      interruptTracking();
      return _result(false, frame, 'start', isSimulated);
    }

    final shoulderDrop = (frame.shoulders.dy - top.shoulders.dy) / top.width;
    final hipDrop = (frame.hips.dy - top.hips.dy) / top.width;
    final travel = (top.clearance - frame.clearance) / top.width;
    // Calibrate against the observed arm clearance at the top. Both values
    // measure image motion rather than the height of the chest above the floor.
    final requiredTravel = (top.clearance / top.width * 0.32).clamp(0.15, 0.27);
    final returnTolerance = requiredTravel * 0.55;
    final returned =
        frame.extended &&
        shoulderDrop.abs() <= returnTolerance &&
        travel.abs() <= returnTolerance &&
        hipDrop.abs() <= 0.16;

    if (_phase == SquatPhase.up) {
      final hipDepthShift =
          (frame.hipDepthFromHands - top.hipDepthFromHands) / top.width;
      final trunkMoved =
          hipDrop >= 0.035 || (hipDrop >= -0.02 && hipDepthShift >= 0.075);
      final leftMoved = frame.left.flexedFrom(top.left);
      final rightMoved = frame.right.flexedFrom(top.right);
      final enoughTravel =
          travel >= requiredTravel && shoulderDrop >= requiredTravel * 0.70;
      final corroborated = trunkMoved && leftMoved && rightMoved;
      final nearBottom =
          corroborated &&
          travel >= requiredTravel * 0.70 &&
          shoulderDrop >= requiredTravel * 0.50;
      final atBottom = enoughTravel && corroborated;

      if ((travel >= 0.09 || leftMoved || rightMoved) &&
          travel >= _bestTravel) {
        _bestTravel = travel;
        if (onDiagnostic != null) {
          final checks = [
            if (!enoughTravel) 'shoulder travel / hand-relative clearance',
            if (!trunkMoved) 'hip movement',
            if (!leftMoved) 'left arm flexion or shortening',
            if (!rightMoved) 'right arm flexion or shortening',
            if (atBottom) 'second bottom-supporting observation',
          ];
          _bottomRejection = checks.join(', ');
        }
      }

      final lastEvidence = _lastBottomEvidenceAt;
      final supported =
          lastEvidence != null &&
          timestamp.difference(lastEvidence) <= _bottomEvidenceWindow;
      if (atBottom && supported) {
        _phase = SquatPhase.down;
        _consecutiveDown = 0;
        _diagnose(timestamp, 'Bottom confirmed by torso travel and both arms.');
        return _result(false, frame, 'raise', isSimulated);
      }
      // A fast but controlled rep can have a single frame at its lowest
      // point. Require a supporting descent frame so a one-frame jump fails.
      _lastBottomEvidenceAt = nearBottom ? timestamp : null;
      _consecutiveDown = nearBottom ? 1 : 0;

      if (returned && travel.abs() < 0.085) {
        if (_bottomRejection != null) {
          _diagnose(
            timestamp,
            'Attempt ended before bottom confirmation: $_bottomRejection.',
          );
        }
        _clearDescent();
        _topAt = timestamp;
      }
      return _result(false, frame, nearBottom ? 'hold' : 'move', isSimulated);
    }

    _consecutiveUp = returned ? _consecutiveUp + 1 : 0;
    if (_consecutiveUp >= PushUpThresholds.consecutiveFrames &&
        elapsed >= const Duration(milliseconds: 260)) {
      _reps++;
      _phase = SquatPhase.up;
      _consecutiveUp = 0;
      _clearDescent();
      _top = frame;
      _topAt = timestamp;
      _diagnose(timestamp, 'Repetition $_reps confirmed.');
      return _result(true, frame, 'complete', isSimulated);
    }
    return _result(false, frame, returned ? 'holdTop' : 'raise', isSimulated);
  }

  void _clearDescent() {
    _bestTravel = 0;
    _bottomRejection = null;
    _lastBottomEvidenceAt = null;
    _consecutiveDown = 0;
  }

  void _diagnose(DateTime timestamp, String message, {bool throttle = false}) {
    if (onDiagnostic == null) return;
    final last = _lastDiagnosticAt;
    if (throttle &&
        last != null &&
        timestamp.difference(last) < const Duration(milliseconds: 750)) {
      return;
    }
    _lastDiagnosticAt = timestamp;
    onDiagnostic!(message);
  }

  SquatCounterResult _result(
    bool completed,
    _PushUpFrame? frame,
    String feedback,
    bool isSimulated,
  ) => SquatCounterResult(
    repetitionCount: _reps,
    phase: _phase,
    isRepetitionCompleted: completed,
    kneeAngle: null,
    isValidTracking: frame != null,
    consecutiveDownFrames: _consecutiveDown,
    consecutiveUpFrames: _consecutiveUp,
    feedbackMessage: feedback,
    isSimulated: isSimulated,
  );

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
        feedbackMessage:
            'Не вижу плечи и локти — направь камеру на верхнюю часть тела',
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
          : 'Отслеживаю движение';
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
    Offset shoulder,
    Offset elbow,
    Offset wrist,
  ) {
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

/// Measurements from both arms and the torso/legs in a front-facing plank.
/// ML Kit depth is relative to the hips and is only a supporting signal.
class _PushUpFrame {
  final Offset shoulders;
  final Offset hips;
  final Offset leftHand;
  final Offset rightHand;
  final double width;
  final double clearance;
  final double hipDepthFromHands;
  final _PushUpArm left;
  final _PushUpArm right;

  bool get extended =>
      clearance >= width * 0.32 && left.extended && right.extended;

  const _PushUpFrame({
    required this.shoulders,
    required this.hips,
    required this.leftHand,
    required this.rightHand,
    required this.width,
    required this.clearance,
    required this.hipDepthFromHands,
    required this.left,
    required this.right,
  });

  bool handsStableComparedWith(_PushUpFrame other) =>
      (leftHand - other.leftHand).distance <= other.width * 0.23 &&
      (rightHand - other.rightHand).distance <= other.width * 0.23 &&
      (width / other.width - 1).abs() <= 0.25;

  static _PushUpFrame? fromPose(
    Pose pose,
    void Function(String check, String hint) reject,
  ) {
    final joints = <PoseLandmarkType, PoseLandmark>{};
    for (final type in const [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ]) {
      final joint = pose.landmarks[type];
      if (joint == null ||
          !joint.likelihood.isFinite ||
          joint.likelihood < PushUpGeometry.defaultLikelihoodThreshold ||
          !joint.x.isFinite ||
          !joint.y.isFinite ||
          !joint.z.isFinite) {
        reject(
          'Uncertain or missing ${type.name} landmark.',
          type.index >= PoseLandmarkType.leftHip.index ? 'tracking' : 'arms',
        );
        return null;
      }
      joints[type] = joint;
    }

    final ls = joints[PoseLandmarkType.leftShoulder]!;
    final rs = joints[PoseLandmarkType.rightShoulder]!;
    final le = joints[PoseLandmarkType.leftElbow]!;
    final re = joints[PoseLandmarkType.rightElbow]!;
    final lw = joints[PoseLandmarkType.leftWrist]!;
    final rw = joints[PoseLandmarkType.rightWrist]!;
    final lh = joints[PoseLandmarkType.leftHip]!;
    final rh = joints[PoseLandmarkType.rightHip]!;
    final lk = joints[PoseLandmarkType.leftKnee]!;
    final rk = joints[PoseLandmarkType.rightKnee]!;
    final la = joints[PoseLandmarkType.leftAnkle]!;
    final ra = joints[PoseLandmarkType.rightAnkle]!;
    final shoulders = (_xy(ls) + _xy(rs)) / 2;
    final hips = (_xy(lh) + _xy(rh)) / 2;
    final width = (ls.x - rs.x).abs();
    final framingFailure = switch (width) {
      < 12 => 'shoulders too small in frame',
      _ when (ls.y - rs.y).abs() > width * 0.35 => 'shoulder line tilt',
      _ when (lw.x - rw.x).abs() < width * 0.60 => 'projected hand spacing',
      _ when (hips - shoulders).distance > width * 1.15 =>
        'projected trunk length',
      _ => null,
    };
    if (framingFailure != null) {
      reject('Frontal framing failed: $framingFailure.', 'setup');
      return null;
    }

    // Feet must recede behind the hips and the legs must be extended.
    final shoulderDepth = (ls.z + rs.z) / 2;
    final hipDepth = (lh.z + rh.z) / 2;
    final ankleDepth = (la.z + ra.z) / 2;
    final plankFailure = switch (hipDepth - shoulderDepth) {
      _ when hipDepth - shoulderDepth < width * 0.30 =>
        'hip depth relative to shoulders',
      _ when ankleDepth - hipDepth < width * 0.30 =>
        'ankle depth relative to hips',
      _ when (_angle(lh, lk, la, withDepth: true) ?? 0) < 145 =>
        'left knee extension',
      _ when (_angle(rh, rk, ra, withDepth: true) ?? 0) < 145 =>
        'right knee extension',
      _ => null,
    };
    if (plankFailure != null) {
      reject('Plank check failed: $plankFailure.', 'setup');
      return null;
    }

    _PushUpArm arm(
      PoseLandmark shoulder,
      PoseLandmark elbow,
      PoseLandmark hand,
    ) => _PushUpArm(
      projectedAngle: _angle(shoulder, elbow, hand),
      depthAngle: _angle(shoulder, elbow, hand, withDepth: true),
      projectedLength: (_xy(shoulder) - _xy(hand)).distance,
    );

    return _PushUpFrame(
      shoulders: shoulders,
      hips: hips,
      leftHand: _xy(lw),
      rightHand: _xy(rw),
      width: width,
      clearance: (lw.y + rw.y) / 2 - shoulders.dy,
      hipDepthFromHands: hipDepth - (lw.z + rw.z) / 2,
      left: arm(ls, le, lw),
      right: arm(rs, re, rw),
    );
  }

  static Offset _xy(PoseLandmark p) => Offset(p.x, p.y);

  static double? _angle(
    PoseLandmark shoulder,
    PoseLandmark elbow,
    PoseLandmark wrist, {
    bool withDepth = false,
  }) {
    if (!withDepth) {
      return PushUpGeometry.calculateElbowAngle(
        _xy(shoulder),
        _xy(elbow),
        _xy(wrist),
      );
    }
    final first = _xy(shoulder) - _xy(elbow);
    final second = _xy(wrist) - _xy(elbow);
    final firstZ = shoulder.z - elbow.z;
    final secondZ = wrist.z - elbow.z;
    final magnitude = math.sqrt(
      (first.distanceSquared + firstZ * firstZ) *
          (second.distanceSquared + secondZ * secondZ),
    );
    if (magnitude < 1e-5) return null;
    final dot = first.dx * second.dx + first.dy * second.dy + firstZ * secondZ;
    return math.acos((dot / magnitude).clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

class _PushUpArm {
  final double? projectedAngle;
  final double? depthAngle;
  final double projectedLength;

  const _PushUpArm({
    required this.projectedAngle,
    required this.depthAngle,
    required this.projectedLength,
  });

  bool get extended =>
      math.max(projectedAngle ?? 0, depthAngle ?? 0) >=
      PushUpThresholds.upAngle;

  bool flexedFrom(_PushUpArm top) =>
      _angleChanged(top.projectedAngle, projectedAngle) ||
      _angleChanged(top.depthAngle, depthAngle) ||
      projectedLength <= top.projectedLength * 0.65;

  static bool _angleChanged(double? top, double? current) =>
      top != null && current != null && current <= 145 && top - current >= 25;
}
