import 'dart:math' as math;
import 'dart:ui';

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
}
