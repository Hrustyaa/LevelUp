import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Internal per-landmark state for the One Euro Filter.
class _LandmarkState {
  Offset smoothed;
  Offset velocity;
  DateTime timestamp;
  int frameCount;

  _LandmarkState({
    required this.smoothed,
    required this.timestamp,
  })  : velocity = Offset.zero,
        frameCount = 1;
}

/// Applies a **One Euro Filter** to per-landmark [Offset] positions for the
/// visual overlay **only**.
///
/// The One Euro Filter is velocity-adaptive: it suppresses jitter aggressively
/// when the landmark is nearly stationary (low cutoff frequency) and passes
/// fast movement through with minimal lag (high cutoff frequency).
///
/// Formulas:
/// - `alpha = 2π·fc / (2π·fc + rate)` where `rate = 1/dt`
/// - `fc = cutoff_min + beta * |velocity|`
/// - Velocity EMA: `vel = alpha_d * (raw - prev)/dt + (1 - alpha_d) * vel_prev`
/// - `alpha_d` derived from `cutoff_d = 1.0 Hz`
///
/// Raw landmark coordinates are still forwarded unchanged to [SquatGeometry]
/// and [SquatCounter] — smoothing is purely cosmetic.
///
/// Call [reset] whenever a session starts or tracking is lost so that stale
/// positions from a previous session do not bleed into the new one.
class PoseLandmarkSmoother {
  /// Minimum cutoff frequency in Hz (governs smoothing at rest).
  final double minCutoff;

  /// Speed coefficient: how quickly the cutoff rises with velocity.
  final double beta;

  /// Cutoff frequency for the derivative (velocity) EMA in Hz.
  final double derivateCutoff;

  final Map<PoseLandmarkType, _LandmarkState> _states = {};

  PoseLandmarkSmoother({
    this.minCutoff = 1.5,
    this.beta = 0.007,
    this.derivateCutoff = 1.0,
  });

  /// Returns `true` once at least 2 frames have been processed for [type],
  /// indicating that the filter has fully settled for that landmark.
  bool waitForEstablishment(PoseLandmarkType type) {
    final state = _states[type];
    return state != null && state.frameCount >= 2;
  }

  /// Returns the One Euro filtered [Offset] for [type] given the new [raw]
  /// reading at [timestamp].
  ///
  /// - First observation: returns [raw] and initialises state (no lag).
  /// - `dt > 0.5 s` (tracking gap): resets state, returns [raw].
  /// - `dt <= 0` or non-finite: uses `alpha = 0.5` as a safe fallback.
  Offset smooth(
    PoseLandmarkType type,
    Offset raw, {
    required DateTime timestamp,
  }) {
    final prev = _states[type];

    // First observation — initialise and return raw.
    if (prev == null) {
      _states[type] = _LandmarkState(smoothed: raw, timestamp: timestamp);
      return raw;
    }

    final dt =
        timestamp.difference(prev.timestamp).inMicroseconds / 1e6; // seconds

    // Large tracking gap — reset to raw.
    if (dt > 0.5) {
      _states[type] = _LandmarkState(smoothed: raw, timestamp: timestamp);
      return raw;
    }

    // Safe alpha for degenerate dt.
    double alpha;

    if (dt <= 0 || !dt.isFinite) {
      alpha = 0.5;
    } else {
      final rate = 1.0 / dt;

      // Derivative (velocity) EMA alpha.
      final tauD = 1.0 / (2.0 * math.pi * derivateCutoff);
      final alphaD = 1.0 / (1.0 + tauD * rate);

      // Instantaneous velocity (pixels/s) for each axis.
      final rawVelX = (raw.dx - prev.smoothed.dx) / dt;
      final rawVelY = (raw.dy - prev.smoothed.dy) / dt;

      // EMA-smoothed velocity.
      final velX = alphaD * rawVelX + (1.0 - alphaD) * prev.velocity.dx;
      final velY = alphaD * rawVelY + (1.0 - alphaD) * prev.velocity.dy;
      final velMag = math.sqrt(velX * velX + velY * velY);

      // Adaptive cutoff and alpha.
      final cutoff = minCutoff + beta * velMag;
      final tau = 1.0 / (2.0 * math.pi * cutoff);
      alpha = 1.0 / (1.0 + tau * rate);

      // Update velocity in state.
      prev.velocity = Offset(velX, velY);
    }

    // Apply EMA with computed alpha.
    final smoothedX = prev.smoothed.dx + alpha * (raw.dx - prev.smoothed.dx);
    final smoothedY = prev.smoothed.dy + alpha * (raw.dy - prev.smoothed.dy);
    final smoothed = Offset(smoothedX, smoothedY);

    prev.smoothed = smoothed;
    prev.timestamp = timestamp;
    prev.frameCount++;

    return smoothed;
  }

  /// Clears all stored per-landmark state.
  ///
  /// Call on session [start] and whenever poses become empty / tracking is
  /// lost, so that the next detection cycle starts fresh.
  void reset() => _states.clear();
}
