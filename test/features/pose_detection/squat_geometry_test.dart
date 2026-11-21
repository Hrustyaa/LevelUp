import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/features/pose_detection/application/squat_geometry.dart';

void main() {
  group('SquatGeometry', () {
    test('calculates 180 degrees for straight vertical leg', () {
      // Hip at (100, 50), Knee at (100, 100), Ankle at (100, 150)
      const hip = Offset(100, 50);
      const knee = Offset(100, 100);
      const ankle = Offset(100, 150);

      final angle = SquatGeometry.calculateKneeAngle(hip, knee, ankle);
      expect(angle, isNotNull);
      expect(angle!, closeTo(180.0, 0.01));
    });

    test('calculates 90 degrees for perpendicular bent leg', () {
      // Hip at (50, 100), Knee at (100, 100), Ankle at (100, 150)
      const hip = Offset(50, 100);
      const knee = Offset(100, 100);
      const ankle = Offset(100, 150);

      final angle = SquatGeometry.calculateKneeAngle(hip, knee, ankle);
      expect(angle, isNotNull);
      expect(angle!, closeTo(90.0, 0.01));
    });

    test('calculates typical deep squat knee angle (~110 degrees)', () {
      // Femur angled downwards, tibia vertical
      const knee = Offset(100, 100);
      const ankle = Offset(100, 200); // vector cb: (0, 100) -> down
      // Hip at 110 degrees from down vector
      // cos(110°) = -0.34202
      const hip = Offset(193.97, 65.8);

      final angle = SquatGeometry.calculateKneeAngle(hip, knee, ankle);
      expect(angle, isNotNull);
      expect(angle!, closeTo(110.0, 0.5));
    });

    test('returns null when any segment distance is near zero', () {
      const knee = Offset(100, 100);
      const ankle = Offset(100, 150);

      // Hip coincident with knee
      final angleCoincident = SquatGeometry.calculateKneeAngle(knee, knee, ankle);
      expect(angleCoincident, isNull);

      // Ankle coincident with knee
      final angleCoincident2 = SquatGeometry.calculateKneeAngle(const Offset(100, 50), knee, knee);
      expect(angleCoincident2, isNull);
    });

    test('exposes defaultLikelihoodThreshold constant matching prototype (0.55)', () {
      expect(SquatGeometry.defaultLikelihoodThreshold, equals(0.55));
    });
  });
}
