import 'dart:async';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/pose_detection/presentation/pose_overlay_widget.dart';
import '../../focus_experience/focus_exercises.dart';
import '../../focus_experience/focus_screens.dart';
import '../../focus_experience/focus_style.dart';
import '../../models/exercise_type.dart';
import '../di/app_scope.dart';
import 'production_challenge_controller.dart';

/// Production challenge route connecting [FocusChallengeScreen] and
/// [FocusAccessGrantedScreen] to [ProductionChallengeController] and
/// [CoreIntegrationCoordinator].
class ProductionChallengeScreen extends StatefulWidget {
  final AppScope scope;
  final bool isUnlockChallenge;
  final String appName;
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

  @override
  Widget build(BuildContext context) {
    if (_controller.isUnlockConfirmed) {
      return FocusAccessGrantedScreen(
        appName: widget.appName,
        accessMinutes: _controller.grantedMinutes,
        language: widget.language,
        onDone: () {
          _controller.releaseCompletedSession();
          Navigator.of(context).pop();
        },
      );
    }

    if (_controller.isFreeWorkoutCompleted) {
      final exerciseName = _controller.exerciseType == ExerciseType.pushUp
          ? focusTr(widget.language, 'отжиманий', 'push-ups', 'қолды бүгіп-жазу')
          : focusTr(widget.language, 'приседаний', 'squats', 'отырып-тұру');
      return Theme(
        data: FocusStyle.theme(),
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 64,
                    color: FocusStyle.accent,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    focusTr(
                      widget.language,
                      'Тренировка завершена',
                      'Workout complete',
                      'Жаттығу аяқталды',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    focusTr(
                      widget.language,
                      'Выполнено ${_controller.repetitions} / ${_controller.targetRepetitions} $exerciseName. Добровольная тренировка не меняет доступ к приложениям.',
                      'Completed ${_controller.repetitions} / ${_controller.targetRepetitions} $exerciseName. Free workouts do not grant app access.',
                      '${_controller.repetitions} / ${_controller.targetRepetitions} $exerciseName орындалды. Еркін жаттығу қолданбаға рұқсат бермейді.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FocusStyle.muted,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FocusPrimaryButton(
                    text: focusTr(widget.language, 'Готово', 'Done', 'Дайын'),
                    onPressed: () {
                      _controller.releaseCompletedSession();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final camera = _controller.cameraController;
    final Widget? preview = _controller.isFinalizing
        ? null
        : camera != null && camera.value.isInitialized
        ? Stack(
            fit: StackFit.passthrough,
            children: [
              CameraPreview(camera),
              Positioned.fill(
                child: PoseOverlayWidget(
                  listenable: _controller.poseOverlayListenable,
                ),
              ),
            ],
          )
        : _controller.error != null
        ? const Icon(Icons.no_photography_outlined)
        : const CircularProgressIndicator();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleCancel());
      },
      child: FocusChallengeScreen(
        exercise: _exercise,
        repetitions: _controller.repetitions,
        language: widget.language,
        cameraReady: _controller.cameraReady,
        trackingReady: _controller.trackingReady,
        cameraPreview: preview,
        hint: _controller.hint,
        error: _controller.error,
        onCancel: _controller.isFinalizing ? null : _handleCancel,
        onRetry: _controller.canRetry
            ? () => unawaited(_controller.retry())
            : null,
      ),
    );
  }
}
