import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/errors/challenge_exceptions.dart';
import '../../../core/integration/coordinator_state.dart';
import '../../../core/integration/pose_event_adapter.dart';
import '../../../features/pose_detection/application/squat_counter.dart';
import '../../../features/pose_detection/application/squat_geometry.dart';
import '../../../models/access_grant_status.dart';
import '../../../models/challenge_type.dart';
import '../../../models/workout_session_status.dart';
import '../di/dev_lab_scope.dart';
import '../models/diagnostic_event.dart';
import '../theme/dev_lab_theme.dart';
import '../widgets/diagnostic_card.dart';
import '../widgets/live_event_log_view.dart';
import '../widgets/status_badge.dart';

/// Screen 3 — Live Challenge Screen: Front camera pose tracking and workout orchestration.
///
/// Integrates real NV21 front camera feed with Google ML Kit PoseDetector,
/// evaluates knee biomechanics via SquatGeometry, and drives the Coordinator
/// for Free Workouts and authentic native Blocker Unlock Challenges.
class LiveChallengeScreen extends StatefulWidget {
  final bool isUnlockFromNative;

  const LiveChallengeScreen({
    super.key,
    this.isUnlockFromNative = false,
  });

  @override
  State<LiveChallengeScreen> createState() => _LiveChallengeScreenState();
}

