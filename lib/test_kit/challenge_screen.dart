import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../focus_experience/focus_exercises.dart';
import '../focus_experience/focus_screens.dart';
import '../focus_experience/focus_style.dart';
import 'squat_counter.dart';

class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({
    super.key,
    required this.exercise,
    required this.appName,
    this.onCompleted,
    this.onCameraPermissionDenied,
    this.language = 'ru',
  });

  final FocusExercise exercise;
  final String appName, language;
  final Future<DateTime> Function(int repetitions)? onCompleted;
  final Future<void> Function()? onCameraPermissionDenied;

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen>
    with WidgetsBindingObserver {
  final _counter = SquatCounter();
  final _detector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  CameraController? _camera;
  Future<void> _cameraWork = Future<void>.value();
  Future<void>? _frameWork;
  bool _foreground = true;
  bool _disposed = false;
  bool _cameraFailed = false;
  bool _permissionDenied = false;
  bool _granting = false;
  bool _canceled = false;
  int? _grantedMinutes;
  late String _message = _t(
    'Подготовка камеры…',
    'Starting camera…',
    'Камера дайындалуда…',
  );
  String? _error;
  bool _trackingReady = false;
  static const orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  String _t(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  bool get _wantsCamera =>
      _foreground &&
      !_disposed &&
      !_canceled &&
      !_cameraFailed &&
      !_counter.isComplete;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _counter.update(null);
    _syncCamera();
  }

  void _syncCamera() {
    _cameraWork = _cameraWork.then((_) async {
      if (!_wantsCamera) {
        final camera = _camera;
        _camera = null;
        if (camera == null) return;
        if (!_disposed) setState(() => _trackingReady = false);
        await _disposeCamera(camera);
      } else if (_camera == null) {
        await _openCamera();
      }
    });
  }

  Future<void> _openCamera() async {
    CameraController? next;
    try {
      final cameras = await availableCameras();
      if (!_wantsCamera) return;
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'Камера недоступна.');
      }
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final camera = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      next = camera;
      await camera.initialize();
      if (!_wantsCamera) return;
      await camera.startImageStream((frame) => _onFrame(camera, frame));
      if (!_wantsCamera) return;
      setState(() {
        _camera = camera;
        _message = _t(
          'Встань боком так, чтобы в кадре были корпус и ноги.',
          'Stand sideways with your body and legs in frame.',
          'Денеңіз бен аяқтарыңыз кадрға сыятындай қырынан тұрыңыз.',
        );
      });
      next = null;
    } catch (error) {
      if (!mounted || _disposed || _canceled) return;
      if (error is CameraException &&
          error.code.startsWith('CameraAccessDenied')) {
        _permissionDenied = true;
        final onDenied = widget.onCameraPermissionDenied;
        if (onDenied != null) unawaited(onDenied());
        _failCamera(
          _t(
            'Разреши доступ к камере и попробуй ещё раз.',
            'Allow camera access and try again.',
            'Камераға рұқсат беріп, қайталап көріңіз.',
          ),
        );
      } else if (_wantsCamera) {
        debugPrint('Could not open challenge camera: $error');
        _failCamera(
          _t(
            'Не удалось открыть камеру.',
            'Could not open the camera.',
            'Камераны ашу мүмкін болмады.',
          ),
        );
      }
    } finally {
      if (next != null) await _disposeCamera(next);
    }
  }

  Future<void> _disposeCamera(CameraController camera) async {
    try {
      await camera.dispose();
    } on CameraException catch (error) {
      debugPrint('Camera cleanup: ${error.code}');
    }
  }

  void _failCamera(String error) {
    setState(() {
      _cameraFailed = true;
      _error = error;
      _trackingReady = false;
      _counter.update(null);
    });
    _syncCamera();
  }

  void _retryCamera() {
    setState(() {
      _cameraFailed = false;
      _permissionDenied = false;
      _error = null;
      _message = _t(
        'Подготовка камеры…',
        'Starting camera…',
        'Камера дайындалуда…',
      );
    });
    _syncCamera();
  }

  InputImage? fromCameraImage(CameraController active, CameraImage image) {
    final description = active.description;
    if (image.planes.length != 1) return null;
    final frameFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (frameFormat != InputImageFormat.nv21) return null;
    final compensation = orientations[active.value.deviceOrientation];
    if (compensation == null) return null;
    final sensor = description.sensorOrientation;
    final rotation = description.lensDirection == CameraLensDirection.front
        ? (sensor + compensation) % 360
        : (sensor - compensation + 360) % 360;
    final imageRotation = InputImageRotationValue.fromRawValue(rotation);
    if (imageRotation == null) return null;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void _onFrame(CameraController camera, CameraImage image) {
    if (!_wantsCamera || _camera != camera || _frameWork != null) return;
    final input = fromCameraImage(camera, image);
    if (input == null) {
      _failCamera(
        _t(
          'Формат кадров камеры не поддерживается.',
          'The camera frame format is unavailable.',
          'Камера кадрларының пішімі қолжетімсіз.',
        ),
      );
      return;
    }
    _frameWork = _processPose(camera, input).whenComplete(() {
      _frameWork = null;
    });
  }

  Future<void> _processPose(CameraController camera, InputImage input) async {
    try {
      final poses = await _detector.processImage(input);
      if (!_wantsCamera || _camera != camera) return;
      final knee = poses.isEmpty ? null : estimateKneeAngle(poses.first);
      final previousCount = _counter.reps;
      _counter.update(knee);
      final tracking = knee != null;
      final message = switch ((poses.isEmpty, knee, _counter.phase)) {
        (true, _, _) => _t(
          'Отойди от телефона, чтобы попасть в кадр.',
          'Step back so the camera can see you.',
          'Кадрға сыю үшін телефоннан алыстаңыз.',
        ),
        (_, null, _) => _t(
          'Повернись боком. В кадре должны быть бедро, колено и стопа.',
          'Turn sideways so your hip, knee and foot are visible.',
          'Жамбас, тізе және табан көрінетіндей қырынан тұрыңыз.',
        ),
        (_, _, SquatPhase.findStanding) => _t(
          'Выпрямись перед приседанием.',
          'Stand upright before your squat.',
          'Отырар алдында тік тұрыңыз.',
        ),
        (_, _, SquatPhase.lower) => _t('Присядь.', 'Squat down.', 'Отырыңыз.'),
        (_, _, SquatPhase.rise) => _t(
          'Теперь выпрямись.',
          'Stand up again.',
          'Енді қайта тік тұрыңыз.',
        ),
      };
      if (tracking != _trackingReady ||
          message != _message ||
          previousCount != _counter.reps) {
        setState(() {
          _trackingReady = tracking;
          _message = message;
        });
      }
      if (_counter.isComplete) {
        if (widget.onCompleted == null) {
          setState(
            () => _message = _t(
              'Упражнение выполнено.',
              'Exercise complete.',
              'Жаттығу орындалды.',
            ),
          );
          _syncCamera();
        } else {
          unawaited(_grantAccess());
        }
      }
    } catch (error) {
      if (_wantsCamera && _camera == camera) {
        debugPrint('Could not track challenge pose: $error');
        _failCamera(
          _t(
            'Не удалось распознать позу.',
            'Could not detect your pose.',
            'Дене қалпын анықтау мүмкін болмады.',
          ),
        );
      }
    }
  }

  double? estimateKneeAngle(Pose pose) {
    final map = pose.landmarks;
    double? side(
      PoseLandmarkType hipType,
      PoseLandmarkType kneeType,
      PoseLandmarkType ankleType,
    ) {
      final hip = map[hipType];
      final knee = map[kneeType];
      final ankle = map[ankleType];
      if (hip == null || knee == null || ankle == null) return null;
      if (hip.likelihood < 0.55 ||
          knee.likelihood < 0.55 ||
          ankle.likelihood < 0.55) {
        return null;
      }
      final a = Offset(hip.x, hip.y);
      final b = Offset(knee.x, knee.y);
      final c = Offset(ankle.x, ankle.y);
      final ab = a - b;
      final cb = c - b;
      final denominator = ab.distance * cb.distance;
      if (denominator < 1e-5) return null;
      final cosine = ((ab.dx * cb.dx + ab.dy * cb.dy) / denominator).clamp(
        -1.0,
        1.0,
      );
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

  Future<void> _grantAccess() async {
    if (_granting || _canceled || !_counter.isComplete) return;
    setState(() {
      _granting = true;
      _message = _t(
        'Подтверждаем временный доступ…',
        'Confirming temporary access…',
        'Уақытша рұқсат расталуда…',
      );
      _error = null;
    });
    _syncCamera();
    try {
      await _cameraWork;
      if (!mounted || _canceled) return;
      if (!_foreground) {
        setState(
          () => _error = _t(
            'Вернись к заданию и подтверди доступ.',
            'Return to the challenge and confirm access.',
            'Тапсырмаға оралып, рұқсатты растаңыз.',
          ),
        );
        return;
      }
      final deadline = await widget.onCompleted!(_counter.reps);
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw StateError(
          'The Focus engine did not return an active access window',
        );
      }
      if (mounted) {
        setState(
          () => _grantedMinutes = (remaining.inMilliseconds / 60000).ceil(),
        );
      }
    } catch (error) {
      debugPrint('Could not grant challenge access: $error');
      if (mounted) {
        setState(
          () => _error = _t(
            'Не удалось подтвердить доступ.',
            'Could not confirm access.',
            'Рұқсатты растау мүмкін болмады.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _granting = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _syncCamera();
    unawaited(
      _cameraWork.then((_) async {
        await _frameWork;
        try {
          await _detector.close();
        } on PlatformException catch (error) {
          debugPrint('Pose detector cleanup: ${error.code}');
        } on MissingPluginException {
          // The detector plugin is unavailable on this platform.
        }
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_grantedMinutes case final minutes?) {
      return FocusAccessGrantedScreen(
        appName: widget.appName,
        accessMinutes: minutes,
        language: widget.language,
        onDone: () => Navigator.of(context).pop(),
      );
    }
    final camera = _camera;
    return PopScope(
      canPop: !_granting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _canceled = true;
          _syncCamera();
        }
      },
      child: FocusChallengeScreen(
        exercise: widget.exercise,
        repetitions: _counter.reps,
        language: widget.language,
        cameraReady: camera != null,
        trackingReady: _trackingReady && !_counter.isComplete,
        cameraPreview: _counter.isComplete
            ? null
            : camera != null
            ? CameraPreview(camera)
            : _cameraFailed
            ? const Icon(Icons.no_photography_outlined)
            : const CircularProgressIndicator(),
        hint: _message,
        error: _error,
        onCancel: _granting ? null : () => Navigator.of(context).pop(),
        onRetry: _cameraFailed
            ? _permissionDenied && widget.onCameraPermissionDenied != null
                  ? null
                  : _retryCamera
            : _counter.isComplete &&
                  widget.onCompleted != null &&
                  _error != null
            ? _grantAccess
            : null,
      ),
    );
  }
}
