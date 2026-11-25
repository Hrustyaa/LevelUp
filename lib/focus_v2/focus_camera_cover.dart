import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

/// Full-bleed preview helper for the EXISTING CameraController.
/// The underlying camera stream should NOT be recreated when count updates.
Widget focusV2CameraCover(CameraController controller) {
  final preview = controller.value.previewSize;
  if (preview == null) return CameraPreview(controller);
  return OrientationBuilder(
    builder: (context, orientation) {
      final portrait = orientation == Orientation.portrait;
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: portrait ? preview.height : preview.width,
              height: portrait ? preview.width : preview.height,
              child: CameraPreview(controller),
            ),
          ),
        ),
      );
    },
  );
}
