import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../focus_experience/focus_style.dart';
import '../application/pose_coordinate_mapper.dart';
import '../application/squat_geometry.dart';
import '../models/pose_overlay_state.dart';

/// Lightweight [CustomPainter] rendering real-time white / lime-green skeleton
/// lines over the camera preview.
///
/// - Squat mode (`ExerciseMode.squat`): draws `hip → knee → ankle` for each
///   detected leg.
/// - Push-up mode (`ExerciseMode.pushUp`): draws `shoulder → elbow → wrist`
///   for each detected arm.
///
/// White `#F7F8F8` = tracking active / standing.
/// Lime `#C7FA5B` = valid form phase (squat down / push-up bottom).
/// No joint circles. 5.5 px rounded strokes.
class PoseOverlayPainter extends CustomPainter {
  final PoseOverlayState state;
  final BoxFit fit;
  final double likelihoodThreshold;

  const PoseOverlayPainter({
    required this.state,
    this.fit = BoxFit.cover,
    this.likelihoodThreshold = SquatGeometry.defaultLikelihoodThreshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hasContent = state.exerciseMode == ExerciseMode.pushUp
        ? state.hasAnyArm
        : state.hasAnyLeg;
    if (!hasContent || size.isEmpty || state.imageSize.isEmpty) return;

    final alpha = state.opacity.clamp(0.0, 1.0);
    final baseColor = state.isValidForm ? FocusStyle.accent : FocusStyle.text;
    final color = baseColor.withValues(alpha: alpha);
    final effectiveThreshold = alpha < 1.0
        ? math.min(likelihoodThreshold, 0.35)
        : likelihoodThreshold;
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (state.exerciseMode == ExerciseMode.pushUp) {
      // Push-up mode: draw arm segments (shoulder → elbow → wrist)
      for (final arm in [state.leftArm, state.rightArm]) {
        if (arm == null) continue;
        final mapped = PoseCoordinateMapper.mapArm(
          arm: arm,
          rawImageSize: state.imageSize,
          rotation: state.rotation,
          previewSize: size,
          isFrontCamera: state.isFrontCamera,
          likelihoodThreshold: effectiveThreshold,
          fit: fit,
        );
        if (mapped == null) continue;

        canvas.drawLine(mapped.shoulder, mapped.elbow, linePaint);
        canvas.drawLine(mapped.elbow, mapped.wrist, linePaint);
      }
    } else {
      // Squat mode: draw leg segments (hip → knee → ankle)
      for (final leg in [state.leftLeg, state.rightLeg]) {
        if (leg == null) continue;
        final mapped = PoseCoordinateMapper.mapLeg(
          leg: leg,
          rawImageSize: state.imageSize,
          rotation: state.rotation,
          previewSize: size,
          isFrontCamera: state.isFrontCamera,
          likelihoodThreshold: effectiveThreshold,
          fit: fit,
        );
        if (mapped == null) continue;

        canvas.drawLine(mapped.hip, mapped.knee, linePaint);
        canvas.drawLine(mapped.knee, mapped.ankle, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.fit != fit ||
        oldDelegate.likelihoodThreshold != likelihoodThreshold;
  }
}
