import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

Pose plank({
  double shoulderDrop = 0,
  double hipDrop = 0,
  double elbowDepth = -40,
  double footDepth = 120,
  double kneeX = 0,
  double shift = 0,
  double handY = 180,
  double hipDepthFromHandsDelta = 0,
  double rightElbowFlare = 0,
}) {
  final points = <PoseLandmarkType, PoseLandmark>{};
  void add(PoseLandmarkType type, double x, double y, double z) {
    points[type] = PoseLandmark(
      type: type,
      x: x + shift,
      y: y,
      z: z,
      likelihood: 0.95,
    );
  }

  add(PoseLandmarkType.leftShoulder, 110, 100 + shoulderDrop, -40);
  add(PoseLandmarkType.rightShoulder, 210, 100 + shoulderDrop, -40);
  // Keep projected angles straight even at the bottom, as can happen head-on.
  add(
    PoseLandmarkType.leftElbow,
    110,
    (handY + 100 + shoulderDrop) / 2,
    elbowDepth,
  );
  add(
    PoseLandmarkType.rightElbow,
    210 + rightElbowFlare,
    (handY + 100 + shoulderDrop) / 2,
    elbowDepth,
  );
  add(PoseLandmarkType.leftWrist, 110, handY, -40 - hipDepthFromHandsDelta);
  add(PoseLandmarkType.rightWrist, 210, handY, -40 - hipDepthFromHandsDelta);
  add(PoseLandmarkType.leftHip, 125, 150 + hipDrop, 0);
  add(PoseLandmarkType.rightHip, 195, 150 + hipDrop, 0);
  add(PoseLandmarkType.leftKnee, 125 - kneeX, 161 + hipDrop / 2, 60);
  add(PoseLandmarkType.rightKnee, 195 + kneeX, 161 + hipDrop / 2, 60);
  add(PoseLandmarkType.leftAnkle, 125, 172, footDepth);
  add(PoseLandmarkType.rightAnkle, 195, 172, footDepth);
  return Pose(landmarks: points);
}
