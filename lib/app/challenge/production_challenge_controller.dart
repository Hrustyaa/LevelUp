import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/integration/coordinator_state.dart';
import '../../core/integration/core_integration_coordinator.dart';
import '../../core/integration/pose_event_adapter.dart';
import '../../features/pose_detection/application/squat_geometry.dart';
import '../../features/settings/application/camera_permission_checker.dart';
import '../../features/settings/models/camera_permission_status.dart';
import '../../focus_experience/focus_style.dart';
import '../../models/access_grant_status.dart';
import '../../models/challenge_type.dart';
import '../../models/workout_session_status.dart';
import '../../services/native_bridge.dart';

/// Function signature for creating a [CameraController] (overridable in tests).
typedef CameraControllerFactory = CameraController Function(
  CameraDescription description,
);

/// Function signature for processing an [InputImage] into ML Kit [Pose]s.
typedef PoseProcessor = Future<List<Pose>> Function(InputImage input);

/// Production controller bridging [FocusChallengeScreen] / [FocusAccessGrantedScreen]
/// with [ICoreIntegrationCoordinator], real [CameraController], and Google ML Kit.
///
/// Enforces all security invariants:
/// - Never creates simulated repetitions (`PoseEngineAdapter(isSimulated: false)`).
/// - Never calls `NativeBridge.grantAccess` directly.
/// - Releases camera & ML Kit resources on pause, cancellation, completion, and disposal.
/// - Confirms unlock success strictly from authoritative [CoordinatorState].
class ProductionChallengeController extends ChangeNotifier {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final ICoreIntegrationCoordinator _coordinator;
  final ICameraPermissionChecker _cameraPermissionChecker;
  final INativeBridge _nativeBridge;
  final bool isUnlockChallenge;
  final String language;
  final PoseEngineAdapter _poseAdapter;
  final Future<List<CameraDescription>> Function()? _availableCamerasOverride;
  final CameraControllerFactory? _cameraControllerFactory;
  final PoseProcessor? _poseProcessorOverride;
  final DateTime Function() _clock;

  PoseDetector? _poseDetector;
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  StreamSubscription<CoordinatorState>? _coordinatorSub;

  bool _disposed = false;
  bool _starting = false;
  bool _foreground = true;
  bool _isProcessingFrame = false;
  bool _cameraPermissionDenied = false;
  bool _cameraPermissionPermanentlyDenied = false;
  bool _trackingReady = false;
  bool _completionHandled = false;
  bool _canceled = false;
  bool _isFinalizing = false;
  bool _isUnlockConfirmed = false;
  bool _isFreeWorkoutCompleted = false;
  int _grantedMinutes = 5;
  String? _error;
  late String _hint = _tr(
    'Подготовка камеры…',
    'Starting camera…',
    'Камера дайындалуда…',
  );

  ProductionChallengeController({
    required ICoreIntegrationCoordinator coordinator,
    required ICameraPermissionChecker cameraPermissionChecker,
    required INativeBridge nativeBridge,
    required this.isUnlockChallenge,
    this.language = 'ru',
    PoseEngineAdapter? poseAdapter,
    Future<List<CameraDescription>> Function()? availableCamerasOverride,
    CameraControllerFactory? cameraControllerFactory,
    PoseProcessor? poseProcessorOverride,
    DateTime Function()? clock,
  })  : _coordinator = coordinator,
        _cameraPermissionChecker = cameraPermissionChecker,
        _nativeBridge = nativeBridge,
        _poseAdapter = poseAdapter ?? PoseEngineAdapter(isSimulated: false),
        _availableCamerasOverride = availableCamerasOverride,
        _cameraControllerFactory = cameraControllerFactory,
        _poseProcessorOverride = poseProcessorOverride,
        _clock = clock ?? DateTime.now;

  // Exposed UI state
  CameraController? get cameraController => _cameraController;
  bool get cameraReady =>
      _cameraController != null && _cameraController!.value.isInitialized;
  bool get trackingReady => _trackingReady && !_isTerminal;
  int get repetitions => _coordinator.currentState.verifiedRepetitions;
  int get targetRepetitions => _coordinator.currentState.targetRepetitions;
  String? get hint => _hint;
  String? get error => _error;
  bool get isFinalizing => _isFinalizing;
  bool get isUnlockConfirmed => _isUnlockConfirmed;
  bool get isFreeWorkoutCompleted => _isFreeWorkoutCompleted;
  int get grantedMinutes => _grantedMinutes;
  bool get isCameraPermissionPermanentlyDenied =>
      _cameraPermissionPermanentlyDenied;
  bool get canRetry =>
      !_isFinalizing &&
      !_isUnlockConfirmed &&
      !_isFreeWorkoutCompleted &&
      (_error != null || _cameraPermissionDenied);

