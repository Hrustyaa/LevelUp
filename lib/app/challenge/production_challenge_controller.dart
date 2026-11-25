import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show ValueListenable, debugPrint, kDebugMode;
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/integration/coordinator_state.dart';
import '../../core/integration/core_integration_coordinator.dart';
import '../../core/integration/pose_event_adapter.dart';
import '../../features/challenge/application/push_up_verification.dart';
import '../../features/pose_detection/application/pose_landmark_smoother.dart';
import '../../features/pose_detection/application/pose_temporal_guard.dart';
import '../../features/pose_detection/application/pose_visibility_hysteresis.dart';
import '../../features/pose_detection/application/push_up_counter.dart';
import '../../features/pose_detection/application/squat_counter.dart';
import '../../features/pose_detection/application/squat_geometry.dart';
import '../../features/pose_detection/models/pose_overlay_state.dart';
import '../../features/settings/application/camera_permission_checker.dart';
import '../../features/settings/models/camera_permission_status.dart';
import '../../focus_experience/focus_style.dart';
import '../../models/access_grant_status.dart';
import '../../models/challenge_type.dart';
import '../../models/exercise_type.dart';
import '../../models/workout_session_status.dart';
import '../../services/native_bridge.dart';

/// Function signature for creating a [CameraController] (overridable in tests).
typedef CameraControllerFactory =
    CameraController Function(CameraDescription description);

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

  /// Exercise assigned to this camera session.
  final ExerciseType exerciseType;
  final String language;
  final String? _unlockSessionId;
  late final PoseEngineAdapter? _poseAdapter;
  late final PushUpPoseAdapter? _pushUpPoseAdapter;
  late final PushUpCounter? _pushUpCounter;
  final Future<List<CameraDescription>> Function()? _availableCamerasOverride;
  final CameraControllerFactory? _cameraControllerFactory;
  final PoseProcessor? _poseProcessorOverride;
  final DateTime Function() _clock;

  PoseDetector? _poseDetector;
  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  StreamSubscription<CoordinatorState>? _coordinatorSub;
  Future<void> _cameraTransition = Future<void>.value();
  Future<void>? _sessionStart;
  String? _sessionId;

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
  int _sessionEpoch = 0;
  final PoseLandmarkSmoother _landmarkSmoother = PoseLandmarkSmoother();
  final PoseTemporalGuard _temporalGuard = PoseTemporalGuard();
  final _jointHysteresis =
      PoseVisibilityHysteresis<PoseLandmarkType, PoseJointPoint>();
  final ValueNotifier<PoseOverlayState> _poseOverlayNotifier =
      ValueNotifier<PoseOverlayState>(PoseOverlayState.empty);
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
    ExerciseType exerciseType = ExerciseType.squats,
    this.language = 'ru',
    String? unlockSessionId,
    PoseEngineAdapter? poseAdapter,
    Future<List<CameraDescription>> Function()? availableCamerasOverride,
    CameraControllerFactory? cameraControllerFactory,
    PoseProcessor? poseProcessorOverride,
    DateTime Function()? clock,
  }) : exerciseType = isUnlockChallenge && !PushUpVerification.unlockEnabled
           ? ExerciseType.squats
           : exerciseType,
       _coordinator = coordinator,
       _cameraPermissionChecker = cameraPermissionChecker,
       _nativeBridge = nativeBridge,
       _unlockSessionId = unlockSessionId,
       _availableCamerasOverride = availableCamerasOverride,
       _cameraControllerFactory = cameraControllerFactory,
       _poseProcessorOverride = poseProcessorOverride,
       _clock = clock ?? DateTime.now {
    final pushUps = this.exerciseType == ExerciseType.pushUp;
    _poseAdapter = pushUps ? null : poseAdapter ?? PoseEngineAdapter();
    _pushUpCounter = pushUps
        ? PushUpCounter(
            onDiagnostic:
                kDebugMode &&
                    const bool.fromEnvironment(
                      'LEVELUP_DEBUG_PUSH_UP_DIAGNOSTICS',
                    )
                ? (message) => debugPrint('LevelUp push-up: $message')
                : null,
          )
        : null;
    _pushUpPoseAdapter = pushUps
        ? PushUpPoseAdapter(counter: _pushUpCounter)
        : null;
  }

  // Exposed UI state
  CameraController? get cameraController => _cameraController;
  ValueListenable<PoseOverlayState> get poseOverlayListenable =>
      _poseOverlayNotifier;
  bool get cameraReady =>
      _cameraController != null && _cameraController!.value.isInitialized;
  bool get trackingReady => _trackingReady && !_isTerminal;
  int get repetitions =>
      _ownsSession ? _coordinator.currentState.verifiedRepetitions : 0;
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

  bool get _ownsSession =>
      _sessionId != null && _coordinator.currentState.sessionId == _sessionId;

  bool get _isTerminal =>
      _canceled ||
      _isUnlockConfirmed ||
      _isFreeWorkoutCompleted ||
      (_ownsSession && _coordinator.currentState.sessionStatus.isTerminal);

  String _tr(String ru, String en, String kk) => focusTr(language, ru, en, kk);

  /// Initializes the coordinator subscription, ML Kit detector, workout session,
  /// camera permission check, and live camera stream.
  Future<void> start() async {
    if (_disposed || _starting || _canceled || _ownsSession) return;
    _starting = true;
    _sessionEpoch++;
    _landmarkSmoother.reset();
    _clearPoseOverlay();
    _error = null;
    _notify();

    try {
      _sessionStart = _claimSession();
      await _sessionStart;
      if (_disposed || _canceled || !_ownsSession) return;

      _coordinatorSub ??= _coordinator.stateStream.listen(_onCoordinatorState);

      if (_poseProcessorOverride == null && _poseDetector == null) {
        _poseDetector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        );
      }

      _poseAdapter?.reset();
      _pushUpPoseAdapter?.reset();
      _coordinator.attachPoseEventSource(
        _pushUpPoseAdapter ?? _poseAdapter!,
        sessionId: _sessionId,
      );
      await _ensureCameraPermissionAndOpen();
    } catch (e) {
      if (!_disposed) {
        _error = '$e';
        _notify();
      }
    } finally {
      _sessionStart = null;
      _starting = false;
    }
  }

  Future<void> _claimSession() async {
    if (_unlockSessionId != null) {
      final state = _coordinator.currentState;
      if (state.sessionId != _unlockSessionId ||
          state.sessionStatus != WorkoutSessionStatus.active ||
          state.challengeContext != ChallengeType.unlockChallenge ||
          state.challenge?.exerciseType != exerciseType) {
        throw StateError('The assigned Focus challenge is no longer active.');
      }
      _sessionId = _unlockSessionId;
      return;
    }

    final session = isUnlockChallenge
        ? await _coordinator.launchUnlockChallenge(
            requirePendingRequest: true,
            exerciseType: exerciseType,
          )
        : await _coordinator.launchFreeWorkout(exerciseType: exerciseType);
    _sessionId = session.sessionId;
  }

  Future<void> _queueCameraTransition(Future<void> Function() action) {
    final transition = _cameraTransition.then((_) => action());
    _cameraTransition = transition.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return transition;
  }

  bool _canOpenCamera(int epoch) =>
      !_disposed &&
      _foreground &&
      !_isTerminal &&
      _ownsSession &&
      epoch == _sessionEpoch;

  Future<void> _ensureCameraPermissionAndOpen() {
    final epoch = _sessionEpoch;
    return _queueCameraTransition(() async {
      if (!_canOpenCamera(epoch) || _cameraController != null) return;
      await _checkCameraPermissionAndOpen(epoch);
    });
  }

  Future<void> _checkCameraPermissionAndOpen(int epoch) async {
    var status = await _cameraPermissionChecker.checkCameraPermission();
    if (!_canOpenCamera(epoch)) return;
    if (status == CameraPermissionStatus.denied) {
      // User explicitly initiated this challenge; request permission now.
      status = await _cameraPermissionChecker.requestCameraPermission();
    }

    if (!_canOpenCamera(epoch)) return;

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
    await _openCamera(epoch);
  }

  Future<void> _openCamera(int epoch) async {
    try {
      final available = _availableCamerasOverride != null
          ? await _availableCamerasOverride()
          : await availableCameras().timeout(
              const Duration(milliseconds: 1500),
              onTimeout: () => <CameraDescription>[],
            );
      if (!_canOpenCamera(epoch)) return;

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

      if (!_canOpenCamera(epoch)) {
        await _closeCamera();
        return;
      }

      await next.startImageStream((image) {
        if (_cameraController == next && _canOpenCamera(epoch)) _onFrame(image);
      });

      if (_canOpenCamera(epoch)) {
        _error = null;
        _hint = exerciseType == ExerciseType.pushUp
            ? _pushUpHint('setup')
            : _tr(
                'Встань боком так, чтобы в кадре были корпус и ноги.',
                'Stand sideways with your body and legs in frame.',
                'Денеңіз бен аяқтарыңыз кадрға сыятындай қырынан тұрыңыз.',
              );
        _notify();
      }
    } on CameraException catch (e) {
      await _closeCamera();
      if (!_canOpenCamera(epoch)) return;
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
      await _closeCamera();
      if (!_canOpenCamera(epoch)) return;
      _error = _tr(
        'Не удалось запустить камеру: $e',
        'Could not start camera: $e',
        'Камераны іске қосу мүмкін болмады: $e',
      );
      _notify();
    }
  }

  Future<void> _releaseCamera() {
    _sessionEpoch++;
    _clearPoseOverlay();
    _trackingReady = false;
    return _queueCameraTransition(_closeCamera);
  }

  Future<void> _closeCamera() async {
    final current = _cameraController;
    _cameraController = null;
    _cameraDescription = null;
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

  Future<void> _closePoseDetector() async {
    final detector = _poseDetector;
    _poseDetector = null;
    try {
      await detector?.close();
    } catch (_) {
      // The camera and session still need to close if the plugin is gone.
    }
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
    final epoch = _sessionEpoch;
    if (!_canOpenCamera(epoch)) return;

    try {
      final List<Pose> poses;
      if (_poseProcessorOverride != null) {
        poses = await _poseProcessorOverride(input);
      } else {
        final detector = _poseDetector;
        if (detector == null) return;
        poses = await detector.processImage(input);
      }

      if (!_canOpenCamera(epoch)) {
        return;
      }

      if (poses.isEmpty) {
        _trackingReady = false;
        _clearPoseOverlay();
        _hint = _tr(
          'Человек не найден — отойди дальше от телефона',
          'Step back so your full body is visible',
          'Денеңіз толық көрінетіндей артқа шегініңіз',
        );
        if (exerciseType == ExerciseType.pushUp) {
          _hint = _pushUpHint('tracking');
          _pushUpPoseAdapter!.processPose(null, timestamp: _clock());
        } else {
          _poseAdapter!.processAngle(null);
        }
        _notify();
        return;
      }

      final pose = poses.first;
      final poseTime = _clock();
      final imageSize = input.metadata?.size ?? Size.zero;
      final rotation =
          input.metadata?.rotation ?? InputImageRotation.rotation0deg;
      final isFrontCamera =
          (_cameraDescription?.lensDirection ?? CameraLensDirection.front) ==
          CameraLensDirection.front;
      final pushUp = exerciseType == ExerciseType.pushUp;
      final result = pushUp
          ? _pushUpPoseAdapter!.processPose(pose, timestamp: poseTime)
          : _poseAdapter!.processAngle(estimateKneeAngle(pose));
      _trackingReady = result.isValidTracking;
      _hint = pushUp
          ? _pushUpHint(result.feedbackMessage)
          : result.isValidTracking
          ? result.feedbackMessage
          : _tr(
              'Не вижу бедро, колено и стопу — повернись боком',
              'Show your hip, knee, and ankle — turn sideways',
              'Жамбас, тізе және табан көрінетіндей қырынан тұрыңыз',
            );
      final isValidForm =
          result.isValidTracking &&
          (result.phase == SquatPhase.down || result.isRepetitionCompleted);
      final overlay = _buildSmoothedOverlayState(
        pose: pose,
        imageSize: imageSize,
        rotation: rotation,
        isFrontCamera: isFrontCamera,
        isValidForm: isValidForm,
        sessionEpoch: epoch,
        now: poseTime,
      );
      if (!_disposed) _poseOverlayNotifier.value = overlay;
      _notify();
    } catch (_) {
      // Ignore transient single-frame ML Kit errors
    }
  }

  void _clearPoseOverlay() {
    _landmarkSmoother.reset();
    _temporalGuard.reset();
    _jointHysteresis.reset();
    if (!_disposed && _poseOverlayNotifier.value != PoseOverlayState.empty) {
      _poseOverlayNotifier.value = PoseOverlayState.empty;
    }
  }

  /// Extracts reliable left/right leg landmarks (`hip -> knee -> ankle`) from
  /// an ML Kit [Pose] for read-only overlay rendering.
  @visibleForTesting
  static PoseOverlayState extractOverlayState({
    required Pose pose,
    required Size imageSize,
    required InputImageRotation rotation,
    required bool isFrontCamera,
    required bool isValidForm,
    int sessionEpoch = 0,
  }) {
    final map = pose.landmarks;

    LegLandmarks? extractLeg(
      PoseLandmarkType hipType,
      PoseLandmarkType kneeType,
      PoseLandmarkType ankleType,
    ) {
      final hip = map[hipType];
      final knee = map[kneeType];
      final ankle = map[ankleType];
      if (hip == null || knee == null || ankle == null) return null;
      final leg = LegLandmarks(
        hip: PoseJointPoint(
          imagePoint: Offset(hip.x, hip.y),
          likelihood: hip.likelihood,
        ),
        knee: PoseJointPoint(
          imagePoint: Offset(knee.x, knee.y),
          likelihood: knee.likelihood,
        ),
        ankle: PoseJointPoint(
          imagePoint: Offset(ankle.x, ankle.y),
          likelihood: ankle.likelihood,
        ),
      );
      return leg.isReliable(SquatGeometry.defaultLikelihoodThreshold)
          ? leg
          : null;
    }

    return PoseOverlayState(
      leftLeg: extractLeg(
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.leftAnkle,
      ),
      rightLeg: extractLeg(
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.rightAnkle,
      ),
      imageSize: imageSize,
      rotation: rotation,
      isFrontCamera: isFrontCamera,
      isValidForm: isValidForm,
      sessionEpoch: sessionEpoch,
    );
  }

  /// Applies temporal outlier rejection and One Euro smoothing for visual
  /// overlay rendering only. Raw landmarks for rep counting are never touched.
  Offset _smoothJoint(
    PoseLandmarkType type,
    Offset raw,
    Size imageSize,
    DateTime now,
  ) {
    final Offset target;
    if (_temporalGuard.isPlausible(type, raw, imageSize)) {
      _temporalGuard.update(type, raw);
      target = raw;
    } else {
      target = _temporalGuard.lastPosition(type) ?? raw;
    }
    return _landmarkSmoother.smooth(type, target, timestamp: now);
  }

  PoseOverlayState _buildSmoothedOverlayState({
    required Pose pose,
    required Size imageSize,
    required InputImageRotation rotation,
    required bool isFrontCamera,
    required bool isValidForm,
    required int sessionEpoch,
    required DateTime now,
  }) {
    final joints = <PoseLandmarkType, PoseJointPoint>{};
    final uncertain = <PoseLandmarkType>{};
    for (final type in PoseOverlayState.jointTypes) {
      final landmark = pose.landmarks[type];
      PoseJointPoint? candidate;
      if (landmark != null) {
        final raw = PoseJointPoint(
          imagePoint: Offset(landmark.x, landmark.y),
          likelihood: landmark.likelihood,
        );
        if (raw.isReliable(_jointHysteresis.exitThreshold)) {
          candidate = PoseJointPoint(
            imagePoint: _smoothJoint(type, raw.imagePoint, imageSize, now),
            likelihood: raw.likelihood,
          );
        }
      }
      final tracked = _jointHysteresis.update(
        key: type,
        candidate: candidate,
        minLikelihood: candidate?.likelihood ?? 0,
        now: now,
      );
      if (tracked.value case final value?) joints[type] = value;
      if (tracked.isUncertain) uncertain.add(type);
    }
    if (joints.isEmpty) return PoseOverlayState.empty;

    return PoseOverlayState(
      joints: Map.unmodifiable(joints),
      uncertainJoints: Set.unmodifiable(uncertain),
      imageSize: imageSize,
      rotation: rotation,
      isFrontCamera: isFrontCamera,
      isValidForm: isValidForm,
      sessionEpoch: sessionEpoch,
      exerciseMode: exerciseType == ExerciseType.pushUp
          ? ExerciseMode.pushUp
          : ExerciseMode.squat,
      opacity: uncertain.length == joints.length ? 0.45 : 1.0,
    );
  }

  String _pushUpHint(String feedback) => switch (feedback) {
    'start' => _tr(
      'Начни с прямых рук',
      'Start with straight arms',
      'Қолды түзу ұстап бастаңыз',
    ),
    'move' => _tr(
      'Выполни повтор в обычном темпе',
      'Do a rep at your usual pace',
      'Жаттығуды әдеттегі қарқынмен орындаңыз',
    ),
    'hold' => _tr(
      'Ненадолго задержись в нижней позиции',
      'Hold the lower position briefly',
      'Төменгі қалыпта сәл кідіріңіз',
    ),
    'holdTop' => _tr(
      'На миг замри вверху',
      'Hold the top briefly',
      'Жоғарғы қалыпта сәл кідіріңіз',
    ),
    'arms' => _tr(
      'Покажи обе руки целиком',
      'Keep both arms visible',
      'Екі қолыңыз да толық көрінсін',
    ),
    'hands' => _tr(
      'Удерживай ладони на месте',
      'Keep your hands in place',
      'Алақандарыңызды орнында ұстаңыз',
    ),
    'tracking' => _tr(
      'Поза плохо видна',
      'Pose tracking uncertain',
      'Дене қалпы анық көрінбейді',
    ),
    'raise' => _tr(
      'Выпрями руки полностью',
      'Press back up with straight arms',
      'Қолыңызды толық жазыңыз',
    ),
    'complete' => _tr('Отлично!', 'Good rep!', 'Жарайсыз!'),
    _ => _tr(
      'Поставь телефон чуть выше пола, камерой к себе и немного вниз. Покажи кисти и стопы.',
      'Set the phone just above the floor, facing you and tilted slightly down. Keep hands and feet in frame.',
      'Телефонды еденнен сәл жоғары қойып, камераны өзіңізге және сәл төмен қаратыңыз. Қол мен аяқ кадрда болсын.',
    ),
  };

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
    if (_disposed ||
        _canceled ||
        !_ownsSession ||
        state.sessionId != _sessionId) {
      return;
    }

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
      _hint =
          exerciseType == ExerciseType.pushUp && !state.sessionStatus.isTerminal
          ? _pushUpHint(state.feedbackMessage!)
          : state.feedbackMessage!;
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
      isUnlockChallenge
          ? 'Подтверждаем временный доступ…'
          : 'Сохраняем тренировку…',
      isUnlockChallenge ? 'Confirming temporary access…' : 'Saving workout…',
      isUnlockChallenge ? 'Уақытша рұқсат расталуда…' : 'Жаттығу сақталуда…',
    );
    _notify();

    try {
      await Future.wait([
        _coordinator.waitForCompletion(),
        _releaseCamera(),
      ]);
    } catch (e) {
      if (!_disposed) _error = '$e';
    }
    await _closePoseDetector();

    if (_disposed || !_ownsSession) return;
    _isFinalizing = false;
    _syncConfirmedGrantState(_coordinator.currentState);
    _notify();
  }

  void _syncConfirmedGrantState(CoordinatorState state) {
    if (state.challengeContext == ChallengeType.freeWorkout) {
      _isFreeWorkoutCompleted = state.isWorkoutPersisted;
      return;
    }

    if (state.accessGrantStatus == AccessGrantStatus.granted &&
        state.unlockUntil != null) {
      final remaining = state.unlockUntil!.difference(_clock());
      if (remaining > Duration.zero) {
        _grantedMinutes = (remaining.inMilliseconds / 60000).ceil().clamp(
          1,
          15,
        );
        _isUnlockConfirmed = true;
        _error = null;
        return;
      }
    }

    if (state.accessGrantStatus == AccessGrantStatus.rejected ||
        state.accessGrantStatus == AccessGrantStatus.failed) {
      _error =
          state.errorMessage ??
          _tr(
            'Не удалось подтвердить доступ.',
            'Could not confirm access.',
            'Рұқсатты растау мүмкін болмады.',
          );
    }
  }

  /// Handles app backgrounding/foregrounding cleanly.
  Future<void> handleLifecycleChange(AppLifecycleState state) async {
    if (_disposed || _canceled) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      _pushUpCounter?.interruptTracking();
      if (_ownsSession) {
        _pushUpPoseAdapter?.processPose(null, timestamp: _clock());
        _poseAdapter?.processAngle(null);
      }
      await _releaseCamera();
      _notify();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      if (!_isTerminal && _ownsSession) {
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

    _detachPoseSource();
    await _releaseCamera();
    await _closePoseDetector();
    await _endOwnedSession('Cancelled by user');
    _notify();
  }

  void _detachPoseSource() {
    final sessionId = _sessionId;
    if (sessionId != null) {
      _coordinator.detachPoseEventSource(sessionId: sessionId);
    }
  }

  void releaseCompletedSession() {
    if (_ownsSession && _coordinator.currentState.sessionStatus.isTerminal) {
      _coordinator.releaseTerminalSession();
    }
  }

  Future<void> _endOwnedSession(String reason) async {
    final pendingStart = _sessionStart;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        return;
      }
    }
    if (!_ownsSession) return;

    final status = _coordinator.currentState.sessionStatus;
    if (status == WorkoutSessionStatus.active ||
        status == WorkoutSessionStatus.preparing) {
      try {
        await _coordinator.cancelCurrentSession(reason: reason);
      } catch (_) {}
    }

    releaseCompletedSession();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _clearPoseOverlay();
    _disposed = true;

    _coordinatorSub?.cancel();
    _coordinatorSub = null;
    _detachPoseSource();

    _poseAdapter?.dispose();
    _pushUpPoseAdapter?.dispose();
    _poseOverlayNotifier.dispose();
    unawaited(
      _releaseCamera().then((_) async {
        await _closePoseDetector();
        await _endOwnedSession('Challenge screen disposed');
      }),
    );

    super.dispose();
  }
}
