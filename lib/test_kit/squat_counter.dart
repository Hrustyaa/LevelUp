enum SquatPhase { findStanding, lower, rise }

class SquatCounter {
  static const goal = 5;
  static const _stableFrames = 2;

  int _reps = 0;
  int _matchingFrames = 0;
  SquatPhase _phase = SquatPhase.findStanding;

  int get reps => _reps;
  SquatPhase get phase => _phase;
  bool get isComplete => _reps >= goal;

  void update(double? angle) {
    if (isComplete) return;
    if (angle == null) {
      _matchingFrames = 0;
      _phase = SquatPhase.findStanding;
      return;
    }

    final matches = switch (_phase) {
      SquatPhase.findStanding || SquatPhase.rise => angle > 155,
      SquatPhase.lower => angle < 125,
    };
    _matchingFrames = matches ? _matchingFrames + 1 : 0;
    if (_matchingFrames < _stableFrames) return;

    _matchingFrames = 0;
    switch (_phase) {
      case SquatPhase.findStanding:
        _phase = SquatPhase.lower;
      case SquatPhase.lower:
        _phase = SquatPhase.rise;
      case SquatPhase.rise:
        _reps++;
        _phase = SquatPhase.lower;
    }
  }
}