  bool get _isTerminal =>
      _canceled ||
      _isUnlockConfirmed ||
      _isFreeWorkoutCompleted ||
      _coordinator.currentState.sessionStatus.isTerminal;

  String _tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);

  /// Initializes the coordinator subscription, ML Kit detector, workout session,
  /// camera permission check, and live camera stream.
  Future<void> start() async {
    if (_disposed || _starting || _canceled) return;
    _starting = true;
    _error = null;
    _notify();

    try {
      _coordinatorSub ??= _coordinator.stateStream.listen(_onCoordinatorState);

      if (_poseProcessorOverride == null && _poseDetector == null) {
        _poseDetector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        );
      }

      // Launch session only if not already launched by gate handler
      final current = _coordinator.currentState;
      final alreadyActive =
          current.sessionStatus == WorkoutSessionStatus.active ||
              current.sessionStatus == WorkoutSessionStatus.preparing;

      if (!alreadyActive) {
        if (isUnlockChallenge) {
          await _coordinator.launchUnlockChallenge(requirePendingRequest: true);
        } else {
          await _coordinator.launchFreeWorkout();
        }
      }

      if (_disposed || _canceled) return;

      _poseAdapter.reset();
      _coordinator.attachPoseEventSource(_poseAdapter);

      await _ensureCameraPermissionAndOpen();
    } catch (e) {
      if (!_disposed) {
        _error = '$e';
        _notify();
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _ensureCameraPermissionAndOpen() async {
    if (_disposed || _canceled || !_foreground) return;

    var status = await _cameraPermissionChecker.checkCameraPermission();
    if (status == CameraPermissionStatus.denied) {
      // User explicitly initiated this challenge; request permission now.
      status = await _cameraPermissionChecker.requestCameraPermission();
    }

    if (_disposed || _canceled) return;

    if (status == CameraPermissionStatus.permanentlyDenied ||
        status == CameraPermissionStatus.restricted) {
      _cameraPermissionDenied = true;
      _cameraPermissionPermanentlyDenied = true;
      _error = _tr(
        'Доступ к камере запрещён. Открой настройки приложения и разреши камеру.',
        'Camera access is denied. Open app settings to allow camera access.',
        'Камераға рұқсат жоқ. Қолданба баптауларынан рұқсат беріңіз.',
      );
      _notify();
      return;
    }

    if (status == CameraPermissionStatus.denied) {
      _cameraPermissionDenied = true;
      _cameraPermissionPermanentlyDenied = false;
      _error = _tr(
        'Разреши доступ к камере и нажми «Повторить».',
        'Allow camera access and tap Try again.',
        'Камераға рұқсат беріп, «Қайталау» түймесін басыңыз.',
      );
      _notify();
      return;
    }

    _cameraPermissionDenied = false;
    _cameraPermissionPermanentlyDenied = false;
    await _openCamera();
  }

  Future<void> _openCamera() async {
    if (_cameraController != null || _disposed || !_foreground || _isTerminal) {
      return;
    }

    try {
      final available = _availableCamerasOverride != null
          ? await _availableCamerasOverride()
          : await availableCameras().timeout(
              const Duration(milliseconds: 1500),
              onTimeout: () => <CameraDescription>[],
            );
      if (_disposed || !_foreground || _isTerminal) return;

      if (available.isEmpty) {
        _error = _tr(
          'Камера недоступна на этом устройстве.',
          'Camera is unavailable on this device.',
          'Бұл құрылғыда камера қолжетімсіз.',
        );
        _notify();
        return;
      }

      final camera = available.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => available.first,
      );

      final next = _cameraControllerFactory != null
          ? _cameraControllerFactory(camera)
          : CameraController(
              camera,
              ResolutionPreset.medium,
              enableAudio: false,
              imageFormatGroup: ImageFormatGroup.nv21,
            );

      _cameraController = next;
      _cameraDescription = camera;
      await next.initialize();

      if (_disposed || !_foreground || _isTerminal || _cameraController != next) {
        await next.dispose();
        if (_cameraController == next) {
          _cameraController = null;
          _cameraDescription = null;
        }
        return;
      }

      await next.startImageStream(_onFrame);

      if (!_disposed) {
        _error = null;
        _hint = _tr(
          'Встань боком так, чтобы в кадре были корпус и ноги.',
          'Stand sideways with your body and legs in frame.',
          'Денеңіз бен аяқтарыңыз кадрға сыятындай қырынан тұрыңыз.',
        );
        _notify();
      }
    } on CameraException catch (e) {
      await _releaseCamera();
      if (_disposed || _canceled) return;
      if (e.code == 'CameraAccessDeniedWithoutPrompt') {
        _cameraPermissionDenied = true;
        _cameraPermissionPermanentlyDenied = true;
      } else if (e.code.startsWith('CameraAccessDenied')) {
        _cameraPermissionDenied = true;
      }
      _error = _tr(
        'Разреши доступ к камере и попробуй ещё раз.',
        'Allow camera access and try again.',
        'Камераға рұқсат беріп, қайталап көріңіз.',
      );
      _notify();
    } catch (e) {
      await _releaseCamera();
      if (_disposed || _canceled) return;
      _error = _tr(
        'Не удалось запустить камеру: $e',
        'Could not start camera: $e',
        'Камераны іске қосу мүмкін болмады: $e',
      );
      _notify();
    }
  }

  Future<void> _releaseCamera() async {
    final current = _cameraController;
    _cameraController = null;
    _cameraDescription = null;
    _trackingReady = false;
    if (current == null) return;

    try {
      if (current.value.isStreamingImages) {
        await current.stopImageStream();
      }
    } catch (_) {}

    try {
      await current.dispose();
    } catch (_) {}
  }

  InputImage? _fromCameraImage(CameraImage image) {
    final active = _cameraController;
    final description = _cameraDescription;
    if (active == null || description == null || image.planes.length != 1) {
      return null;
    }

    final frameFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (frameFormat != InputImageFormat.nv21) return null;

    final compensation = _orientations[active.value.deviceOrientation];
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

  void _onFrame(CameraImage image) {
    if (_isProcessingFrame || _disposed || !_foreground || _isTerminal) return;
    final input = _fromCameraImage(image);
    if (input == null) return;

    _isProcessingFrame = true;
    processInputImage(input).whenComplete(() => _isProcessingFrame = false);
  }

  /// Processes an [InputImage] through ML Kit [PoseDetector] (or test override),
  /// evaluates knee angle via [SquatGeometry], and forwards to [PoseEngineAdapter].
  @visibleForTesting
  Future<void> processInputImage(InputImage input) async {
    if (_disposed || !_foreground || _isTerminal) return;

    try {
      final List<Pose> poses;
      if (_poseProcessorOverride != null) {
        poses = await _poseProcessorOverride(input);
      } else {
        final detector = _poseDetector;
        if (detector == null) return;
        poses = await detector.processImage(input);
      }

      if (_disposed || !_foreground || _isTerminal) return;

      if (poses.isEmpty) {
        _trackingReady = false;
        _hint = _tr(
          'Человек не найден — отойди дальше от телефона',
          'Step back so your full body is visible',
          'Денеңіз толық көрінетіндей артқа шегініңіз',
        );
        _poseAdapter.processAngle(null);
        _notify();
        return;
      }

      final angle = estimateKneeAngle(poses.first);
      if (angle == null) {
        _trackingReady = false;
        _hint = _tr(
          'Не вижу бедро, колено и стопу — повернись боком',
          'Show your hip, knee, and ankle — turn sideways',
          'Жамбас, тізе және табан көрінетіндей қырынан тұрыңыз',
        );
        _poseAdapter.processAngle(null);
        _notify();
        return;
      }

      final result = _poseAdapter.processAngle(angle);
      _trackingReady = true;
      _hint = result.feedbackMessage;
      _notify();
    } catch (_) {
      // Ignore transient single-frame ML Kit errors
    }
  }

  /// Extracts the 2D interior knee angle using [SquatGeometry].
  @visibleForTesting
  static double? estimateKneeAngle(Pose pose) {
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
      if (hip.likelihood < SquatGeometry.defaultLikelihoodThreshold ||
          knee.likelihood < SquatGeometry.defaultLikelihoodThreshold ||
          ankle.likelihood < SquatGeometry.defaultLikelihoodThreshold) {
        return null;
      }

      return SquatGeometry.calculateKneeAngle(
        Offset(hip.x, hip.y),
        Offset(knee.x, knee.y),
        Offset(ankle.x, ankle.y),
      );
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

  void _onCoordinatorState(CoordinatorState state) {
    if (_disposed) return;

    if (state.sessionStatus == WorkoutSessionStatus.completed &&
        !_completionHandled) {
      unawaited(_handleCompletion(state));
      return;
    }

    if (state.sessionStatus == WorkoutSessionStatus.completed &&
        _completionHandled) {
      _syncConfirmedGrantState(state);
    }

    if (state.feedbackMessage != null && state.feedbackMessage!.isNotEmpty) {
      _hint = state.feedbackMessage!;
    }
    if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
      _error = state.errorMessage;
    }
    _notify();
  }

  Future<void> _handleCompletion(CoordinatorState state) async {
    _completionHandled = true;
    _isFinalizing = true;
    _hint = _tr(
      'Подтверждаем временный доступ…',
      'Confirming temporary access…',
      'Уақытша рұқсат расталуда…',
    );
    _notify();

    await _releaseCamera();
    if (_disposed) return;

    try {
      await _coordinator.waitForCompletion();
    } catch (e) {
      if (!_disposed) {
        _error = '$e';
      }
    }

    if (_disposed) return;
    _isFinalizing = false;
    _syncConfirmedGrantState(_coordinator.currentState);
    _notify();
  }

  void _syncConfirmedGrantState(CoordinatorState state) {
    if (state.challengeContext == ChallengeType.freeWorkout) {
      _isFreeWorkoutCompleted = true;
      return;
    }

    if (state.accessGrantStatus == AccessGrantStatus.granted &&
        state.unlockUntil != null) {
      final remaining = state.unlockUntil!.difference(_clock());
      if (remaining > Duration.zero) {
        _grantedMinutes =
            (remaining.inMilliseconds / 60000).ceil().clamp(1, 15);
        _isUnlockConfirmed = true;
        _error = null;
        return;
      }
    }

    if (state.accessGrantStatus == AccessGrantStatus.rejected ||
        state.accessGrantStatus == AccessGrantStatus.failed) {
      _error = state.errorMessage ??
          _tr(
            'Не удалось подтвердить доступ.',
            'Could not confirm access.',
            'Рұқсатты растау мүмкін болмады.',
          );
    }
  }

  /// Handles app backgrounding/foregrounding cleanly.
  Future<void> handleLifecycleChange(AppLifecycleState state) async {
    if (_disposed) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _foreground = false;
      _poseAdapter.processAngle(null);
      await _releaseCamera();
      _notify();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!_isTerminal && !_starting) {
        await _ensureCameraPermissionAndOpen();
      }
    }
  }

  /// Retries camera acquisition or opens Android App Settings if permanently denied.
  Future<void> retry() async {
    if (_disposed || _isFinalizing) return;
    if (_cameraPermissionPermanentlyDenied) {
      await _nativeBridge.openAppSettings();
      return;
    }
    _error = null;
    _notify();

    final status = _coordinator.currentState.sessionStatus;
    if (status != WorkoutSessionStatus.active &&
        status != WorkoutSessionStatus.preparing) {
      await start();
    } else {
      await _ensureCameraPermissionAndOpen();
    }
  }

  /// Cancels the active session and releases hardware resources.
  Future<void> cancel() async {
    if (_disposed || _canceled || _isFinalizing) return;
    _canceled = true;

    _coordinator.detachPoseEventSource();
    await _releaseCamera();

    final status = _coordinator.currentState.sessionStatus;
    if (status == WorkoutSessionStatus.active ||
        status == WorkoutSessionStatus.preparing) {
      try {
        await _coordinator.cancelCurrentSession(reason: 'Cancelled by user');
      } catch (_) {}
    }

    if (_coordinator.currentState.sessionStatus.isTerminal) {
      _coordinator.releaseTerminalSession();
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _coordinatorSub?.cancel();
    _coordinatorSub = null;
    _coordinator.detachPoseEventSource();

    final status = _coordinator.currentState.sessionStatus;
    if (status == WorkoutSessionStatus.active ||
        status == WorkoutSessionStatus.preparing) {
      unawaited(
        _coordinator
            .cancelCurrentSession(reason: 'Challenge screen disposed')
            .then<void>((_) {}, onError: (_) {})
            .whenComplete(() {
          if (_coordinator.currentState.sessionStatus.isTerminal) {
            _coordinator.releaseTerminalSession();
          }
        }),
      );
    } else if (status.isTerminal) {
      _coordinator.releaseTerminalSession();
    }

    _poseAdapter.dispose();
    unawaited(_poseDetector?.close());
    _poseDetector = null;
    unawaited(_releaseCamera());

    super.dispose();
  }
}
