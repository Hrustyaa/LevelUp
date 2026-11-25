import 'dart:async';

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../features/pose_detection/application/push_up_counter.dart';
import '../../features/pose_detection/application/squat_counter.dart';

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

typedef PushUpSessionIdentity = ({
  String sessionId,
  String requestId,
  String challengeId,
  String? targetPackage,
  int repetitions,
});

/// Evidence issued when the live counter completes its bound workout.
final class PushUpCompletion {
  final PushUpSessionIdentity identity;

  const PushUpCompletion._(this.identity);
}

/// Adapter that processes push-up poses through a [PushUpCounter] and exposes
/// the results as an [IPoseEventSource].
///
/// Used when the active exercise is [ExerciseType.pushUp]. The coordinator
/// consumes [SquatCounterResult] in both cases because the state machine
/// structure is identical (top/bottom phases, repetition count, feedback).
final class PushUpPoseAdapter implements IPoseEventSource {
  final PushUpCounter _counter;
  PushUpSessionIdentity? _identity;
  PushUpCompletion? _completion;

  PushUpCompletion? get completion => _completion;
  final StreamController<SquatCounterResult> _controller =
      StreamController<SquatCounterResult>.broadcast();

  @override
  final bool isSimulated;

  PushUpPoseAdapter({
    this.isSimulated = false,
    void Function(String message)? onDiagnostic,
  }) : _counter = PushUpCounter(onDiagnostic: onDiagnostic);

  @override
  Stream<SquatCounterResult> get poseStream => _controller.stream;

  void bindToSession(PushUpSessionIdentity identity) {
    if (_identity == identity) return;
    if (_identity != null || identity.repetitions != _counter.targetGoal) {
      throw StateError('The push-up counter must match one workout session.');
    }
    _counter.reset();
    _identity = identity;
  }

  SquatCounterResult processPose(Pose? pose, {required DateTime timestamp}) {
    final result = _counter.processPose(
      pose,
      timestamp: timestamp,
      isSimulated: isSimulated,
    );
    if (!_controller.isClosed) {
      final identity = _identity;
      if (identity != null &&
          !result.isSimulated &&
          result.isRepetitionCompleted &&
          result.repetitionCount == identity.repetitions) {
        _completion ??= PushUpCompletion._(identity);
      }
      _controller.add(result);
    }
    return result;
  }

  void interruptTracking() => _counter.interruptTracking();

  @override
  void dispose() {
    _controller.close();
  }
}
