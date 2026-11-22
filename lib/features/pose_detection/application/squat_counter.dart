import 'package:flutter/foundation.dart';

/// Exact biomechanical thresholds used by the LevelUp squat detection state machine.
abstract final class SquatThresholds {
  /// Maximum knee angle (in degrees) to qualify as a bottom squat position (down phase).
  static const double downAngle = 125.0;

  /// Minimum knee angle (in degrees) to qualify as an upright standing position (up phase).
  static const double upAngle = 155.0;

  /// Number of consecutive valid frames required to confirm a phase transition (debounce).
  static const int consecutiveFrames = 2;

  /// Default competition repetition goal.
  static const int defaultGoal = 5;
}

/// Movement phase of the squat repetition state machine.
enum SquatPhase {
  /// Standing upright pose (starting position and return position).
  up,

  /// Deep squat pose with knees bent below [SquatThresholds.downAngle].
  down,
}

/// Snapshot result emitted after processing a single frame angle.
@immutable
class SquatCounterResult {
  /// Cumulative count of verified completed full squat repetitions.
  final int repetitionCount;

  /// Current active movement phase (up or down).
  final SquatPhase phase;

  /// True ONLY on the single frame where a full repetition was verified (down -> up transition).
  final bool isRepetitionCompleted;

  /// The processed knee angle in degrees, or null if tracking was unavailable.
  final double? kneeAngle;

  /// Whether valid body landmarks were detected and evaluated in this frame.
  final bool isValidTracking;

  /// Number of consecutive frames accumulated towards the down transition.
  final int consecutiveDownFrames;

  /// Number of consecutive frames accumulated towards the up transition.
  final int consecutiveUpFrames;

  /// Real-time posture feedback message matching the LevelUp prototype.
  final String feedbackMessage;

  /// Whether this result was generated via manual angle simulation rather than live camera tracking.
  final bool isSimulated;

  const SquatCounterResult({
    required this.repetitionCount,
    required this.phase,
    required this.isRepetitionCompleted,
    this.kneeAngle,
    required this.isValidTracking,
    required this.consecutiveDownFrames,
    required this.consecutiveUpFrames,
    required this.feedbackMessage,
    this.isSimulated = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SquatCounterResult &&
          runtimeType == other.runtimeType &&
          repetitionCount == other.repetitionCount &&
          phase == other.phase &&
          isRepetitionCompleted == other.isRepetitionCompleted &&
          kneeAngle == other.kneeAngle &&
          isValidTracking == other.isValidTracking &&
          consecutiveDownFrames == other.consecutiveDownFrames &&
          consecutiveUpFrames == other.consecutiveUpFrames &&
          feedbackMessage == other.feedbackMessage &&
          isSimulated == other.isSimulated;

  @override
  int get hashCode => Object.hash(
        repetitionCount,
        phase,
        isRepetitionCompleted,
        kneeAngle,
        isValidTracking,
        consecutiveDownFrames,
        consecutiveUpFrames,
        feedbackMessage,
        isSimulated,
      );

  @override
  String toString() =>
      'SquatCounterResult(reps: $repetitionCount, phase: $phase, completed: $isRepetitionCompleted, angle: ${kneeAngle?.toStringAsFixed(1)}°, simulated: $isSimulated)';
}

/// Pure Dart state machine for counting squats based on interior knee angle.
///
/// Encapsulates the exact counting logic from `lib/main.dart` without camera,
/// Flutter UI, or native platform dependencies.
class SquatCounter {
  final int targetGoal;

  int _reps = 0;
  SquatPhase _phase = SquatPhase.up;
  int _consecutiveDown = 0;
  int _consecutiveUp = 0;

  SquatCounter({
    this.targetGoal = SquatThresholds.defaultGoal,
  });

  /// Current count of completed repetitions.
  int get repetitionCount => _reps;

  /// Current phase of the squat movement.
  SquatPhase get currentPhase => _phase;

  /// Whether the user has achieved the target goal for this session.
  bool get isGoalAchieved => _reps >= targetGoal;

  /// Resets the counter state back to initial (0 reps, up phase).
  void reset() {
    _reps = 0;
    _phase = SquatPhase.up;
    _consecutiveDown = 0;
    _consecutiveUp = 0;
  }

  /// Processes a single frame's knee angle and updates the state machine.
  ///
  /// Passing `null` indicates that landmarks were missing or below confidence threshold.
  SquatCounterResult processAngle(double? angle, {bool isSimulated = false}) {
    if (angle == null) {
      // Invalidate consecutive frame debounce when tracking is lost
      _consecutiveDown = 0;
      _consecutiveUp = 0;

      return SquatCounterResult(
        repetitionCount: _reps,
        phase: _phase,
        isRepetitionCompleted: false,
        kneeAngle: null,
        isValidTracking: false,
        consecutiveDownFrames: 0,
        consecutiveUpFrames: 0,
        feedbackMessage: 'Не вижу бедро, колено и стопу — повернись боком',
        isSimulated: isSimulated,
      );
    }

    bool repetitionCompleted = false;
    String feedback;

    if (_phase == SquatPhase.up) {
      if (angle < SquatThresholds.downAngle) {
        _consecutiveDown++;
        if (_consecutiveDown >= SquatThresholds.consecutiveFrames) {
          _phase = SquatPhase.down;
          _consecutiveDown = 0;
        }
      } else {
        _consecutiveDown = 0;
      }

      feedback = _phase == SquatPhase.down
          ? 'Отлично! Теперь встань'
          : 'Присядь (опусти корпус)';
    } else {
      // Phase is SquatPhase.down
      if (angle > SquatThresholds.upAngle) {
        _consecutiveUp++;
        if (_consecutiveUp >= SquatThresholds.consecutiveFrames) {
          _consecutiveUp = 0;
          _reps++;
          _phase = SquatPhase.up;
          repetitionCompleted = true;
        }
      } else {
        _consecutiveUp = 0;
      }

      feedback = repetitionCompleted ? 'Отлично!' : 'Вернись в положение стоя';
    }

    return SquatCounterResult(
      repetitionCount: _reps,
      phase: _phase,
      isRepetitionCompleted: repetitionCompleted,
      kneeAngle: angle,
      isValidTracking: true,
      consecutiveDownFrames: _consecutiveDown,
      consecutiveUpFrames: _consecutiveUp,
      feedbackMessage: feedback,
      isSimulated: isSimulated,
    );
  }
}
