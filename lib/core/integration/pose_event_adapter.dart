import 'dart:async';

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

  PoseEngineAdapter({
    SquatCounter? counter,
    this.isSimulated = false,
  }) : _counter = counter ?? SquatCounter();

  @override
  Stream<SquatCounterResult> get poseStream => _controller.stream;

  /// Processes a single knee angle measurement and emits the evaluated result.
  SquatCounterResult processAngle(double? angle, {bool? isSimulated}) {
    final simulatedFlag = isSimulated ?? this.isSimulated;
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