class _LiveChallengeScreenState extends State<LiveChallengeScreen>
    with WidgetsBindingObserver {
  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  PoseDetector? _poseDetector;
  late PoseEngineAdapter _poseAdapter;
  StreamSubscription<CoordinatorState>? _coordinatorSubscription;
  DevLabController? _controller;

  bool _isProcessingFrame = false;
  String? _cameraError;
  double? _currentKneeAngle;
  SquatPhase _currentPhase = SquatPhase.up;
  String _feedbackMessage = 'Встань так, чтобы камера видела ноги и корпус';
  bool _isTrackingValid = false;
  bool _isActionInProgress = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = DevLabScope.of(context);
    _poseAdapter = PoseEngineAdapter(
      isSimulated: _controller?.executionMode.isSimulation ?? false,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = DevLabScope.of(context);

      // Listen to reactive Coordinator updates
      _coordinatorSubscription = controller.coordinator.stateStream.listen((_) {
        if (mounted) setState(() {});
      });

      // Initialize ML Kit PoseDetector
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );

      _openCamera();

      if (widget.isUnlockFromNative) {
        if (controller.coordinator.currentState.sessionStatus ==
                WorkoutSessionStatus.active ||
            controller.coordinator.currentState.sessionStatus ==
                WorkoutSessionStatus.preparing) {
          _poseAdapter.reset();
          controller.coordinator.attachPoseEventSource(_poseAdapter);
        } else {
          _startUnlockChallenge();
        }
      } else {
        if (controller.coordinator.currentState.sessionStatus ==
            WorkoutSessionStatus.completed) {
          controller.coordinator.releaseTerminalSession();
          _poseAdapter.reset();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coordinatorSubscription?.cancel();

    _controller?.coordinator.detachPoseEventSource();

    _poseAdapter.dispose();
    _poseDetector?.close();
    _releaseCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed && mounted) {
      _openCamera();
      _controller?.refreshAll();
    }
  }

  Future<void> _openCamera() async {
    if (_cameraController != null || !mounted) return;

    try {
      final available = await availableCameras().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => <CameraDescription>[],
      );
      if (!mounted) return;

      if (available.isEmpty) {
        setState(() {
          _cameraError = 'No camera hardware found in this environment.';
        });
        return;
      }

      final camera = available.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => available.first,
      );

      final next = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      _cameraController = next;
      _cameraDescription = camera;
      await next.initialize();

      if (!mounted || _cameraController != next) {
        await next.dispose();
        return;
      }

      await next.startImageStream(_onFrame);

      if (mounted) {
        setState(() {
          _cameraError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraError = e.toString();
        });
      }
      await _releaseCamera();
    }
  }

  Future<void> _releaseCamera() async {
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

  InputImage? _fromCameraImage(CameraImage image) {
    final active = _cameraController;
    final description = _cameraDescription;
    if (active == null || description == null || image.planes.length != 1) return null;

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
    if (_isProcessingFrame || !mounted) return;
    final input = _fromCameraImage(image);
    if (input == null) return;

    _isProcessingFrame = true;
    _processFrame(input).whenComplete(() => _isProcessingFrame = false);
  }

  Future<void> _processFrame(InputImage input) async {
    final detector = _poseDetector;
    if (detector == null) return;

    try {
      final poses = await detector.processImage(input);
      if (!mounted) return;

      if (poses.isEmpty) {
        setState(() {
          _isTrackingValid = false;
          _currentKneeAngle = null;
          _feedbackMessage = 'Человек не найден — отойди дальше от телефона';
        });
        _poseAdapter.processAngle(null);
        return;
      }

      final pose = poses.first;
      final angle = _estimateKneeAngle(pose);

      if (angle == null) {
        setState(() {
          _isTrackingValid = false;
          _currentKneeAngle = null;
          _feedbackMessage = 'Не вижу бедро, колено и стопу — повернись боком';
        });
        _poseAdapter.processAngle(null);
        return;
      }

      // Valid frame evaluated
      final result = _poseAdapter.processAngle(angle);

      if (mounted) {
        setState(() {
          _isTrackingValid = true;
          _currentKneeAngle = angle;
          _currentPhase = result.phase;
          _feedbackMessage = result.feedbackMessage;
        });
      }
    } catch (_) {
      // Ignore individual frame ML Kit failures
    }
  }

  double? _estimateKneeAngle(Pose pose) {
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

  Future<void> _startFreeWorkout() async {
    final controller = DevLabScope.of(context);
    if (controller.executionMode.isReal && _cameraError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot launch in Real Device mode without an operational front camera.',
          ),
          backgroundColor: DevLabTheme.statusError,
        ),
      );
      return;
    }

    setState(() => _isActionInProgress = true);

    try {
      controller.logService.info(
        BackendModuleId.sessionManager,
        'Starting Free Workout (5 reps goal)',
      );
      _poseAdapter.reset();
      await controller.coordinator.launchFreeWorkout();
      controller.coordinator.attachPoseEventSource(_poseAdapter);
    } catch (e) {
      controller.logService.error(
        BackendModuleId.sessionManager,
        'Failed to start Free Workout: $e',
      );
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _startUnlockChallenge() async {
    final controller = DevLabScope.of(context);
    if (controller.executionMode.isReal && _cameraError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot launch in Real Device mode without an operational front camera.',
          ),
          backgroundColor: DevLabTheme.statusError,
        ),
      );
      return;
    }

    setState(() => _isActionInProgress = true);

    try {
      controller.logService.info(
        BackendModuleId.sessionManager,
        'Starting Unlock Challenge (5 reps goal for ${controller.currentFocusState?.targetDisplayName})',
      );
      _poseAdapter.reset();
      await controller.coordinator.launchUnlockChallenge(
        requirePendingRequest: !controller.executionMode.isSimulation,
      );
      controller.coordinator.attachPoseEventSource(_poseAdapter);
    } on InvalidChallengeRequestException {
      controller.logService.warning(
        BackendModuleId.sessionManager,
        'No pending native challenge request flag found.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No pending challenge request from Android Blocker overlay. Open a restricted app to trigger the blocker overlay first, or switch to Simulation Mode.',
            ),
            backgroundColor: DevLabTheme.statusWarning,
          ),
        );
      }
    } catch (e) {
      controller.logService.error(
        BackendModuleId.sessionManager,
        'Failed to start Unlock Challenge: $e',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot start challenge: $e'),
            backgroundColor: DevLabTheme.statusError,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _cancelWorkout() async {
    final controller = DevLabScope.of(context);
    try {
      controller.logService.warning(
        BackendModuleId.sessionManager,
        'Workout cancelled by user',
      );
      await controller.coordinator.cancelCurrentSession();
      _poseAdapter.reset();
    } catch (e) {
      controller.logService.error(
        BackendModuleId.sessionManager,
        'Error cancelling workout: $e',
      );
    }
  }

  // Simulation helpers for automated testing or headless/emulator validation
  void _simulateAngle(double angle) {
    final controller = DevLabScope.of(context);
    if (controller.executionMode.isReal) {
      throw StateError('Simulated joint angles are strictly forbidden in Real Device mode.');
    }

    final result = _poseAdapter.processAngle(angle, isSimulated: true);
    setState(() {
      _isTrackingValid = true;
      _currentKneeAngle = angle;
      _currentPhase = result.phase;
      _feedbackMessage = result.feedbackMessage;
    });
  }

  void _simulateSingleRep() {
    final controller = DevLabScope.of(context);
    if (controller.executionMode.isReal) {
      throw StateError('Simulated joint angles are strictly forbidden in Real Device mode.');
    }

    // 2 consecutive down frames (<125)
    _simulateAngle(110.0);
    _simulateAngle(110.0);
    // 2 consecutive up frames (>155)
    _simulateAngle(165.0);
    _simulateAngle(165.0);
  }

  void _simulateFullFiveReps() {
    final controller = DevLabScope.of(context);
    if (controller.executionMode.isReal) {
      throw StateError('Simulated joint angles are strictly forbidden in Real Device mode.');
    }

    for (int i = 0; i < 5; i++) {
      _simulateSingleRep();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = DevLabScope.of(context);
    final coordState = controller.coordinator.currentState;
    final isSessionActive = coordState.sessionStatus == WorkoutSessionStatus.active;
    final isSessionCompleted = coordState.sessionStatus == WorkoutSessionStatus.completed;
    final isCameraBlockedInRealMode =
        controller.executionMode.isReal && _cameraError != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LIVE CHALLENGE'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: StatusBadge(
              label: coordState.sessionStatus.name.toUpperCase(),
              color: isSessionCompleted
                  ? DevLabTheme.statusSuccess
                  : isSessionActive
                      ? DevLabTheme.accent
                      : DevLabTheme.statusNeutral,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Live Camera Viewport & HUD
            _buildCameraViewport(),

            if (isCameraBlockedInRealMode) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DevLabTheme.statusError.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DevLabTheme.statusError),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.videocam_off_rounded, color: DevLabTheme.statusError, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Camera Sensor Required in Real Device Mode',
                            style: TextStyle(
                              color: DevLabTheme.statusError,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Real Device mode requires front camera pose verification to unlock apps. Simulated joint angles are strictly disabled in Real Device mode. To test without camera hardware, switch to Simulation Mode in System Hub.',
                            style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // 2. Biomechanical Pose Metrics Bar
            _buildPoseMetricsCard(),

            const SizedBox(height: 12),

            // 3. Challenge Session Status & Repetition Progress
            _buildProgressCard(coordState),

            const SizedBox(height: 12),

            // 4. Session Action Buttons / Completion Victory Card
            if (isSessionCompleted)
              _buildVictoryCard(coordState, controller)
            else if (isSessionActive)
              _buildActiveControlsCard()
            else
              _buildStartSessionCard(
                isCameraBlocked: isCameraBlockedInRealMode,
              ),

            // 5. Simulation Testing Toolset (STRICTLY available in Simulation mode only)
            if (controller.executionMode.isSimulation)
              _buildSimulationControls(isSessionActive),

            const SizedBox(height: 14),

            // 6. Live Event Log
            LiveEventLogView(
              logService: controller.logService,
              initialExpanded: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraViewport() {
    final isCameraReady =
        _cameraController != null && _cameraController!.value.isInitialized;

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: DevLabTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isTrackingValid ? DevLabTheme.accent : DevLabTheme.surfaceElevated,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isCameraReady)
            CameraPreview(_cameraController!)
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_off_outlined,
                    size: 40,
                    color: _cameraError != null
                        ? DevLabTheme.statusWarning
                        : DevLabTheme.textMuted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _cameraError ?? 'Initializing Camera...',
                    style: TextStyle(
                      color: _cameraError != null
                          ? DevLabTheme.statusWarning
                          : DevLabTheme.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // HUD Overlay: Feedback message banner
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: DevLabTheme.background.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isTrackingValid
                      ? DevLabTheme.accent.withValues(alpha: 0.6)
                      : DevLabTheme.statusWarning.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isTrackingValid ? Icons.check_circle_outline : Icons.info_outline,
                    size: 16,
                    color: _isTrackingValid ? DevLabTheme.accent : DevLabTheme.statusWarning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _feedbackMessage,
                      style: const TextStyle(
                        color: DevLabTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoseMetricsCard() {
    final angleText = _currentKneeAngle != null
        ? '${_currentKneeAngle!.toStringAsFixed(1)}°'
        : '--°';

    Color angleColor;
    if (_currentKneeAngle == null) {
      angleColor = DevLabTheme.textMuted;
    } else if (_currentKneeAngle! < SquatThresholds.downAngle) {
      angleColor = DevLabTheme.accent; // In deep squat threshold
    } else if (_currentKneeAngle! > SquatThresholds.upAngle) {
      angleColor = DevLabTheme.statusSuccess; // Standing upright
    } else {
      angleColor = DevLabTheme.textPrimary; // Transitioning
    }

    return DiagnosticCard(
      title: 'Pose Engine Biometrics',
      subtitle: 'Real-time knee joint angle and phase calculation (SquatGeometry)',
      icon: Icons.accessibility_new_rounded,
      badge: StatusBadge(
        label: _isTrackingValid ? 'Tracking Active' : 'No Target',
        color: _isTrackingValid ? DevLabTheme.statusSuccess : DevLabTheme.statusNeutral,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metricColumn('Knee Angle', angleText, angleColor),
          _metricColumn(
            'Movement Phase',
            _currentPhase == SquatPhase.down ? 'DOWN (Squat)' : 'UP (Standing)',
            _currentPhase == SquatPhase.down ? DevLabTheme.accent : DevLabTheme.textPrimary,
          ),
          _metricColumn(
            'Thresholds',
            '<125° / >155°',
            DevLabTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _metricColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(CoordinatorState state) {
    final reps = state.verifiedRepetitions;
    final goal = state.targetRepetitions > 0 ? state.targetRepetitions : 5;
    final progress = (reps / goal).clamp(0.0, 1.0);

    return DiagnosticCard(
      title: 'Session Repetition Progress',
      subtitle: state.sessionId != null
          ? 'Session ID: ${state.sessionId}'
          : 'No workout session started yet',
      icon: Icons.fitness_center_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$reps / $goal Verified Repetitions',
                style: const TextStyle(
                  color: DevLabTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  color: DevLabTheme.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: DevLabTheme.surfaceElevated,
            valueColor: const AlwaysStoppedAnimation<Color>(DevLabTheme.accent),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          if (state.challengeContext != null) ...[
            const SizedBox(height: 8),
            Text(
              'Context: ${state.challengeContext!.name.toUpperCase()} ${state.selectedTarget != null ? "(${state.selectedTarget})" : ""}',
              style: const TextStyle(color: DevLabTheme.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartSessionCard({
    required bool isCameraBlocked,
  }) {
    return DiagnosticCard(
      title: 'Launch Workout Challenge',
      subtitle: 'Select challenge workflow to run through the Coordinator',
      icon: Icons.play_arrow_rounded,
      child: Column(
        children: [
          // 1. Free Workout Launch
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.fitness_center_outlined, size: 18),
              label: const Text('Start Free Workout (5 Reps)'),
              onPressed: (_isActionInProgress || isCameraBlocked)
                  ? null
                  : _startFreeWorkout,
            ),
          ),
          const SizedBox(height: 8),

          // 2. Unlock Challenge Launch
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Start Unlock Challenge (5 Reps)'),
              onPressed: (_isActionInProgress || isCameraBlocked)
                  ? null
                  : _startUnlockChallenge,
            ),
          ),

          if (isCameraBlocked) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DevLabTheme.statusError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: DevLabTheme.statusError.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.block_rounded, size: 16, color: DevLabTheme.statusError),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Workouts cannot be launched while camera is unavailable in Real Device mode. Switch to Simulation Mode to test without camera hardware.',
                      style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveControlsCard() {
    return DiagnosticCard(
      title: 'Session in Progress',
      subtitle: 'Physical tracking active. Repetitions are verified in real time.',
      icon: Icons.timer_outlined,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: DevLabTheme.statusError,
            side: const BorderSide(color: DevLabTheme.statusError),
          ),
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('Cancel Workout Session'),
          onPressed: _cancelWorkout,
        ),
      ),
    );
  }

  Widget _buildVictoryCard(CoordinatorState state, DevLabController controller) {
    final isUnlock = state.challengeContext == ChallengeType.unlockChallenge;
    final isAccessGranted = state.accessGrantStatus == AccessGrantStatus.granted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DevLabTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DevLabTheme.statusSuccess, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: DevLabTheme.statusSuccess, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Workout Completed!',
                      style: TextStyle(
                        color: DevLabTheme.statusSuccess,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '5 of 5 verified repetitions achieved',
                      style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: DevLabTheme.surfaceElevated, height: 24),
          Text(
            isUnlock
                ? (isAccessGranted
                    ? 'Native Access Granted: 5 minutes granted for target app.'
                    : 'Access Engine Status: ${state.accessGrantStatus?.name ?? "Pending"}')
                : 'Free Workout persisted in SQLite database. No access grant executed (as intended).',
            style: const TextStyle(color: DevLabTheme.textPrimary, fontSize: 13),
          ),
          if (state.unlockUntil != null && isUnlock) ...[
            const SizedBox(height: 6),
            Text(
              'Unlocked until: ${state.unlockUntil!.toLocal()}',
              style: const TextStyle(
                color: DevLabTheme.accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Start New Challenge'),
                  onPressed: () {
                    controller.coordinator.releaseTerminalSession();
                    _poseAdapter.reset();
                    if (mounted) {
                      setState(() {
                        _feedbackMessage = 'Встань так, чтобы камера видела ноги и корпус';
                        _currentKneeAngle = null;
                        _currentPhase = SquatPhase.up;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: const Text('Return to Hub'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationControls(bool isSessionActive) {
    return DiagnosticCard(
      title: 'QA Simulation Toolset',
      subtitle: 'Simulate biomechanical joint movements without camera hardware',
      icon: Icons.science_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSessionActive ? () => _simulateAngle(110.0) : null,
                  child: const Text('Down (110°)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: isSessionActive ? () => _simulateAngle(165.0) : null,
                  child: const Text('Up (165°)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DevLabTheme.surfaceElevated,
                    foregroundColor: DevLabTheme.textPrimary,
                  ),
                  onPressed: isSessionActive ? _simulateSingleRep : null,
                  child: const Text('+1 Verified Rep'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DevLabTheme.accent,
                    foregroundColor: DevLabTheme.background,
                  ),
                  onPressed: isSessionActive ? _simulateFullFiveReps : null,
                  child: const Text('Finish 5 Reps'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
