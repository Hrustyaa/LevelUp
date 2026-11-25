import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Exercise associated with the overlay snapshot.
enum ExerciseMode { squat, pushUp }

/// Immutable raw ML Kit landmark point in input-image coordinates.
@immutable
class PoseJointPoint {
  final Offset imagePoint;
  final double likelihood;

  const PoseJointPoint({required this.imagePoint, required this.likelihood});

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
/// coordinates.
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

  double get minLikelihood => math.min(
    shoulder.likelihood,
    math.min(elbow.likelihood, wrist.likelihood),
  );

  bool isReliable(double threshold) =>
      shoulder.isReliable(threshold) &&
      elbow.isReliable(threshold) &&
      wrist.isReliable(threshold);
}

/// Read-only, immutable snapshot of detected landmarks for live overlay
/// rendering. Strictly presentation-only: never drives workout completion.
@immutable
class PoseOverlayState {
  final LegLandmarks? _leftLeg;
  final LegLandmarks? _rightLeg;
  final ArmLandmarks? _leftArm;
  final ArmLandmarks? _rightArm;
  final Map<PoseLandmarkType, PoseJointPoint> joints;
  final Set<PoseLandmarkType> uncertainJoints;

  static const connections = <(PoseLandmarkType, PoseLandmarkType)>[
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow),
    (PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow),
    (PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist),
    (PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip),
    (PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.rightHip),
    (PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee),
    (PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle),
    (PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee),
    (PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle),
  ];

  static final jointTypes = Set<PoseLandmarkType>.unmodifiable(
    connections.expand((edge) => [edge.$1, edge.$2]),
  );
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
    LegLandmarks? leftLeg,
    LegLandmarks? rightLeg,
    ArmLandmarks? leftArm,
    ArmLandmarks? rightArm,
    this.joints = const {},
    this.uncertainJoints = const {},
    this.imageSize = Size.zero,
    this.rotation = InputImageRotation.rotation0deg,
    this.isFrontCamera = true,
    this.isValidForm = false,
    this.sessionEpoch = 0,
    this.exerciseMode = ExerciseMode.squat,
    this.opacity = 1.0,
  }) : _leftLeg = leftLeg,
       _rightLeg = rightLeg,
       _leftArm = leftArm,
       _rightArm = rightArm;

  PoseJointPoint? joint(PoseLandmarkType type) =>
      joints[type] ??
      switch (type) {
        PoseLandmarkType.leftShoulder => _leftArm?.shoulder,
        PoseLandmarkType.rightShoulder => _rightArm?.shoulder,
        PoseLandmarkType.leftElbow => _leftArm?.elbow,
        PoseLandmarkType.rightElbow => _rightArm?.elbow,
        PoseLandmarkType.leftWrist => _leftArm?.wrist,
        PoseLandmarkType.rightWrist => _rightArm?.wrist,
        PoseLandmarkType.leftHip => _leftLeg?.hip,
        PoseLandmarkType.rightHip => _rightLeg?.hip,
        PoseLandmarkType.leftKnee => _leftLeg?.knee,
        PoseLandmarkType.rightKnee => _rightLeg?.knee,
        PoseLandmarkType.leftAnkle => _leftLeg?.ankle,
        PoseLandmarkType.rightAnkle => _rightLeg?.ankle,
        _ => null,
      };

  LegLandmarks? _leg(
    PoseLandmarkType hip,
    PoseLandmarkType knee,
    PoseLandmarkType ankle,
  ) {
    final a = joint(hip);
    final b = joint(knee);
    final c = joint(ankle);
    if (a == null || b == null || c == null) return null;
    return LegLandmarks(hip: a, knee: b, ankle: c);
  }

  ArmLandmarks? _arm(
    PoseLandmarkType shoulder,
    PoseLandmarkType elbow,
    PoseLandmarkType wrist,
  ) {
    final a = joint(shoulder);
    final b = joint(elbow);
    final c = joint(wrist);
    if (a == null || b == null || c == null) return null;
    return ArmLandmarks(shoulder: a, elbow: b, wrist: c);
  }

  LegLandmarks? get leftLeg =>
      _leftLeg ??
      _leg(
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.leftAnkle,
      );
  LegLandmarks? get rightLeg =>
      _rightLeg ??
      _leg(
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightAnkle,
      );
  ArmLandmarks? get leftArm =>
      _leftArm ??
      _arm(
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist,
      );
  ArmLandmarks? get rightArm =>
      _rightArm ??
      _arm(
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist,
      );

  static const empty = PoseOverlayState();

  bool get hasAnyLeg => leftLeg != null || rightLeg != null;
  bool get hasAnyArm => leftArm != null || rightArm != null;
}
