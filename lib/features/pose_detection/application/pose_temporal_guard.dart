import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Temporal outlier rejection for overlay landmarks **only**.
///
/// Rejects single-frame landmark jumps that are physically implausible given
/// a known maximum-movement budget expressed as a fraction of the input image
/// dimension. Never touches [SquatCounter] inputs.
///
/// Usage:
/// ```dart
/// final guard = PoseTemporalGuard();
/// if (guard.isPlausible(type, raw, imageSize)) {
///   guard.update(type, raw);
///   // use raw for overlay
/// } else {
///   // skip or use previous smoothed value
/// }
/// ```
class PoseTemporalGuard {
  /// Maximum normalised displacement per frame considered plausible.
  ///
  /// A value of 0.25 means a landmark may not jump more than 25 % of the
  /// longest image dimension in a single frame.
  final double maxNormalizedJump;

  /// Number of consecutive rejected frames before accepting a relocation so
  /// legitimate fast movement or repositioning never freezes the overlay.
  final int maxConsecutiveRejections;

  final Map<PoseLandmarkType, Offset> _last = {};
  final Map<PoseLandmarkType, int> _rejections = {};

  PoseTemporalGuard({
    this.maxNormalizedJump = 0.25,
    this.maxConsecutiveRejections = 2,
  });

  /// Returns the last accepted position for [type], or `null` if none yet.
  Offset? lastPosition(PoseLandmarkType type) => _last[type];

  /// Returns `true` if the displacement from the last known position to [raw]
  /// is within the plausible range, or if this is the first observation for
  /// [type], or if [maxConsecutiveRejections] has been reached.
  ///
  /// [imageSize] is the raw ML Kit input image size (before any rotation).
  bool isPlausible(PoseLandmarkType type, Offset raw, Size imageSize) {
    final prev = _last[type];
    if (prev == null) {
      _rejections[type] = 0;
      return true; // First observation — always accept.
    }

    final normDim = math.max(imageSize.width, imageSize.height);
    if (normDim <= 0) {
      _rejections[type] = 0;
      return true;
    }

    final displacement = (raw - prev).distance;
    if (displacement <= maxNormalizedJump * normDim) {
      _rejections[type] = 0;
      return true;
    }

    final count = (_rejections[type] ?? 0) + 1;
    if (count >= maxConsecutiveRejections) {
      // Sustained displacement across multiple frames → legitimate relocation.
      _rejections[type] = 0;
      return true;
    }

    _rejections[type] = count;
    return false;
  }

  /// Updates the last-known position for [type] to [position].
  ///
  /// Call this only after deciding to accept the new position (i.e., after
  /// [isPlausible] returned `true`).
  void update(PoseLandmarkType type, Offset position) {
    _last[type] = position;
    _rejections[type] = 0;
  }

  /// Clears all stored last-known positions and rejection counters.
  void reset() {
    _last.clear();
    _rejections.clear();
  }
}
