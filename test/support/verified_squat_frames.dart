import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/core/integration/pose_event_adapter.dart';

Pose squatPose({required bool down}) {
  PoseLandmark point(PoseLandmarkType type, double x, double y) => PoseLandmark(
    type: type, x: x, y: y, z: 0, likelihood: 0.95,
  );
  return Pose(landmarks: {
    PoseLandmarkType.leftHip: point(
      PoseLandmarkType.leftHip,
      down ? 200 : 100,
      down ? 100 : 0,
    ),
    PoseLandmarkType.leftKnee: point(PoseLandmarkType.leftKnee, 100, 100),
    PoseLandmarkType.leftAnkle: point(PoseLandmarkType.leftAnkle, 100, 200),
  });
}

/// Drives the same session-bound counter as the UI with synthetic ML Kit poses.
Future<void> completeVerifiedSquats(ICoreIntegrationCoordinator coordinator) async {
  final adapter = SquatCameraPoseAdapter();
  final sessionId = coordinator.currentState.sessionId!;
  coordinator.attachPoseEventSource(adapter, sessionId: sessionId);
  var timestamp = DateTime.utc(2026);
  try {
    for (var rep = 0; rep < 5; rep++) {
      for (final down in [true, true, false, false]) {
        timestamp = timestamp.add(const Duration(milliseconds: 85));
        adapter.processPose(squatPose(down: down), timestamp: timestamp);
        await Future<void>.microtask(() {});
      }
    }
    await coordinator.waitForCompletion();
  } finally {
    coordinator.detachPoseEventSource(sessionId: sessionId);
    adapter.dispose();
  }
}
