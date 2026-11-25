/// Optional helper for the EXISTING camera's onImage callback.
/// Processes at most one frame at a time, dropping excess frames. No cameras,
/// detectors or access grants are created by this utility.
class FocusFrameLimiter {
  FocusFrameLimiter({
    this.minimumSpacing = const Duration(milliseconds: 70),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration minimumSpacing;
  final DateTime Function() _clock;
  bool _busy = false;
  int _generation = 0;
  DateTime? _lastStarted;

  bool get busy => _busy;
  bool isCurrent(int generation) => generation == _generation;

  /// Cancel stale results when camera closes, app pauses, or challenge ends.
  /// A running operation remains marked busy until it actually finishes.
  void invalidate() {
    _generation++;
  }

  /// Use `unawaited(limiter.submit((token) async { ... }))` from onImage.
  /// Check `limiter.isCurrent(token)` before publishing pose results.
  Future<bool> submit(Future<void> Function(int token) process) async {
    final now = _clock();
    if (_busy ||
        (_lastStarted != null &&
            now.difference(_lastStarted!) < minimumSpacing)) {
      return false;
    }
    _busy = true;
    _lastStarted = now;
    final token = _generation;
    try {
      await process(token);
    } finally {
      _busy = false;
    }
    return true;
  }
}
