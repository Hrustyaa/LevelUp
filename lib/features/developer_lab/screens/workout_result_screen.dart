import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/access_attempt_record.dart';
import '../../../models/challenge_type.dart';
import '../../../models/exercise_type.dart';
import '../../../models/workout_result.dart';
import '../../../models/workout_session.dart';
import '../../../models/workout_session_status.dart';
import '../di/dev_lab_scope.dart';
import '../theme/dev_lab_theme.dart';
import '../widgets/diagnostic_card.dart';
import '../widgets/status_badge.dart';
import 'history_database_screen.dart';

/// Screen 4 — Workout Result: Authoritative inspection of completed or terminal sessions.
///
/// Correlates data across:
/// 1. Coordinator state snapshot
/// 2. WorkoutSessionManager domain model
/// 3. AccessService & native platform gate
/// 4. SQLite WorkoutHistoryRepository & AccessAttemptRepository
class WorkoutResultScreen extends StatefulWidget {
  final String? sessionId;
  final WorkoutResult? initialResult;
  final WorkoutSession? initialSession;

  const WorkoutResultScreen({
    super.key,
    this.sessionId,
    this.initialResult,
    this.initialSession,
  });

  @override
  State<WorkoutResultScreen> createState() => _WorkoutResultScreenState();
}

