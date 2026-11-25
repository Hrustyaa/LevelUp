import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Pure geometric functions for calculating biomechanical joint angles.
///
/// Implements the exact 2D vector dot product formula used in the LevelUp prototype.
abstract final class SquatGeometry {
  /// Minimum landmark confidence threshold used by the LevelUp pose filter.
  static const double defaultLikelihoodThreshold = 0.55;

  /// Calculates the 2D interior angle at joint [knee] (in degrees) formed by [hip] -> [knee] -> [ankle].
  ///
  /// Uses the 2D dot product of vectors BA (hip - knee) and BC (ankle - knee):
  /// $$\cos(\theta) = \frac{\vec{BA} \cdot \vec{BC}}{|\vec{BA}| \cdot |\vec{BC}|}$$
  /// Returns null if any segment length is approximately zero (< 1e-5).
  static double? calculateKneeAngle(Offset hip, Offset knee, Offset ankle) {
    final ab = hip - knee;
    final cb = ankle - knee;
    final denominator = ab.distance * cb.distance;

    if (denominator < 1e-5) return null;

    final dotProduct = ab.dx * cb.dx + ab.dy * cb.dy;
    final cosine = (dotProduct / denominator).clamp(-1.0, 1.0);
    return math.acos(cosine) * 180 / math.pi;
  }
  /// Extracts the 2D interior knee angle using [SquatGeometry].
  static double? estimateKneeAngle(Pose pose) {
    final map = pose.landmarks;

    double? side(
      PoseLandmarkType hipType,
      PoseLandmarkType kneeType,
      PoseLandmarkType ankleType,
    ) {
      final hip = map[hipType];
      final knee = map[kneeType];
      final ankle = map[ankleType];
      if (hip == null || knee == null || ankle == null) return null;
      if ([hip, knee, ankle].any((point) =>
          !point.likelihood.isFinite ||
          point.likelihood < defaultLikelihoodThreshold ||
          !point.x.isFinite || !point.y.isFinite)) {
        return null;
      }

      return calculateKneeAngle(
        Offset(hip.x, hip.y),
        Offset(knee.x, knee.y),
        Offset(ankle.x, ankle.y),
      );
    }

    return side(
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
        ) ??
        side(
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.rightAnkle,
        );
  }
}
