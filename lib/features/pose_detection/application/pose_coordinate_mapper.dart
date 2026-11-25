import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/pose_overlay_state.dart';

/// Mapped 2D leg segment ready for [CustomPainter] rendering in overlay space.
class MappedLegSegment {
  final Offset hip;
  final Offset knee;
  final Offset ankle;

  const MappedLegSegment({
    required this.hip,
    required this.knee,
    required this.ankle,
  });
}

/// Mapped 2D arm segment (`shoulder -> elbow -> wrist`) ready for
/// [CustomPainter] rendering in overlay space.
class MappedArmSegment {
  final Offset shoulder;
  final Offset elbow;
  final Offset wrist;

  const MappedArmSegment({
    required this.shoulder,
    required this.elbow,
    required this.wrist,
  });
}

/// Pure, deterministic coordinate transformation from Google ML Kit image-space
/// landmarks to Flutter overlay-space coordinates.
///
/// Accounts for:
/// - [InputImageRotation] (swapping image width/height for 90° and 270°)
/// - Preview scaling and [BoxFit] cropping/letterboxing (`BoxFit.cover` / `BoxFit.contain`)
/// - Front-camera horizontal mirroring matching Android [CameraPreview]
abstract final class PoseCoordinateMapper {
  /// Returns the effective upright image size after ML Kit applies [rotation].
  static Size effectiveImageSize(
    Size rawImageSize,
    InputImageRotation rotation,
  ) {
    return switch (rotation) {
      InputImageRotation.rotation90deg ||
      InputImageRotation.rotation270deg =>
        Size(rawImageSize.height, rawImageSize.width),
      InputImageRotation.rotation0deg ||
      InputImageRotation.rotation180deg =>
        rawImageSize,
    };
  }

  /// Maps an image-space [point] to overlay-space coordinates within [previewSize].
  ///
  /// Returns `null` if [rawImageSize] or [previewSize] is empty, or if the
  /// mapped coordinate falls outside [previewSize] bounds.
  static Offset? mapPoint({
    required Offset point,
    required Size rawImageSize,
    required InputImageRotation rotation,
    required Size previewSize,
    required bool isFrontCamera,
    BoxFit fit = BoxFit.cover,
  }) {
    if (rawImageSize.isEmpty || previewSize.isEmpty) return null;
    if (!point.dx.isFinite || !point.dy.isFinite) return null;

    final upright = effectiveImageSize(rawImageSize, rotation);
    if (upright.width <= 0 || upright.height <= 0) return null;

    final scaleX = previewSize.width / upright.width;
    final scaleY = previewSize.height / upright.height;
    final double scale = switch (fit) {
      BoxFit.cover => math.max(scaleX, scaleY),
      _ => math.min(scaleX, scaleY),
    };

    final scaledWidth = upright.width * scale;
    final scaledHeight = upright.height * scale;
    final offsetX = (previewSize.width - scaledWidth) / 2.0;
    final offsetY = (previewSize.height - scaledHeight) / 2.0;

    final rawMappedX = point.dx * scale + offsetX;
    final mappedY = point.dy * scale + offsetY;
    final mappedX = isFrontCamera ? (previewSize.width - rawMappedX) : rawMappedX;

    if (mappedX < 0 ||
        mappedX > previewSize.width ||
        mappedY < 0 ||
        mappedY > previewSize.height) {
      return null;
    }

    return Offset(mappedX, mappedY);
  }

  /// Maps all 3 joints of [leg] (`hip -> knee -> ankle`) into overlay space.
  /// Returns `null` if any joint fails reliability or falls out of bounds.
  static MappedLegSegment? mapLeg({
    required LegLandmarks leg,
    required Size rawImageSize,
    required InputImageRotation rotation,
    required Size previewSize,
    required bool isFrontCamera,
    required double likelihoodThreshold,
    BoxFit fit = BoxFit.cover,
  }) {
    if (!leg.isReliable(likelihoodThreshold)) return null;

    final hip = mapPoint(
      point: leg.hip.imagePoint,
      rawImageSize: rawImageSize,
      rotation: rotation,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      fit: fit,
    );
    final knee = mapPoint(
      point: leg.knee.imagePoint,
      rawImageSize: rawImageSize,
      rotation: rotation,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      fit: fit,
    );
    final ankle = mapPoint(
      point: leg.ankle.imagePoint,
      rawImageSize: rawImageSize,
      rotation: rotation,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      fit: fit,
    );

    if (hip == null || knee == null || ankle == null) return null;
    return MappedLegSegment(hip: hip, knee: knee, ankle: ankle);
  }

  /// Maps all 3 joints of [arm] (`shoulder -> elbow -> wrist`) into overlay
  /// space. Returns `null` if any joint fails reliability or falls out of bounds.
  static MappedArmSegment? mapArm({
    required ArmLandmarks arm,
    required Size rawImageSize,
    required InputImageRotation rotation,
    required Size previewSize,
    required bool isFrontCamera,
    required double likelihoodThreshold,
    BoxFit fit = BoxFit.cover,
  }) {
    if (!arm.isReliable(likelihoodThreshold)) return null;

    final shoulder = mapPoint(
      point: arm.shoulder.imagePoint,
      rawImageSize: rawImageSize,
      rotation: rotation,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      fit: fit,
    );
    final elbow = mapPoint(
      point: arm.elbow.imagePoint,
      rawImageSize: rawImageSize,
      rotation: rotation,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      fit: fit,
    );
    final wrist = mapPoint(
      point: arm.wrist.imagePoint,
      rawImageSize: rawImageSize,
      rotation: rotation,
      previewSize: previewSize,
      isFrontCamera: isFrontCamera,
      fit: fit,
    );

    if (shoulder == null || elbow == null || wrist == null) return null;
    return MappedArmSegment(shoulder: shoulder, elbow: elbow, wrist: wrist);
  }
}
