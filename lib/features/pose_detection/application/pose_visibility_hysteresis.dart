/// Tracked visibility state for a single limb (leg or arm) in the visual overlay.
enum LimbVisibilityStatus {
  /// Not yet established, or hidden after sustained tracking loss.
  hidden,

  /// Actively tracked with high confidence (`minLikelihood >= enterThreshold`).
  confident,

  /// Temporary low confidence (`exitThreshold <= minLikelihood < enterThreshold`)
  /// or brief dropout within [PoseVisibilityHysteresis.gracePeriod].
  /// Rendered with reduced opacity and never lime-green.
  uncertain,
}

/// Result returned by [PoseVisibilityHysteresis.update] for one limb.
class LimbVisibilityResult<T> {
  final T? value;
  final LimbVisibilityStatus status;

  const LimbVisibilityResult({
    required this.value,
    required this.status,
  });

  bool get isVisible => status != LimbVisibilityStatus.hidden && value != null;
  bool get isConfident => status == LimbVisibilityStatus.confident;
  bool get isUncertain => status == LimbVisibilityStatus.uncertain;
}

class _LimbEntry<T> {
  T lastValue;
  DateTime lastConfidentAt;
  LimbVisibilityStatus status;

  _LimbEntry({
    required this.lastValue,
    required this.lastConfidentAt,
    required this.status,
  });
}

/// Time-aware visibility hysteresis for visual pose overlay limbs.
///
/// Prevents flickering when ML Kit landmark confidence hovers around a single
/// hard threshold or drops out for a single frame:
/// - **Enter:** requires `minLikelihood >= enterThreshold` (default `0.55`).
/// - **Stay confident:** `minLikelihood >= enterThreshold` updates `lastConfidentAt`.
/// - **Uncertain (soft):** `exitThreshold <= minLikelihood < enterThreshold`
///   (`0.35..0.55`) keeps the limb visible in [LimbVisibilityStatus.uncertain]
///   for up to [gracePeriod] (`250 ms`) since the last confident frame.
/// - **Grace hold:** if `candidate == null` or `minLikelihood < exitThreshold`,
///   holds the last genuinely observed limb in [LimbVisibilityStatus.uncertain]
///   only while `now.difference(lastConfidentAt) <= gracePeriod`.
/// - **Prompt hide:** once `now.difference(lastConfidentAt) > gracePeriod`,
///   transitions to [LimbVisibilityStatus.hidden] and clears the held limb so
///   stale coordinates never remain frozen.
///
/// Strictly cosmetic: never fabricates coordinates and never feeds held/uncertain
/// landmarks into [SquatCounter] or [PushUpCounter].
class PoseVisibilityHysteresis<K, T> {
  final double enterThreshold;
  final double exitThreshold;
  final Duration gracePeriod;

  final Map<K, _LimbEntry<T>> _entries = {};

  PoseVisibilityHysteresis({
    this.enterThreshold = 0.55,
    this.exitThreshold = 0.35,
    this.gracePeriod = const Duration(milliseconds: 250),
  });

  /// Evaluates visibility for [key] at [now].
  ///
  /// [candidate] should be `null` if any required joint is missing or non-finite.
  /// [minLikelihood] is the minimum ML Kit likelihood across the limb's joints.
  LimbVisibilityResult<T> update({
    required K key,
    required T? candidate,
    required double minLikelihood,
    required DateTime now,
  }) {
    final existing = _entries[key];

    if (candidate != null && minLikelihood >= enterThreshold) {
      _entries[key] = _LimbEntry<T>(
        lastValue: candidate,
        lastConfidentAt: now,
        status: LimbVisibilityStatus.confident,
      );
      return LimbVisibilityResult<T>(
        value: candidate,
        status: LimbVisibilityStatus.confident,
      );
    }

    // Not currently tracked — require enterThreshold to establish.
    if (existing == null) {
      return const LimbVisibilityResult(
        value: null,
        status: LimbVisibilityStatus.hidden,
      );
    }

    final elapsed = now.difference(existing.lastConfidentAt);
    if (elapsed > gracePeriod || elapsed.isNegative) {
      _entries.remove(key);
      return const LimbVisibilityResult(
        value: null,
        status: LimbVisibilityStatus.hidden,
      );
    }

    // Within bounded grace period:
    // - If candidate is still above soft exitThreshold, show updated position
    //   as uncertain.
    // - If candidate dropped below exitThreshold or is null, hold lastValue as
    //   uncertain without fabricating new coordinates.
    if (candidate != null && minLikelihood >= exitThreshold) {
      existing.lastValue = candidate;
    }
    existing.status = LimbVisibilityStatus.uncertain;

    return LimbVisibilityResult<T>(
      value: existing.lastValue,
      status: LimbVisibilityStatus.uncertain,
    );
  }

  /// Clears all held visibility state (call on tracking loss, cancel,
  /// camera release, session restart, or disposal).
  void reset() => _entries.clear();
}
