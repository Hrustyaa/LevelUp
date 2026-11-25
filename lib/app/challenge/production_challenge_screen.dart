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
  late ProductionChallengeController _controller;
  late bool _ownsController;
  late FocusExercise _exercise;

  /// Selected exercise for Free Workout (squats by default, overridable before
  /// the session starts). Always squats for unlock challenges.
  late ExerciseType _selectedExercise;

  /// True once the camera/tracking is live — locks exercise selection.
  bool _sessionStarted = false;

  /// Serializes exercise switches so rapid taps during camera initialization
  /// always converge on the latest selection without controller leaks.
  bool _isSwitchingExercise = false;
  ExerciseType? _queuedExercise;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Resolve preferred exercise from persisted settings (Free Workout only).
    if (!widget.isUnlockChallenge && widget.controllerOverride == null) {
      _selectedExercise = widget.scope.settingsService.currentState.settings
          .preferredExerciseType;
    } else {
      _selectedExercise = ExerciseType.squats;
    }

    _exercise = widget.exercise ?? _resolveDisplayExercise(_selectedExercise);

    _buildController();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.start());
  }

  FocusExercise _resolveDisplayExercise(ExerciseType type) {
    final id = type == ExerciseType.pushUp
        ? FocusExerciseId.pushUp
        : FocusExerciseId.squat;
    return exerciseById(id) ??
        focusExercises.firstWhere((e) => e.id == FocusExerciseId.squat);
  }

  /// Creates (or reuses) a [ProductionChallengeController] for [_selectedExercise].
  void _buildController() {
    if (widget.controllerOverride != null) {
      _controller = widget.controllerOverride!;
      _ownsController = false;
    } else {
      _controller = ProductionChallengeController(
        coordinator: widget.scope.coordinator,
        cameraPermissionChecker: widget.scope.cameraChecker,
        nativeBridge: widget.scope.nativeBridge,
        isUnlockChallenge: widget.isUnlockChallenge,
        exerciseType: widget.isUnlockChallenge
            ? ExerciseType.squats
            : _selectedExercise,
        language: widget.language,
      );
      _ownsController = true;
    }
  }

  /// Called when the user picks a different exercise before the session locks.
  Future<void> _changeExercise(ExerciseType type) async {
    if (_sessionStarted || !_ownsController || widget.isUnlockChallenge) return;
    if (type == _selectedExercise && !_isSwitchingExercise) return;

    _queuedExercise = type;
    if (_isSwitchingExercise) return;
    _isSwitchingExercise = true;

    try {
      while (_queuedExercise != null && mounted && !_sessionStarted) {
        final target = _queuedExercise!;
        _queuedExercise = null;
        if (target == _selectedExercise &&
            _controller.exerciseType == target) {
          continue;
        }

        // Immediately reflect selection in UI so display stays synchronized.
        setState(() {
          _selectedExercise = target;
          _exercise = widget.exercise ?? _resolveDisplayExercise(target);
        });

        await widget.scope.settingsService.updatePreferredExercise(target);
        if (!mounted || _sessionStarted) break;

        _controller.removeListener(_onControllerChanged);
        await _controller.cancel();
        _controller.dispose();
        if (!mounted) break;

        setState(() {
          _buildController();
          _sessionStarted = false;
        });

        _controller.addListener(_onControllerChanged);
        unawaited(_controller.start());
      }
    } finally {
      _isSwitchingExercise = false;
    }
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {
        // Lock exercise selection once tracking or reps are active.
        if ((_controller.trackingReady || _controller.repetitions > 0) &&
            !_sessionStarted) {
          _sessionStarted = true;
        }
      });
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

  String _exerciseLabel(ExerciseType type) {
    switch (type) {
      case ExerciseType.squats:
        return focusTr(widget.language, 'Приседания', 'Squats', 'Отырып-тұру');
      case ExerciseType.pushUp:
        return focusTr(widget.language, 'Отжимания', 'Push-ups', 'Жатып тіреліс');
    }
  }

  /// Compact exercise selector shown in Free Workout before tracking locks in.
  Widget _buildExerciseSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final type in [ExerciseType.squats, ExerciseType.pushUp]) ...[
            if (type != ExerciseType.squats) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(_exerciseLabel(type)),
              selected: _selectedExercise == type,
              onSelected: _sessionStarted
                  ? null
                  : (selected) {
                      if (selected) unawaited(_changeExercise(type));
                    },
              selectedColor: FocusStyle.accent,
              labelStyle: TextStyle(
                color: _selectedExercise == type
                    ? FocusStyle.background
                    : FocusStyle.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              backgroundColor: FocusStyle.surface,
              side: BorderSide(
                color: _selectedExercise == type
                    ? FocusStyle.accent
                    : FocusStyle.muted,
              ),
            ),
          ],
        ],
      ),
    );
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
      final exerciseName = _selectedExercise == ExerciseType.pushUp
          ? focusTr(widget.language, 'отжиманий', 'push-ups', 'жатып тіреліс')
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
        onRetry:
            _controller.canRetry ? () => unawaited(_controller.retry()) : null,
        // Exercise selector for Free Workout only, injected as header content.
        headerExtra: !widget.isUnlockChallenge && widget.controllerOverride == null
            ? _buildExerciseSelector()
            : null,
      ),
    );
  }
}

