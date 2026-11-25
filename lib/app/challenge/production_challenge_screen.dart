import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../features/pose_detection/presentation/pose_overlay_widget.dart';
import '../../focus_experience/focus_exercises.dart';
import '../../focus_v2/focus_camera_cover.dart';
import '../../focus_v2/focus_v2_models.dart';
import '../../focus_v2/focus_v2_screens.dart';
import '../../free_workout/workout_challenge_tab.dart';
import '../../free_workout/workout_session.dart' as presentation;
import '../../focus_experience/focus_style.dart';
import '../../models/exercise_type.dart';
import '../../models/workout_result.dart';
import '../di/app_scope.dart';
import 'production_challenge_controller.dart';

/// Production presentation for the existing verified challenge controller.
class ProductionChallengeScreen extends StatefulWidget {
  final AppScope scope;
  final bool isUnlockChallenge;
  final String appName;
  final FocusTarget? target;
  final String language;
  final FocusExercise? exercise;
  final ExerciseType exerciseType;
  final String? unlockSessionId;
  final ProductionChallengeController? controllerOverride;

  const ProductionChallengeScreen({
    super.key,
    required this.scope,
    required this.isUnlockChallenge,
    required this.appName,
    this.target,
    this.language = 'ru',
    this.exercise,
    this.exerciseType = ExerciseType.squats,
    this.unlockSessionId,
    this.controllerOverride,
  });

  @override
  State<ProductionChallengeScreen> createState() =>
      _ProductionChallengeScreenState();
}

class _ProductionChallengeScreenState extends State<ProductionChallengeScreen>
    with WidgetsBindingObserver {
  late final ProductionChallengeController _controller;
  late final FocusExercise _exercise;
  bool _closing = false;
  Future<WorkoutResult?>? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller =
        widget.controllerOverride ??
        ProductionChallengeController(
          coordinator: widget.scope.coordinator,
          cameraPermissionChecker: widget.scope.cameraChecker,
          nativeBridge: widget.scope.nativeBridge,
          isUnlockChallenge: widget.isUnlockChallenge,
          exerciseType: widget.exerciseType,
          unlockSessionId: widget.unlockSessionId,
          language: widget.language,
        );
    final id = _controller.exerciseType == ExerciseType.pushUp
        ? FocusExerciseId.pushUp
        : FocusExerciseId.squat;
    _exercise = widget.exercise ?? exerciseById(id)!;
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.start());
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_controller.handleLifecycleChange(state));
  }

  Future<void> _handleCancel() async {
    if (_closing || _controller.isFinalizing) return;
    _closing = true;
    await _controller.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    if (widget.controllerOverride == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _finish() {
    _controller.releaseCompletedSession();
    Navigator.of(context).pop();
  }

  String _tr(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  Future<WorkoutResult?> _readResult() {
    final id = widget.scope.coordinator.currentState.sessionId;
    return id == null
        ? Future.value()
        : widget.scope.workoutHistoryRepository.getWorkoutBySessionId(id);
  }

  @override
  Widget build(BuildContext context) {
    final goal = _controller.targetRepetitions;
    if (_controller.isUnlockConfirmed) {
      return FocusV2SuccessScreen(
        target:
            widget.target ??
            FocusTarget(packageName: '', appName: widget.appName),
        goalReps: goal,
        accessMinutes: _controller.grantedMinutes,
        language: widget.language,
        actionText: _tr('Готово', 'Done', 'Дайын'),
        onOpenApp: _finish,
      );
    }

    if (_controller.isFreeWorkoutCompleted) {
      return FutureBuilder<WorkoutResult?>(
        future: _result ??= _readResult(),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null) {
            return WorkoutResultScreen(
              result: presentation.WorkoutResult(
                exercise: result.exerciseType.name,
                startedAt: result.completedAt.subtract(result.duration),
                endedAt: result.completedAt,
                sets: [result.completedRepetitions],
              ),
              saved: true,
              language: widget.language,
              onDone: _finish,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return FocusV2ErrorScreen(
            message: _tr(
              'Не удалось загрузить итоги тренировки.',
              'Could not load the workout result.',
              'Жаттығу нәтижесі жүктелмеді.',
            ),
            language: widget.language,
            onCancel: _finish,
          );
        },
      );
    }

    final camera = _controller.cameraController;
    final preview =
        camera != null &&
            camera.value.isInitialized &&
            !_controller.isFinalizing
        ? focusV2CameraCover(
            camera,
            overlay: PoseOverlayWidget(
              listenable: _controller.poseOverlayListenable,
            ),
          )
        : const Center(child: CircularProgressIndicator());
    final error = _controller.error;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleCancel());
      },
      child: error != null
          ? FocusV2ErrorScreen(
              message: error,
              language: widget.language,
              onCancel: _handleCancel,
              onRetry: _controller.canRetry
                  ? () => unawaited(_controller.retry())
                  : null,
            )
          : FocusV2CameraScreen(
              cameraPreview: preview,
              exerciseName: _exercise.name(widget.language),
              repetitions: _controller.repetitions,
              goalReps: goal,
              poseDetected: _controller.trackingReady,
              verifying: _controller.isFinalizing,
              language: widget.language,
              isFreeWorkout: !widget.isUnlockChallenge,
              status: _controller.hint,
              onCancel: _controller.isFinalizing ? null : _handleCancel,
            ),
    );
  }
}
