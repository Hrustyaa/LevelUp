import 'dart:async';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../../focus_experience/focus_exercises.dart';
import '../../focus_experience/focus_screens.dart';
import '../../focus_experience/focus_style.dart';
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
  final ProductionChallengeController? controllerOverride;

  const ProductionChallengeScreen({
    super.key,
    required this.scope,
    required this.isUnlockChallenge,
    required this.appName,
    this.language = 'ru',
    this.exercise,
    this.controllerOverride,
  });

  @override
  State<ProductionChallengeScreen> createState() =>
      _ProductionChallengeScreenState();
}

class _ProductionChallengeScreenState extends State<ProductionChallengeScreen>
    with WidgetsBindingObserver {
  late final ProductionChallengeController _controller;
  late final bool _ownsController;
  late final FocusExercise _exercise;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _exercise = widget.exercise ??
        focusExercises.firstWhere((e) => e.id == FocusExerciseId.squat);

    if (widget.controllerOverride != null) {
      _controller = widget.controllerOverride!;
      _ownsController = false;
    } else {
      _controller = ProductionChallengeController(
        coordinator: widget.scope.coordinator,
        cameraPermissionChecker: widget.scope.cameraChecker,
        nativeBridge: widget.scope.nativeBridge,
        isUnlockChallenge: widget.isUnlockChallenge,
        language: widget.language,
      );
      _ownsController = true;
    }

    _controller.addListener(_onControllerChanged);
    unawaited(_controller.start());
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_controller.handleLifecycleChange(state));
  }

  Future<void> _handleCancel() async {
    await _controller.cancel();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
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
          widget.scope.coordinator.releaseTerminalSession();
          Navigator.of(context).pop();
        },
      );
    }

    if (_controller.isFreeWorkoutCompleted) {
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
                      'Выполнено ${_controller.repetitions} / ${_controller.targetRepetitions} приседаний. Добровольная тренировка не меняет доступ к приложениям.',
                      'Completed ${_controller.repetitions} / ${_controller.targetRepetitions} squats. Free workouts do not grant app access.',
                      '${_controller.repetitions} / ${_controller.targetRepetitions} отырып-тұру орындалды. Еркін жаттығу қолданбаға рұқсат бермейді.',
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
                      widget.scope.coordinator.releaseTerminalSession();
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
            ? CameraPreview(camera)
            : _controller.error != null
                ? const Icon(Icons.no_photography_outlined)
                : const CircularProgressIndicator();

    return PopScope(
      canPop: !_controller.isFinalizing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_controller.cancel());
        }
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
        onRetry: _controller.canRetry ? () => unawaited(_controller.retry()) : null,
      ),
    );
  }
}
