import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../focus_experience/focus_style.dart';
import '../application/pose_coordinate_mapper.dart';
import '../application/squat_geometry.dart';
import '../models/pose_overlay_state.dart';

/// Lightweight [CustomPainter] rendering real-time white / lime-green skeleton
/// lines over the camera preview.
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
    if (size.isEmpty || state.imageSize.isEmpty) return;

    final alpha = state.opacity.clamp(0.0, 1.0);
    final points = {
      for (final type in PoseOverlayState.jointTypes)
        if (state.joint(type) case final joint?)
          if (joint.isReliable(
            state.uncertainJoints.contains(type) || alpha < 1
                ? math.min(likelihoodThreshold, 0.35)
                : likelihoodThreshold,
          ))
            type: PoseCoordinateMapper.mapPoint(
              point: joint.imagePoint,
              rawImageSize: state.imageSize,
              rotation: state.rotation,
              previewSize: size,
              isFrontCamera: state.isFrontCamera,
              fit: fit,
            ),
    };
    final linePaint = Paint()
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final (start, end) in PoseOverlayState.connections) {
      final from = points[start];
      final to = points[end];
      if (from == null || to == null) continue;
      final uncertain =
          state.uncertainJoints.contains(start) ||
          state.uncertainJoints.contains(end);
      final baseColor = state.isValidForm && !uncertain
          ? FocusStyle.accent
          : FocusStyle.text;
      linePaint.color = baseColor.withValues(
        alpha: uncertain ? math.min(alpha, 0.45) : alpha,
      );
      canvas.drawLine(from, to, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PoseOverlayPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.fit != fit ||
        oldDelegate.likelihoodThreshold != likelihoodThreshold;
  }
}