class _WorkoutResultScreenState extends State<WorkoutResultScreen>
    with WidgetsBindingObserver {
  Timer? _countdownTicker;
  int _loadGeneration = 0;
  bool _isLoading = true;
  String? _loadError;

  WorkoutResult? _persistedWorkout;
  AccessAttemptRecord? _persistedAttempt;
  WorkoutSession? _activeSession;
  DateTime? _nativeUnlockUntil;
  bool _isNativeAccessActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    _countdownTicker?.cancel();
    _countdownTicker = null;
    final controller = DevLabScope.of(context);
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      // 1. Resolve session ID
      final targetSessionId = widget.sessionId ??
          widget.initialResult?.sessionId ??
          widget.initialSession?.sessionId ??
          controller.coordinator.currentState.sessionId ??
          controller.sessionManager.currentSession?.sessionId;

      WorkoutResult? workout;
      AccessAttemptRecord? attempt;
      if (targetSessionId != null) {
        workout = await controller.workoutHistoryRepository
            .getWorkoutBySessionId(targetSessionId);
        attempt = await controller.accessAttemptRepository
            .getAttemptBySessionId(targetSessionId);
      } else {
        final recents = await controller.workoutHistoryRepository.getRecentWorkouts(limit: 1);
        workout = recents.firstOrNull;
        if (workout != null) {
          attempt = await controller.accessAttemptRepository
              .getAttemptBySessionId(workout.sessionId);
        }
      }

      final nativeStatus = await controller.nativeBridge.getState();
      if (!mounted || generation != _loadGeneration) return;
      _persistedWorkout = workout;
      _persistedAttempt = attempt;
      final nativeExpiry = nativeStatus.accessStatus.unlockUntil;
      final matchesAttempt = attempt != null && attempt.isConfirmed &&
          nativeStatus.targetPackage == attempt.targetPackage &&
          nativeExpiry?.millisecondsSinceEpoch == attempt.unlockUntil?.millisecondsSinceEpoch;
      _nativeUnlockUntil = matchesAttempt ? nativeExpiry : null;
      _isNativeAccessActive = matchesAttempt && nativeStatus.accessStatus.isAccessActive();

      final current = controller.sessionManager.currentSession;
      _activeSession = current != null &&
              (targetSessionId == null || current.sessionId == targetSessionId)
          ? current
          : null;
    } catch (e) {
      if (mounted && generation == _loadGeneration) _loadError = e.toString();
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
        // Start countdown ticker only when there is an active timed access window in the future.
        // This prevents the timer from keeping the Flutter clock busy in tests
        // or ticking needlessly when expired.
        if (_nativeUnlockUntil != null &&
            _nativeUnlockUntil!.isAfter(DateTime.now()) &&
            _countdownTicker == null) {
          _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted) return;
            if (_nativeUnlockUntil != null) {
              final remainingMs =
                  _nativeUnlockUntil!.difference(DateTime.now()).inMilliseconds;
              final nowActive = remainingMs > 0;
              if (nowActive != _isNativeAccessActive) {
                setState(() => _isNativeAccessActive = nowActive);
              } else {
                setState(() {});
              }
              if (remainingMs <= 0) {
                _countdownTicker?.cancel();
                _countdownTicker = null;
              }
            }
          });
        }
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--';
    final local = dt.toLocal();
    final y = local.year.toString();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = DevLabScope.of(context);
    final coordState = controller.coordinator.currentState;

    // Authoritative properties resolved with priority: persisted DB -> in-memory result/session -> coordinator
    final sessionId = _persistedWorkout?.sessionId ??
        widget.initialResult?.sessionId ??
        _activeSession?.sessionId ??
        widget.initialSession?.sessionId ??
        coordState.sessionId ??
        'N/A';

    final challengeId = _persistedWorkout?.challengeId ??
        widget.initialResult?.challengeId ??
        _activeSession?.challengeId ??
        widget.initialSession?.challengeId ??
        coordState.challenge?.challengeId ??
        'unknown_challenge';

    final contextType = _persistedWorkout?.challengeContext ??
        widget.initialResult?.challengeContext ??
        _activeSession?.challengeContext ??
        widget.initialSession?.challengeContext ??
        coordState.challengeContext ??
        ChallengeType.freeWorkout;

    final exerciseType = _persistedWorkout?.exerciseType ??
        widget.initialResult?.exerciseType ??
        _activeSession?.exerciseType ??
        widget.initialSession?.exerciseType ??
        ExerciseType.squats;

    final targetReps = _activeSession?.targetRepetitions ??
        widget.initialSession?.targetRepetitions ??
        coordState.targetRepetitions;

    final completedReps = _persistedWorkout?.completedRepetitions ??
        widget.initialResult?.completedRepetitions ??
        _activeSession?.verifiedRepetitions ??
        widget.initialSession?.verifiedRepetitions ??
        coordState.verifiedRepetitions;

    final duration = _persistedWorkout?.duration ??
        widget.initialResult?.duration ??
        _activeSession?.duration ??
        widget.initialSession?.duration ??
        Duration.zero;

    final startedAt = _activeSession?.startedAt ?? widget.initialSession?.startedAt;
    final completedAt = _persistedWorkout?.completedAt ??
        widget.initialResult?.completedAt ??
        _activeSession?.completedAt ??
        widget.initialSession?.completedAt;

    final sessionStatus = widget.initialSession?.status ??
        _activeSession?.status ??
        ((_persistedWorkout != null || widget.initialResult != null)
            ? WorkoutSessionStatus.completed
            : coordState.sessionStatus);

    final targetPackage = _persistedWorkout?.targetPackage ??
        widget.initialResult?.targetPackage ??
        _activeSession?.targetPackage ??
        widget.initialSession?.targetPackage ??
        coordState.selectedTarget;

    final isPersisted = _persistedWorkout != null;
    final errorMessage = coordState.errorMessage ??
        _activeSession?.failureReason ??
        widget.initialSession?.failureReason ??
        _persistedAttempt?.failureReason;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout Result Inspection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh result data',
            onPressed: _loadData,
          ),
        ],
      ),
      body: (_isLoading && _persistedWorkout == null && widget.initialResult == null && widget.initialSession == null)
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (_loadError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: DevLabTheme.statusError.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: DevLabTheme.statusError),
                      ),
                      child: Text(
                        'Data query error: $_loadError',
                        style: const TextStyle(color: DevLabTheme.statusError, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 1. Header Card: Session ID & Lifecycle Status
                  _buildHeaderCard(
                    sessionId: sessionId,
                    challengeId: challengeId,
                    contextType: contextType,
                    status: sessionStatus,
                  ),

                  const SizedBox(height: 12),

                  // 2. Biomechanics & Repetitions Card
                  _buildRepetitionCard(
                    exerciseType: exerciseType,
                    completedReps: completedReps,
                    targetReps: targetReps,
                    duration: duration,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    source: _persistedWorkout?.source ?? widget.initialResult?.source ?? 'camera',
                  ),

                  const SizedBox(height: 12),

                  // 3. SQLite Persistence Status Card
                  _buildPersistenceCard(
                    isPersisted: isPersisted,
                    workout: _persistedWorkout,
                  ),

                  const SizedBox(height: 12),

                  // 4. Access Engine & Native Gate Card
                  _buildAccessEngineCard(
                    contextType: contextType,
                    targetPackage: targetPackage,
                    attempt: _persistedAttempt,
                    unlockUntil: _nativeUnlockUntil ?? _persistedAttempt?.unlockUntil,
                    isNativeActive: _isNativeAccessActive,
                  ),

                  if (errorMessage != null && errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildErrorCard(errorMessage),
                  ],

                  const SizedBox(height: 16),

                  // 5. Navigation Actions
                  _buildActionButtons(sessionId: sessionId, controller: controller),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard({
    required String sessionId,
    required String challengeId,
    required ChallengeType contextType,
    required WorkoutSessionStatus status,
  }) {
    Color statusColor;
    String statusLabel;

    switch (status) {
      case WorkoutSessionStatus.completed:
        statusColor = DevLabTheme.statusSuccess;
        statusLabel = 'COMPLETED';
        break;
      case WorkoutSessionStatus.cancelled:
        statusColor = DevLabTheme.statusWarning;
        statusLabel = 'CANCELLED';
        break;
      case WorkoutSessionStatus.failed:
        statusColor = DevLabTheme.statusError;
        statusLabel = 'FAILED';
        break;
      default:
        statusColor = DevLabTheme.statusNeutral;
        statusLabel = status.name.toUpperCase();
    }

    final isUnlock = contextType == ChallengeType.unlockChallenge;

    return DiagnosticCard(
      title: 'Session Overview',
      subtitle: 'Authoritative session lifecycle status',
      icon: Icons.assignment_outlined,
      badge: StatusBadge(label: statusLabel, color: statusColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session ID',
                      style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sessionId,
                      style: const TextStyle(
                        color: DevLabTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: DevLabTheme.accent),
                tooltip: 'Copy Session ID',
                onPressed: () => _copyToClipboard(sessionId, 'Session ID'),
              ),
            ],
          ),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Challenge Context',
                style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isUnlock
                      ? DevLabTheme.accent.withValues(alpha: 0.15)
                      : DevLabTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isUnlock ? 'UNLOCK CHALLENGE' : 'FREE WORKOUT',
                  style: TextStyle(
                    color: isUnlock ? DevLabTheme.accent : DevLabTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _infoRow('Challenge ID', challengeId),
        ],
      ),
    );
  }

  Widget _buildRepetitionCard({
    required ExerciseType exerciseType,
    required int completedReps,
    required int targetReps,
    required Duration duration,
    required DateTime? startedAt,
    required DateTime? completedAt,
    required String source,
  }) {
    final goalAchieved = completedReps >= targetReps && targetReps > 0;

    return DiagnosticCard(
      title: 'Physical Exercise Metrics',
      subtitle: 'Biomechanical repetition count and active duration',
      icon: Icons.fitness_center_rounded,
      badge: StatusBadge(
        label: goalAchieved ? 'Goal Achieved' : 'Incomplete',
        color: goalAchieved ? DevLabTheme.statusSuccess : DevLabTheme.statusWarning,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricTile('Exercise', exerciseType.name.toUpperCase(), DevLabTheme.textPrimary),
              _metricTile(
                'Repetitions',
                '$completedReps / $targetReps',
                goalAchieved ? DevLabTheme.accent : DevLabTheme.statusWarning,
              ),
              _metricTile('Duration', _formatDuration(duration), DevLabTheme.textPrimary),
              _metricTile('Source', source.toUpperCase(), DevLabTheme.textSecondary),
            ],
          ),
          const Divider(height: 20),
          _infoRow('Started At', _formatDateTime(startedAt)),
          _infoRow('Completed At', _formatDateTime(completedAt)),
        ],
      ),
    );
  }

  Widget _buildPersistenceCard({
    required bool isPersisted,
    required WorkoutResult? workout,
  }) {
    return DiagnosticCard(
      title: 'SQLite Local Persistence',
      subtitle: 'Module 07: ACID transaction & audit consistency',
      icon: Icons.storage_rounded,
      badge: StatusBadge(
        label: isPersisted ? 'Persisted in DB' : 'Not Persisted',
        color: isPersisted ? DevLabTheme.statusSuccess : DevLabTheme.statusError,
      ),
      child: Column(
        children: [
          _infoRow('Table', 'workout_sessions'),
          _infoRow('Storage Status', isPersisted ? 'Committed & Verified' : 'No DB record found'),
          if (workout != null) ...[
            _infoRow('Earned XP', '${workout.earnedXp} XP'),
            _infoRow('Verification Origin', workout.source),
          ],
        ],
      ),
    );
  }

  Widget _buildAccessEngineCard({
    required ChallengeType contextType,
    required String? targetPackage,
    required AccessAttemptRecord? attempt,
    required DateTime? unlockUntil,
    required bool isNativeActive,
  }) {
    final isUnlock = contextType == ChallengeType.unlockChallenge;

    if (!isUnlock) {
      return DiagnosticCard(
        title: 'Access Engine Authorization',
        subtitle: 'Module 06: Voluntary Free Workout isolation',
        icon: Icons.lock_clock_rounded,
        badge: const StatusBadge(label: 'N/A (Free Workout)', color: DevLabTheme.statusNeutral),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: DevLabTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_outlined, size: 20, color: DevLabTheme.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Free Workout mode strictly enforces that no native access request is generated or granted.',
                  style: TextStyle(color: DevLabTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Evaluate live wall-clock active status
    final now = DateTime.now();
    final remainingMs = unlockUntil != null ? unlockUntil.difference(now).inMilliseconds : 0;
    final isCurrentlyActive = remainingMs > 0;

    String currentAccessLabel;
    Color currentAccessColor;

    if (isCurrentlyActive) {
      final totalSec = (remainingMs / 1000).ceil();
      final m = totalSec ~/ 60;
      final s = totalSec % 60;
      final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      currentAccessLabel = 'ACTIVE ($timeStr remaining)';
      currentAccessColor = DevLabTheme.statusSuccess;
    } else if (unlockUntil != null) {
      currentAccessLabel = 'EXPIRED (Historically Confirmed)';
      currentAccessColor = DevLabTheme.statusWarning;
    } else {
      currentAccessLabel = attempt?.state.name.toUpperCase() ?? 'NO GRANT';
      currentAccessColor = DevLabTheme.statusError;
    }

    return DiagnosticCard(
      title: 'Access Engine Authorization',
      subtitle: 'Module 06: Native temporary unlock status',
      icon: Icons.vpn_key_rounded,
      badge: StatusBadge(label: currentAccessLabel, color: currentAccessColor),
      child: Column(
        children: [
          _infoRow('Target Package', targetPackage ?? '--'),
          _infoRow('Attempt Journal State', attempt?.state.name.toUpperCase() ?? 'None'),
          _infoRow('Authoritative unlockUntil', _formatDateTime(unlockUntil)),
          _infoRow(
            'Current Gate Status',
            isCurrentlyActive ? 'UNLOCKED' : 'RESTRICTED',
            valueColor: isCurrentlyActive ? DevLabTheme.statusSuccess : DevLabTheme.statusWarning,
          ),
          if (attempt?.failureReason != null)
            _infoRow('Attempt Error Reason', attempt!.failureReason!, valueColor: DevLabTheme.statusError),
          if (!isCurrentlyActive && unlockUntil != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DevLabTheme.statusWarning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DevLabTheme.statusWarning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: DevLabTheme.statusWarning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'IMPORTANT: A historically confirmed grant is NOT currently active once the 300s window has expired.',
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

  Widget _buildErrorCard(String error) {
    return DiagnosticCard(
      title: 'Session Error Diagnostic',
      subtitle: 'Exact error captured during execution or completion',
      icon: Icons.error_outline_rounded,
      badge: const StatusBadge(label: 'ERROR', color: DevLabTheme.statusError),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: DevLabTheme.statusError.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          error,
          style: const TextStyle(
            color: DevLabTheme.statusError,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons({
    required String sessionId,
    required DevLabController controller,
  }) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.storage_outlined, size: 18),
            label: const Text('View in History & Database'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HistoryDatabaseScreen(highlightSessionId: sessionId),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to System Hub'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value, Color color) {
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

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? DevLabTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
