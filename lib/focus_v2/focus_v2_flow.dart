import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'focus_v2_models.dart';
import 'focus_v2_screens.dart';
import 'focus_v2_style.dart';

/// Adapter for the EXISTING ML Kit challenge: return its camera preview and
/// call [onReading] only with real, detector-verified progress.
/// The builder does NOT create an independent access grant mechanism.
typedef FocusCameraBuilder =
    Widget Function(
      BuildContext context,
      ValueChanged<FocusPoseReading> onReading,
    );

typedef FocusNativeGrant =
    Future<VerifiedFocusGrant> Function(FocusTarget target);
typedef FocusOpenTarget = Future<void> Function(FocusTarget target);

enum FocusV2Step { gate, camera, verifying, success, error }

/// Flutter side of the UI flow, to be wired into existing native APIs.
/// The actual Accessibility overlay Gate is native, so this Dart Gate is also
/// useful for UI previews and for Flutter-owned entry points.
class FocusExperienceV2 extends StatefulWidget {
  const FocusExperienceV2({
    super.key,
    required this.target,
    required this.language,
    required this.cameraBuilder,
    required this.requestVerifiedAccess,
    required this.openTarget,
    required this.exitFlow,
    this.onCameraCancel,
    this.goalReps = 5,
    this.offeredAccessMinutes = 5,
  }) : assert(goalReps > 0),
       assert(offeredAccessMinutes > 0);

  final FocusTarget target;
  final String language;
  final FocusCameraBuilder cameraBuilder;
  final FocusNativeGrant requestVerifiedAccess;
  final FocusOpenTarget openTarget;
  final VoidCallback exitFlow;
  final VoidCallback? onCameraCancel;
  final int goalReps;
  final int offeredAccessMinutes;

  @override
  State<FocusExperienceV2> createState() => _FocusExperienceV2State();
}

class _FocusExperienceV2State extends State<FocusExperienceV2> {
  FocusV2Step _step = FocusV2Step.gate;
  int _session = 0;
  VerifiedFocusGrant? _grant;
  String? _error;
  bool _openingApp = false;

  void _start() {
    _session++;
    setState(() {
      _grant = null;
      _error = null;
      _step = FocusV2Step.camera;
    });
  }

  void _cancel() {
    // Invalidates an in-flight native result, so late callbacks cannot show success.
    _session++;
    widget.onCameraCancel?.call();
    setState(() {
      _step = FocusV2Step.gate;
      _grant = null;
      _error = null;
    });
  }

  void _onReading(FocusPoseReading reading) {
    if (_step != FocusV2Step.camera) return;
    if (reading.repetitions >= widget.goalReps) {
      unawaited(_verifyGrant());
    }
  }

  Future<void> _verifyGrant() async {
    if (_step != FocusV2Step.camera) return;
    final token = ++_session;
    setState(() => _step = FocusV2Step.verifying);
    try {
      final granted = await widget.requestVerifiedAccess(widget.target);
      if (!mounted || token != _session) return;
      if (granted.isConfirmedAt(DateTime.now())) {
        setState(() {
          _grant = granted;
          _step = FocusV2Step.success;
        });
      } else {
        setState(() {
          _error =
              granted.error ??
              focusV2Tr(
                widget.language,
                'Не удалось подтвердить доступ.',
                'Could not verify access.',
                'Қолжетімділікті растау мүмкін болмады.',
              );
          _step = FocusV2Step.error;
        });
      }
    } catch (_) {
      if (!mounted || token != _session) return;
      setState(() {
        _error = focusV2Tr(
          widget.language,
          'Не удалось подтвердить доступ. Попробуй ещё раз.',
          'Could not verify access. Please try again.',
          'Қолжетімділік расталмады. Қайта байқап көр.',
        );
        _step = FocusV2Step.error;
      });
    }
  }

  Future<void> _openApp() async {
    if (_openingApp) return;
    _openingApp = true;
    try {
      await widget.openTarget(widget.target);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = focusV2Tr(
          widget.language,
          'Не удалось открыть приложение.',
          'Could not open the app.',
          'Қолданбаны ашу мүмкін болмады.',
        );
        _step = FocusV2Step.error;
      });
    } finally {
      _openingApp = false;
    }
  }

  void _onSystemBack() {
    if (_step == FocusV2Step.camera || _step == FocusV2Step.verifying) {
      _cancel();
    } else {
      widget.exitFlow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onSystemBack();
      },
      child: switch (_step) {
        FocusV2Step.gate => FocusV2GateScreen(
          target: widget.target,
          language: widget.language,
          goalReps: widget.goalReps,
          accessMinutes: widget.offeredAccessMinutes,
          onStart: _start,
        ),
        FocusV2Step.camera || FocusV2Step.verifying => _FocusCameraStage(
          key: const ValueKey('focus_v2_camera_stage'),
          cameraBuilder: widget.cameraBuilder,
          onReading: _onReading,
          language: widget.language,
          goalReps: widget.goalReps,
          verifying: _step == FocusV2Step.verifying,
        ),
        FocusV2Step.success => FocusV2SuccessScreen(
          target: widget.target,
          language: widget.language,
          accessMinutes: _grant!.remainingWholeMinutesAt(DateTime.now()),
          goalReps: widget.goalReps,
          onOpenApp: () => unawaited(_openApp()),
        ),
        FocusV2Step.error => FocusV2ErrorScreen(
          message: _error ?? 'Ошибка',
          language: widget.language,
          onRetry: _start,
        ),
      },
    );
  }
}

/// Keeps the expensive preview instance stable as the counter updates.
class _FocusCameraStage extends StatefulWidget {
  const _FocusCameraStage({
    super.key,
    required this.cameraBuilder,
    required this.onReading,
    required this.language,
    required this.goalReps,
    required this.verifying,
  });

  final FocusCameraBuilder cameraBuilder;
  final ValueChanged<FocusPoseReading> onReading;
  final String language;
  final int goalReps;
  final bool verifying;

  @override
  State<_FocusCameraStage> createState() => _FocusCameraStageState();
}

class _FocusCameraStageState extends State<_FocusCameraStage> {
  final ValueNotifier<FocusPoseReading> _reading = ValueNotifier(
    const FocusPoseReading(repetitions: 0, poseDetected: false),
  );
  Widget? _stablePreview;

  void _onReading(FocusPoseReading value) {
    if (!mounted || widget.verifying) return;
    final old = _reading.value;
    // Counters should not move backward within one fixed Focus challenge.
    final progress = value.repetitions.clamp(0, widget.goalReps).toInt();
    final next = FocusPoseReading(
      repetitions: progress > old.repetitions ? progress : old.repetitions,
      poseDetected: value.poseDetected,
    );
    if (next.repetitions != old.repetitions ||
        next.poseDetected != old.poseDetected) {
      _reading.value = next;
    }
    widget.onReading(next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stablePreview ??= widget.cameraBuilder(context, _onReading);
  }

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<FocusPoseReading>(
        valueListenable: _reading,
        child: _stablePreview,
        builder: (context, reading, preview) => FocusV2CameraScreen(
          cameraPreview:
              preview ?? const ColoredBox(color: FocusV2Style.surface),
          repetitions: reading.repetitions,
          poseDetected: reading.poseDetected,
          language: widget.language,
          goalReps: widget.goalReps,
          verifying: widget.verifying,
        ),
      );
}
