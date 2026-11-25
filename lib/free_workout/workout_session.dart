/// Pure-Dart workout model. No Focus/Accessibility/temporary-access calls.
/// The counter receives *detected knee angles* only, never button presses.
class ContinuousSquatCounter {
  static const stableFrames = 2;
  int _reps = 0;
  int _matchingFrames = 0;
  _SquatPhase _phase = _SquatPhase.findStanding;

  int get reps => _reps;

  void reset() {
    _reps = 0;
    resetTracking();
  }

  /// Require a stable standing pose again after tracking loss / pause.
  void resetTracking() {
    _matchingFrames = 0;
    _phase = _SquatPhase.findStanding;
  }

  void update(double? kneeAngle) {
    if (kneeAngle == null || !kneeAngle.isFinite) {
      resetTracking();
      return;
    }
    final matches = switch (_phase) {
      _SquatPhase.findStanding || _SquatPhase.rise => kneeAngle > 155,
      _SquatPhase.lower => kneeAngle < 125,
    };
    _matchingFrames = matches ? _matchingFrames + 1 : 0;
    if (_matchingFrames < stableFrames) return;
    _matchingFrames = 0;
    switch (_phase) {
      case _SquatPhase.findStanding:
        _phase = _SquatPhase.lower;
      case _SquatPhase.lower:
        _phase = _SquatPhase.rise;
      case _SquatPhase.rise:
        _reps++;
        _phase = _SquatPhase.lower;
    }
  }
}

enum _SquatPhase { findStanding, lower, rise }

enum WorkoutStage { counting, resting, finished }

class WorkoutSession {
  WorkoutSession({DateTime? startedAt})
    : startedAt = startedAt ?? DateTime.now();

  final DateTime startedAt;
  final ContinuousSquatCounter _counter = ContinuousSquatCounter();
  final List<int> _sets = [];
  WorkoutStage _stage = WorkoutStage.counting;
  bool _paused = false;
  DateTime? _endedAt;

  WorkoutStage get stage => _stage;
  bool get paused => _paused;
  bool get isCounting => _stage == WorkoutStage.counting && !_paused;
  int get currentReps => _counter.reps;
  int get setNumber => _sets.length + 1;
  List<int> get completedSets => List.unmodifiable(_sets);
  int get totalReps => _sets.fold(0, (sum, next) => sum + next);
  DateTime? get endedAt => _endedAt;

  void onDetectedKneeAngle(double? angle) {
    if (isCounting) _counter.update(angle);
  }

  void pause() {
    if (_stage != WorkoutStage.counting) return;
    _paused = true;
    _counter.resetTracking();
  }

  void resume() {
    if (_stage != WorkoutStage.counting) return;
    _counter.resetTracking();
    _paused = false;
  }

  /// A zero-rep set is not recorded, and cannot become a fake achievement.
  bool finishSet() {
    if (!isCounting || _counter.reps == 0) return false;
    _sets.add(_counter.reps);
    _stage = WorkoutStage.resting;
    _paused = false;
    _counter.reset();
    return true;
  }

  void nextSet() {
    if (_stage != WorkoutStage.resting) return;
    _counter.reset();
    _paused = false;
    _stage = WorkoutStage.counting;
  }

  /// Save the current partial set when the user explicitly ends a workout.
  WorkoutResult? finish({DateTime? endedAt}) {
    if (_stage == WorkoutStage.finished) return null;
    if (_stage == WorkoutStage.counting && _counter.reps > 0) {
      _sets.add(_counter.reps);
    }
    _stage = WorkoutStage.finished;
    _paused = true;
    _endedAt = endedAt ?? DateTime.now();
    if (_sets.isEmpty) return null;
    return WorkoutResult(
      exercise: 'squat',
      startedAt: startedAt,
      endedAt: _endedAt!,
      sets: List.unmodifiable(_sets),
    );
  }
}

class WorkoutResult {
  const WorkoutResult({
    required this.exercise,
    required this.startedAt,
    required this.endedAt,
    required this.sets,
  });
  final String exercise;
  final DateTime startedAt, endedAt;
  final List<int> sets;
  int get totalReps => sets.fold(0, (sum, next) => sum + next);
  int get durationSeconds =>
      endedAt.difference(startedAt).inSeconds.clamp(0, 86400).toInt();

  Map<String, dynamic> toJson() => {
    'exercise': exercise,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'sets': sets,
  };

  factory WorkoutResult.fromJson(Map<String, dynamic> data) {
    final values = (data['sets'] as List<dynamic>).cast<int>();
    if (values.isEmpty || values.any((value) => value <= 0)) {
      throw const FormatException('Invalid workout sets');
    }
    return WorkoutResult(
      exercise: data['exercise'] as String,
      startedAt: DateTime.parse(data['startedAt'] as String),
      endedAt: DateTime.parse(data['endedAt'] as String),
      sets: List.unmodifiable(values),
    );
  }
}
