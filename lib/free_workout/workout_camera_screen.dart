import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../focus_experience/focus_style.dart';
import 'workout_session.dart';

/// Separate from the Focus gate's ChallengeScreen; never calls grantAccess.
/// Returns a real result with per-set repetitions, or null when discarded.
class FreeWorkoutCameraScreen extends StatefulWidget {
  const FreeWorkoutCameraScreen({super.key, required this.language});

  final String language;

  @override
  State<FreeWorkoutCameraScreen> createState() =>
      _FreeWorkoutCameraScreenState();
}

class _FreeWorkoutCameraScreenState extends State<FreeWorkoutCameraScreen>
    with WidgetsBindingObserver {
  final WorkoutSession _workout = WorkoutSession();
  final PoseDetector _detector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _camera;
  Future<void> _cameraTask = Future<void>.value();
  Future<void>? _frameTask;
  bool _inForeground = true;
  bool _disposed = false;
  bool _openingFailed = false;
  bool _cameraWasStarted = false;
  bool _exitPromptOpen = false;
  bool _closing = false;
  int _captureEpoch = 0;
  bool _poseFound = false;
  String? _cameraError;
  String _tr(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  bool get _wantsCamera =>
      !_disposed &&
      !_exitPromptOpen &&
      !_closing &&
      _inForeground &&
      !_openingFailed &&
      _workout.isCounting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (!_inForeground) _resetCapture();
    if (_cameraWasStarted &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      _workout.pause();
    }
    if (mounted) setState(() {});
    _syncCamera();
  }

  void _resetCapture() {
    _captureEpoch++;
    _poseFound = false;
    _workout.onDetectedKneeAngle(null);
  }

  void _syncCamera() {
    _cameraTask = _cameraTask
        .then((_) async {
          if (!_wantsCamera) {
            final old = _camera;
            _camera = null;
            if (old != null) {
              if (mounted && !_disposed) setState(() {});
              await old.dispose();
            }
          } else if (_camera == null) {
            await _openCamera();
          }
        })
        .catchError((Object error) {
          debugPrint('Free workout camera lifecycle: $error');
        });
  }

  Future<void> _openCamera() async {
    CameraController? created;
    try {
      final cameras = await availableCameras();
      if (!_wantsCamera) return;
      if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found');
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      created = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await created.initialize();
      if (!_wantsCamera) return;
      final initialized = created;
      await initialized.startImageStream(
        (frame) => _onFrame(initialized, frame),
      );
      if (!_wantsCamera || !mounted) return;
      setState(() {
        _camera = initialized;
        _cameraWasStarted = true;
        _cameraError = null;
      });
      created = null;
    } on CameraException catch (error) {
      final denied = error.code.startsWith('CameraAccessDenied');
      if (_disposed || !mounted || (!_inForeground && !denied)) return;
      _openingFailed = true;
      _cameraError = denied
          ? _tr(
              'Разреши доступ к камере в настройках телефона.',
              'Allow camera access in Android Settings.',
              'Телефон баптауларынан камераға рұқсат бер.',
            )
          : _tr(
              'Не удалось запустить камеру.',
              'Could not open the camera.',
              'Камера ашылмады.',
            );
      setState(() {});
    } catch (error) {
      if (_disposed || !mounted || !_inForeground) return;
      debugPrint('Free workout camera: $error');
      _openingFailed = true;
      _cameraError = _tr(
        'Не удалось запустить камеру.',
        'Could not open the camera.',
        'Камера ашылмады.',
      );
      setState(() {});
    } finally {
      if (created != null) await created.dispose();
    }
  }

  InputImage? _toInput(CameraController active, CameraImage image) {
    if (image.planes.length != 1) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format != InputImageFormat.nv21) return null;
    final orientation = _orientations[active.value.deviceOrientation];
    if (orientation == null) return null;
    final sensor = active.description.sensorOrientation;
    final rotationDegrees =
        active.description.lensDirection == CameraLensDirection.front
        ? (sensor + orientation) % 360
        : (sensor - orientation + 360) % 360;
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) return null;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void _onFrame(CameraController camera, CameraImage image) {
    if (!_wantsCamera || _camera != camera || _frameTask != null) return;
    final input = _toInput(camera, image);
    if (input == null) {
      _openingFailed = true;
      _cameraError = _tr(
        'Формат кадров камеры не поддерживается.',
        'Unsupported camera frame format.',
        'Камера кадрының пішімі қолдау таппайды.',
      );
      if (mounted) setState(() {});
      _syncCamera();
      return;
    }
    _frameTask = _processFrame(camera, input, _captureEpoch).whenComplete(() {
      _frameTask = null;
    });
  }

  Future<void> _processFrame(
    CameraController camera,
    InputImage input,
    int epoch,
  ) async {
    try {
      final poses = await _detector.processImage(input);
      if (!mounted ||
          !_wantsCamera ||
          _camera != camera ||
          epoch != _captureEpoch) {
        return;
      }
      final angle = poses.isEmpty ? null : _kneeAngle(poses.first);
      final previousReps = _workout.currentReps;
      _workout.onDetectedKneeAngle(angle);
      final found = angle != null;
      if (found != _poseFound || previousReps != _workout.currentReps) {
        setState(() => _poseFound = found);
      }
    } catch (error) {
      debugPrint('Free workout pose detection: $error');
      if (_wantsCamera &&
          mounted &&
          _camera == camera &&
          epoch == _captureEpoch) {
        _openingFailed = true;
        _cameraError = _tr(
          'Не удалось распознать движения.',
          'Could not recognize movement.',
          'Қозғалысты тану мүмкін болмады.',
        );
        setState(() {});
        _syncCamera();
      }
    }
  }

  double? _kneeAngle(Pose pose) {
    double? side(
      PoseLandmarkType hipId,
      PoseLandmarkType kneeId,
      PoseLandmarkType ankleId,
    ) {
      final hip = pose.landmarks[hipId];
      final knee = pose.landmarks[kneeId];
      final ankle = pose.landmarks[ankleId];
      if (hip == null || knee == null || ankle == null) return null;
      if (hip.likelihood < 0.55 ||
          knee.likelihood < 0.55 ||
          ankle.likelihood < 0.55) {
        return null;
      }
      final a = Offset(hip.x, hip.y) - Offset(knee.x, knee.y);
      final b = Offset(ankle.x, ankle.y) - Offset(knee.x, knee.y);
      if (a.distance * b.distance < 1e-5) return null;
      final cosine = ((a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance))
          .clamp(-1.0, 1.0);
      return math.acos(cosine) * 180 / math.pi;
    }

    return side(
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
        ) ??
        side(
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.rightAnkle,
        );
  }

  Future<void> _confirmExit() async {
    if (_exitPromptOpen || _closing) return;
    setState(() {
      _exitPromptOpen = true;
      _resetCapture();
    });
    _syncCamera();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FocusStyle.surface,
        title: Text(
          _tr(
            'Завершить тренировку?',
            'End workout?',
            'Жаттығуды аяқтау керек пе?',
          ),
        ),
        content: Text(
          _tr(
            'Можно сохранить выполненные повторения или выйти без сохранения.',
            'You can save the completed repetitions or leave without saving.',
            'Орындалған қайталауларды сақтауға немесе сақтамай шығуға болады.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_tr('Продолжить', 'Continue', 'Жалғастыру')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(_tr('Не сохранять', 'Discard', 'Сақтамау')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(_tr('Сохранить', 'Save', 'Сақтау')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _exitPromptOpen = false);
    if (choice != null) {
      await _closeWorkout(save: choice == 'save');
    } else {
      _syncCamera();
    }
  }

  Future<void> _closeWorkout({required bool save}) async {
    if (_closing) return;
    setState(() {
      _closing = true;
      _resetCapture();
    });
    final result = save ? _workout.finish() : null;
    _syncCamera();
    await _cameraTask;
    if (mounted) Navigator.pop(context, result);
  }

  void _finishWorkout() => unawaited(_closeWorkout(save: true));

  void _finishSet() {
    if (!_workout.finishSet()) return;
    setState(_resetCapture);
    _syncCamera();
  }

  void _nextSet() {
    _workout.nextSet();
    setState(_resetCapture);
    _syncCamera();
  }

  void _togglePause() {
    if (_workout.paused) {
      _workout.resume();
    } else {
      _workout.pause();
    }
    setState(_resetCapture);
    _syncCamera();
  }

  void _retry() {
    _openingFailed = false;
    _cameraError = null;
    setState(_resetCapture);
    _syncCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _syncCamera();
    unawaited(
      _cameraTask.then((_) async {
        await _frameTask;
        try {
          await _detector.close();
        } on PlatformException catch (error) {
          debugPrint('Pose detector cleanup: ${error.code}');
        } on MissingPluginException {
          // Platform plugin unavailable in widget-test environments.
        }
      }),
    );
    super.dispose();
  }

  Widget _cameraImage() {
    if (!_workout.isCounting || _exitPromptOpen || _closing) {
      return Container(color: FocusStyle.surface);
    }
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: FocusStyle.surface,
        child: Center(
          child: _cameraError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.no_photography_outlined,
                      color: FocusStyle.muted,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _cameraError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: FocusStyle.muted),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _retry,
                      child: Text(_tr('Повторить', 'Try again', 'Қайталау')),
                    ),
                  ],
                )
              : const CircularProgressIndicator(color: FocusStyle.accent),
        ),
      );
    }
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);
    // Camera-preview dimensions arrive in landscape orientation on Android.
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: preview.height,
            height: preview.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stage = _workout.stage;
    final resting = stage == WorkoutStage.resting;
    final paused = _workout.paused;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmExit());
      },
      child: Theme(
        data: FocusStyle.theme(),
        child: Scaffold(
          backgroundColor: FocusStyle.background,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: _cameraImage()),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    color: const Color(0xED0A0F10),
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _tr('Приседания', 'Squats', 'Отырып-тұру'),
                                style: const TextStyle(
                                  color: FocusStyle.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _tr(
                            'Подход ${_workout.setNumber}',
                            'Set ${_workout.setNumber}',
                            '${_workout.setNumber}-тәсіл',
                          ),
                          style: const TextStyle(
                            color: FocusStyle.muted,
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          tooltip: _tr(
                            'Закрыть тренировку',
                            'Close workout',
                            'Жаттығуды жабу',
                          ),
                          onPressed: _confirmExit,
                          icon: const Icon(Icons.close, color: FocusStyle.text),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!resting)
                  Positioned(
                    top: 78,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE00A0F10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_workout.currentReps}',
                            style: const TextStyle(
                              color: FocusStyle.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 42,
                              height: 1,
                            ),
                          ),
                          Text(
                            _tr('повторений', 'reps', 'қайталау'),
                            style: const TextStyle(
                              color: FocusStyle.text,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (resting || paused)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: const Color(0xD10A0F10),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              resting
                                  ? Icons.self_improvement
                                  : Icons.pause_circle_outline,
                              size: 42,
                              color: FocusStyle.accent,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              resting
                                  ? _tr('Отдых', 'Rest', 'Демалыс')
                                  : _tr('Пауза', 'Paused', 'Үзіліс'),
                              style: const TextStyle(
                                color: FocusStyle.text,
                                fontWeight: FontWeight.w600,
                                fontSize: 24,
                              ),
                            ),
                            if (resting) ...[
                              const SizedBox(height: 8),
                              Text(
                                _tr(
                                  'Подходов: ${_workout.completedSets.length}',
                                  'Sets completed: ${_workout.completedSets.length}',
                                  'Аяқталған тәсілдер: ${_workout.completedSets.length}',
                                ),
                                style: const TextStyle(
                                  color: FocusStyle.muted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: const Color(0xF20A0F10),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!resting && !paused) ...[
                          Row(
                            children: [
                              Icon(
                                _poseFound
                                    ? Icons.check_circle_outline
                                    : Icons.center_focus_strong,
                                size: 16,
                                color: _poseFound
                                    ? FocusStyle.accent
                                    : FocusStyle.muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _poseFound
                                      ? _tr(
                                          'Поза распознана',
                                          'Pose detected',
                                          'Дене қалпы анықталды',
                                        )
                                      : _tr(
                                          'Встань боком, чтобы были видны бедро, колено и стопа.',
                                          'Turn sideways and keep your hip, knee and foot in frame.',
                                          'Жамбас, тізе және табан көрінетіндей қырыңмен тұр.',
                                        ),
                                  maxLines: 3,
                                  style: const TextStyle(
                                    color: FocusStyle.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (resting) ...[
                          _primary(
                            _tr('Следующий подход', 'Next set', 'Келесі тәсіл'),
                            _nextSet,
                          ),
                          const SizedBox(height: 8),
                          _secondary(
                            _tr(
                              'Закончить тренировку',
                              'End workout',
                              'Жаттығуды аяқтау',
                            ),
                            _finishWorkout,
                          ),
                        ] else if (paused) ...[
                          _primary(
                            _tr('Продолжить', 'Resume', 'Жалғастыру'),
                            _togglePause,
                          ),
                          const SizedBox(height: 8),
                          _secondary(
                            _tr(
                              'Закончить тренировку',
                              'End workout',
                              'Жаттығуды аяқтау',
                            ),
                            _finishWorkout,
                          ),
                        ] else
                          Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: _tr('Пауза', 'Pause', 'Үзіліс'),
                                onPressed: _togglePause,
                                style: IconButton.styleFrom(
                                  backgroundColor: FocusStyle.surface,
                                  foregroundColor: FocusStyle.text,
                                ),
                                icon: const Icon(Icons.pause),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _primary(
                                  _tr(
                                    'Завершить подход',
                                    'Finish set',
                                    'Тәсілді аяқтау',
                                  ),
                                  _workout.currentReps == 0 ? null : _finishSet,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _primary(String text, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: FocusStyle.accent,
        foregroundColor: FocusStyle.background,
        disabledBackgroundColor: FocusStyle.border,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _secondary(String text, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: FocusStyle.text,
        side: const BorderSide(color: FocusStyle.border),
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(text),
    ),
  );
}
