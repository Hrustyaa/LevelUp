import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:material_ui/material_ui.dart';

/// Full-bleed preview helper for the EXISTING CameraController.
/// The underlying camera stream should NOT be recreated when count updates.
Widget focusV2CameraCover(CameraController controller, {Widget? overlay}) =>
    ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      child: overlay,
      builder: (context, value, child) {
        final preview = value.previewSize;
        if (preview == null) return CameraPreview(controller, child: child);
        final orientation = value.isRecordingVideo
            ? value.recordingOrientation ?? value.deviceOrientation
            : value.previewPauseOrientation ??
                  value.lockedCaptureOrientation ??
                  value.deviceOrientation;
        final landscape =
            orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        return ClipRect(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: landscape ? preview.width : preview.height,
                height: landscape ? preview.height : preview.width,
                child: CameraPreview(controller, child: child),
              ),
            ),
          ),
        );
      },
    );
