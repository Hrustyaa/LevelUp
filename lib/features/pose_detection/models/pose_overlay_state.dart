import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Which exercise mode is active, used by [PoseOverlayPainter] to decide
/// which skeleton segments to draw.
enum ExerciseMode { squat, pushUp }

/// Immutable raw ML Kit landmark point in input-image coordinates.
@immutable
class PoseJointPoint {
  final Offset imagePoint;
  final double likelihood;

  const PoseJointPoint({
    required this.imagePoint,
    required this.likelihood,
  });

  bool isReliable(double threshold) =>
      likelihood >= threshold &&
      imagePoint.dx.isFinite &&
      imagePoint.dy.isFinite &&
      (imagePoint.dx != 0 || imagePoint.dy != 0);
}

/// Immutable 3-joint leg chain (`hip -> knee -> ankle`) in image coordinates.
@immutable
class LegLandmarks {
  final PoseJointPoint hip;
  final PoseJointPoint knee;
  final PoseJointPoint ankle;

  const LegLandmarks({
    required this.hip,
    required this.knee,
    required this.ankle,
  });

  double get minLikelihood =>
      math.min(hip.likelihood, math.min(knee.likelihood, ankle.likelihood));

  bool isReliable(double threshold) =>
      hip.isReliable(threshold) &&
      knee.isReliable(threshold) &&
      ankle.isReliable(threshold);
}

/// Immutable 3-joint arm chain (`shoulder -> elbow -> wrist`) in image
/// coordinates, used for push-up overlay rendering.
@immutable
class ArmLandmarks {
  final PoseJointPoint shoulder;
  final PoseJointPoint elbow;
  final PoseJointPoint wrist;

  const ArmLandmarks({
    required this.shoulder,
    required this.elbow,
    required this.wrist,
  });

  double get minLikelihood =>
      math.min(shoulder.likelihood, math.min(elbow.likelihood, wrist.likelihood));

  bool isReliable(double threshold) =>
      shoulder.isReliable(threshold) &&
      elbow.isReliable(threshold) &&
      wrist.isReliable(threshold);
}

/// Read-only, immutable snapshot of detected landmarks for live overlay
/// rendering. Strictly presentation-only: never drives workout completion.
@immutable
class PoseOverlayState {
  final LegLandmarks? leftLeg;
  final LegLandmarks? rightLeg;
  final ArmLandmarks? leftArm;
  final ArmLandmarks? rightArm;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  final bool isValidForm;
  final int sessionEpoch;
  final ExerciseMode exerciseMode;

  /// Stroke opacity (`1.0` for confident tracking, reduced e.g. `0.45` during
  /// uncertain hysteresis grace period).
  final double opacity;

  const PoseOverlayState({
    this.leftLeg,
    this.rightLeg,
    this.leftArm,
    this.rightArm,
    this.imageSize = Size.zero,
    this.rotation = InputImageRotation.rotation0deg,
    this.isFrontCamera = true,
    this.isValidForm = false,
    this.sessionEpoch = 0,
    this.exerciseMode = ExerciseMode.squat,
    this.opacity = 1.0,
  });

  static const empty = PoseOverlayState();

  bool get hasAnyLeg => leftLeg != null || rightLeg != null;
  bool get hasAnyArm => leftArm != null || rightArm != null;
}
