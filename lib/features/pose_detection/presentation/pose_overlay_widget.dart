import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/pose_overlay_state.dart';
import 'pose_overlay_painter.dart';

/// Non-interactive, frame-reactive skeleton overlay layered over [CameraPreview].
///
/// Uses [ValueListenableBuilder] + [RepaintBoundary] so pose landmark updates
/// repaint only the overlay without rebuilding the surrounding challenge UI,
/// and [IgnorePointer] so touch input passes straight through.
class PoseOverlayWidget extends StatelessWidget {
  final ValueListenable<PoseOverlayState> listenable;
  final BoxFit fit;

  const PoseOverlayWidget({
    super.key,
    required this.listenable,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ValueListenableBuilder<PoseOverlayState>(
          valueListenable: listenable,
          builder: (context, state, _) {
            return CustomPaint(
              painter: PoseOverlayPainter(state: state, fit: fit),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}
