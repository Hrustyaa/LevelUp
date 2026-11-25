import 'dart:async';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../features/pose_detection/application/push_up_counter.dart';
import '../../features/pose_detection/application/squat_counter.dart';
import '../../features/pose_detection/application/squat_geometry.dart';
import '../../models/exercise_type.dart';

/// Contract for a source emitting verified pose tracking and repetition events.
///
/// Decouples the Coordinator from direct camera or ML Kit widgets, enabling
/// headless testing in Phase A and clean camera binding in Phase B.
abstract class IPoseEventSource {
  /// Reactive stream of evaluated [SquatCounterResult] snapshots.
  Stream<SquatCounterResult> get poseStream;

  /// Whether this source emits simulated / artificial pose angles rather than camera-verified poses.
  bool get isSimulated;

  /// Disposes resources held by the event source.
  void dispose();
}

/// Simple adapter that processes raw knee angles through a [SquatCounter]
/// and exposes the results as an [IPoseEventSource].
class PoseEngineAdapter implements IPoseEventSource {
  final SquatCounter _counter;
  final StreamController<SquatCounterResult> _controller =
      StreamController<SquatCounterResult>.broadcast();

  @override
  final bool isSimulated;

  PoseEngineAdapter({SquatCounter? counter, this.isSimulated = false})
    : _counter = counter ?? SquatCounter();

  @override
  Stream<SquatCounterResult> get poseStream => _controller.stream;

  /// Processes a single knee angle measurement and emits the evaluated result.
  SquatCounterResult processAngle(double? angle, {bool? isSimulated}) {
    final simulatedFlag = this.isSimulated || (isSimulated ?? false);
    final result = _counter.processAngle(angle, isSimulated: simulatedFlag);
    if (!_controller.isClosed) {
      _controller.add(result);
    }
    return result;
  }

  /// Resets the internal counter state machine back to zero.
  void reset() {
    _counter.reset();
  }

  @override
  void dispose() {
    _controller.close();
  }
}

typedef CameraWorkoutIdentity = ({
  String sessionId,
  String requestId,
  String challengeId,
  ExerciseType exerciseType,
  String? targetPackage,
  int repetitions,
});

/// In-memory evidence issued by a session-bound counter from raw landmarks.
final class CameraWorkoutCompletion {
  final CameraWorkoutIdentity identity;
  const CameraWorkoutCompletion._(this.identity);
}

typedef PushUpCompletion = CameraWorkoutCompletion;

sealed class CameraPoseAdapter implements IPoseEventSource {
  final _controller = StreamController<SquatCounterResult>.broadcast();
  CameraWorkoutIdentity? _identity;
  CameraWorkoutCompletion? _completion;

  CameraWorkoutCompletion? get completion => _completion;
  ExerciseType get exerciseType;

  @override
  final bool isSimulated;
  CameraPoseAdapter({this.isSimulated = false});

  @override
  Stream<SquatCounterResult> get poseStream => _controller.stream;

  void bindToSession(CameraWorkoutIdentity identity) {
    if (_identity == identity) return;
    if (_identity != null ||
        identity.exerciseType != exerciseType ||
        identity.repetitions != SquatThresholds.defaultGoal) {
      throw StateError('The camera counter must match one workout session.');
    }
    _reset();
    _identity = identity;
  }

  SquatCounterResult processPose(Pose? pose, {required DateTime timestamp}) {
    final result = _process(pose, timestamp);
    if (!_controller.isClosed) {
      final identity = _identity;
      if (identity != null &&
          !result.isSimulated &&
          result.isRepetitionCompleted &&
          result.repetitionCount == identity.repetitions) {
        _completion ??= CameraWorkoutCompletion._(identity);
      }
      _controller.add(result);
    }
    return result;
  }

  SquatCounterResult _process(Pose? pose, DateTime timestamp);
  void _reset();
  void interruptTracking();

  @override
  void dispose() => _controller.close();
}

final class SquatCameraPoseAdapter extends CameraPoseAdapter {
  final _counter = SquatCounter();
  DateTime? _lastTrackedAt;

  SquatCameraPoseAdapter({super.isSimulated});

  @override
  ExerciseType get exerciseType => ExerciseType.squats;

  @override
  SquatCounterResult _process(Pose? pose, DateTime timestamp) {
    final last = _lastTrackedAt;
    if (last != null &&
        (timestamp.isBefore(last) ||
            timestamp.difference(last) > const Duration(milliseconds: 500))) {
      interruptTracking();
    }
    final angle = pose == null ? null : SquatGeometry.estimateKneeAngle(pose);
    if (angle != null) _lastTrackedAt = timestamp;
    return _counter.processAngle(angle, isSimulated: isSimulated);
  }

  @override
  void _reset() {
    _lastTrackedAt = null;
    _counter.reset();
  }

  @override
  void interruptTracking() {
    _lastTrackedAt = null;
    _counter.interruptTracking();
  }
}

final class PushUpPoseAdapter extends CameraPoseAdapter {
  final PushUpCounter _counter;

  PushUpPoseAdapter({
    super.isSimulated,
    void Function(String message)? onDiagnostic,
  }) : _counter = PushUpCounter(onDiagnostic: onDiagnostic);

  @override
  ExerciseType get exerciseType => ExerciseType.pushUp;

  @override
  SquatCounterResult _process(Pose? pose, DateTime timestamp) =>
      _counter.processPose(pose, timestamp: timestamp, isSimulated: isSimulated);

  @override
  void _reset() => _counter.reset();

  @override
  void interruptTracking() => _counter.interruptTracking();
}
