import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/access_attempt_record.dart';
import '../../../models/access_attempt_state.dart';
import '../../../models/challenge_type.dart';
import '../../../models/workout_result.dart';
import '../di/dev_lab_scope.dart';
import '../models/dev_mode.dart';
import '../theme/dev_lab_theme.dart';
import '../widgets/status_badge.dart';
import 'workout_result_screen.dart';

/// Screen 5 — History & Database: Read-only inspection of persisted workouts and access attempts.
///
/// Connects directly to [IWorkoutHistoryRepository] and [IAccessAttemptRepository].
/// Strictly respects Real Device vs. Simulation Mode database isolation.
class HistoryDatabaseScreen extends StatefulWidget {
  final String? highlightSessionId;

  const HistoryDatabaseScreen({
    super.key,
    this.highlightSessionId,
  });

  @override
  State<HistoryDatabaseScreen> createState() => _HistoryDatabaseScreenState();
}

class _HistoryDatabaseScreenState extends State<HistoryDatabaseScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;

  bool _isLoading = true;
  String? _loadError;

  List<WorkoutResult> _allWorkouts = [];
  List<AccessAttemptRecord> _allAttempts = [];
  int _totalWorkoutsCount = 0;
  int _totalRepsCount = 0;

  // Filters
  ChallengeType? _workoutContextFilter;
  AccessAttemptState? _attemptStateFilter;
  String _searchQuery = '';

  // Persistent search controller — created once, never rebuilt inline.
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);

    _searchQuery = widget.highlightSessionId ?? '';
    _searchController = TextEditingController(text: _searchQuery);

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHistoryData());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadHistoryData();
    }
  }

  Future<void> _loadHistoryData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final controller = DevLabScope.of(context);
    try {
      final workouts = await controller.workoutHistoryRepository.getRecentWorkouts(limit: 50);
      final attempts = await controller.accessAttemptRepository.getRecentAttempts(limit: 50);
      final count = await controller.workoutHistoryRepository.countCompletedWorkouts();
      final totalReps = await controller.workoutHistoryRepository.getTotalVerifiedRepetitions();

      if (mounted) {
        setState(() {
          _allWorkouts = workouts;
          _allAttempts = attempts;
          _totalWorkoutsCount = count;
          _totalRepsCount = totalReps;
          _loadError = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
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

  String _formatDateTime(DateTime dt) {
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
    final isReal = controller.executionMode == DevExecutionMode.realDevice;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History & Local Database'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: DevLabTheme.accent,
          labelColor: DevLabTheme.accent,
          unselectedLabelColor: DevLabTheme.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.fitness_center_rounded, size: 18),
              text: 'Workouts ($_totalWorkoutsCount)',
            ),
            Tab(
              icon: const Icon(Icons.lock_clock_rounded, size: 18),
              text: 'Access Attempts (${_allAttempts.length})',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload database tables',
            onPressed: _loadHistoryData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Database Isolation Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: DevLabTheme.surfaceElevated,
            child: Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 16,
                  color: isReal ? DevLabTheme.statusSuccess : DevLabTheme.statusInfo,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isReal
                        ? 'Target Database: Real Device (levelup.db)'
                        : 'Target Database: Isolated QA Simulation (levelup_simulation.db)',
                    style: TextStyle(
                      color: isReal ? DevLabTheme.statusSuccess : DevLabTheme.statusInfo,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: DevLabTheme.background,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$_totalRepsCount total reps',
                    style: const TextStyle(
                      color: DevLabTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search bar (if active or typed)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              decoration: InputDecoration(
                hintText: 'Filter by session ID, package or challenge...',
                prefixIcon: const Icon(Icons.search, size: 18, color: DevLabTheme.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13, color: DevLabTheme.textPrimary),
            ),
          ),

          if (_loadError != null) ...[
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DevLabTheme.statusError.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DevLabTheme.statusError),
              ),
              child: Text(
                'Database load error: $_loadError',
                style: const TextStyle(color: DevLabTheme.statusError, fontSize: 12),
              ),
            ),
          ],

          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Workouts List
                      _buildWorkoutsTab(),
                      // Tab 2: Access Attempts List
                      _buildAccessAttemptsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutsTab() {
    var filtered = _allWorkouts;
    if (_workoutContextFilter != null) {
      filtered = filtered.where((w) => w.challengeContext == _workoutContextFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((w) =>
              w.sessionId.toLowerCase().contains(q) ||
              w.challengeId.toLowerCase().contains(q) ||
              (w.targetPackage?.toLowerCase().contains(q) ?? false))
          .toList();
    }

    return Column(
      children: [
        // Filter Chips Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Workouts'),
                selected: _workoutContextFilter == null,
                onSelected: (_) => setState(() => _workoutContextFilter = null),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.accent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _workoutContextFilter == null
                      ? DevLabTheme.accent
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Unlock Challenges'),
                selected: _workoutContextFilter == ChallengeType.unlockChallenge,
                onSelected: (_) => setState(
                  () => _workoutContextFilter = ChallengeType.unlockChallenge,
                ),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.accent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _workoutContextFilter == ChallengeType.unlockChallenge
                      ? DevLabTheme.accent
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Free Workouts'),
                selected: _workoutContextFilter == ChallengeType.freeWorkout,
                onSelected: (_) => setState(
                  () => _workoutContextFilter = ChallengeType.freeWorkout,
                ),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.accent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _workoutContextFilter == ChallengeType.freeWorkout
                      ? DevLabTheme.accent
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyView(
                  icon: Icons.fitness_center_outlined,
                  message: 'No completed workouts found in SQLite table.',
                )
              : RefreshIndicator(
                  onRefresh: _loadHistoryData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildWorkoutCard(item);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWorkoutCard(WorkoutResult workout) {
    final isUnlock = workout.challengeContext == ChallengeType.unlockChallenge;
    final isHighlighted = widget.highlightSessionId == workout.sessionId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isHighlighted ? DevLabTheme.accent : DevLabTheme.border,
          width: isHighlighted ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    workout.sessionId,
                    style: const TextStyle(
                      color: DevLabTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14, color: DevLabTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _copyToClipboard(workout.sessionId, 'Session ID'),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isUnlock
                        ? DevLabTheme.accent.withValues(alpha: 0.15)
                        : DevLabTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isUnlock ? 'UNLOCK' : 'FREE',
                    style: TextStyle(
                      color: isUnlock ? DevLabTheme.accent : DevLabTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _dataItem('Exercise', workout.exerciseType.name.toUpperCase()),
                _dataItem('Verified Reps', '${workout.completedRepetitions} reps',
                    valueColor: DevLabTheme.statusSuccess),
                _dataItem('Duration', _formatDuration(workout.duration)),
                _dataItem('Origin', workout.source),
              ],
            ),
            const SizedBox(height: 8),
            if (workout.targetPackage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Target: ${workout.targetPackage}',
                  style: const TextStyle(color: DevLabTheme.accent, fontSize: 11),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDateTime(workout.completedAt),
                  style: const TextStyle(color: DevLabTheme.textMuted, fontSize: 11),
                ),
                Row(
                  children: [
                    if (isUnlock)
                      TextButton.icon(
                        icon: const Icon(Icons.vpn_key_outlined, size: 14),
                        label: const Text('Attempt', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: DevLabTheme.textSecondary,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          _tabController.animateTo(1);
                          _searchController.text = workout.sessionId;
                          setState(() => _searchQuery = workout.sessionId);
                        },
                      ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: DevLabTheme.surfaceElevated,
                        foregroundColor: DevLabTheme.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WorkoutResultScreen(
                              sessionId: workout.sessionId,
                              initialResult: workout,
                            ),
                          ),
                        );
                      },
                      child: const Text('Inspect Result'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessAttemptsTab() {
    var filtered = _allAttempts;
    if (_attemptStateFilter != null) {
      filtered = filtered.where((a) => a.state == _attemptStateFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((a) =>
              a.sessionId.toLowerCase().contains(q) ||
              a.targetPackage.toLowerCase().contains(q) ||
              a.state.name.toLowerCase().contains(q))
          .toList();
    }

    return Column(
      children: [
        // Filter Chips Bar
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Attempts'),
                selected: _attemptStateFilter == null,
                onSelected: (_) => setState(() => _attemptStateFilter = null),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.accent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _attemptStateFilter == null
                      ? DevLabTheme.accent
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Confirmed'),
                selected: _attemptStateFilter == AccessAttemptState.confirmed,
                onSelected: (_) =>
                    setState(() => _attemptStateFilter = AccessAttemptState.confirmed),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.statusSuccess.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _attemptStateFilter == AccessAttemptState.confirmed
                      ? DevLabTheme.statusSuccess
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Uncertain'),
                selected: _attemptStateFilter == AccessAttemptState.uncertain,
                onSelected: (_) =>
                    setState(() => _attemptStateFilter = AccessAttemptState.uncertain),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.statusWarning.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _attemptStateFilter == AccessAttemptState.uncertain
                      ? DevLabTheme.statusWarning
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Rejected'),
                selected: _attemptStateFilter == AccessAttemptState.definitivelyRejected,
                onSelected: (_) =>
                    setState(() => _attemptStateFilter = AccessAttemptState.definitivelyRejected),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.statusError.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _attemptStateFilter == AccessAttemptState.definitivelyRejected
                      ? DevLabTheme.statusError
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Prepared'),
                selected: _attemptStateFilter == AccessAttemptState.prepared,
                onSelected: (_) =>
                    setState(() => _attemptStateFilter = AccessAttemptState.prepared),
                backgroundColor: DevLabTheme.surface,
                selectedColor: DevLabTheme.statusNeutral.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _attemptStateFilter == AccessAttemptState.prepared
                      ? DevLabTheme.textPrimary
                      : DevLabTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyView(
                  icon: Icons.lock_clock_outlined,
                  message: 'No access attempt records found in SQLite table.',
                )
              : RefreshIndicator(
                  onRefresh: _loadHistoryData,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildAttemptCard(item);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAttemptCard(AccessAttemptRecord attempt) {
    Color stateColor;
    switch (attempt.state) {
      case AccessAttemptState.confirmed:
        stateColor = DevLabTheme.statusSuccess;
        break;
      case AccessAttemptState.uncertain:
        stateColor = DevLabTheme.statusWarning;
        break;
      case AccessAttemptState.definitivelyRejected:
        stateColor = DevLabTheme.statusError;
        break;
      case AccessAttemptState.prepared:
        stateColor = DevLabTheme.statusNeutral;
        break;
    }

    final isCurrentlyActive = attempt.unlockUntil != null &&
        attempt.unlockUntil!.isAfter(DateTime.now());

    final isHighlighted = widget.highlightSessionId == attempt.sessionId;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isHighlighted ? DevLabTheme.accent : DevLabTheme.border,
          width: isHighlighted ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    attempt.sessionId,
                    style: const TextStyle(
                      color: DevLabTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 14, color: DevLabTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _copyToClipboard(attempt.sessionId, 'Session ID'),
                ),
                const SizedBox(width: 8),
                StatusBadge(
                  label: attempt.state.name.toUpperCase(),
                  color: stateColor,
                ),
              ],
            ),
            const Divider(height: 16),
            _dataRow('Target Package', attempt.targetPackage),
            _dataRow('Requested Duration', '${attempt.durationSeconds}s (${attempt.durationSeconds ~/ 60}m)'),
            _dataRow('Attempted At', _formatDateTime(attempt.attemptedAt)),
            if (attempt.confirmedAt != null)
              _dataRow('Confirmed At', _formatDateTime(attempt.confirmedAt!)),
            if (attempt.unlockUntil != null) ...[
              _dataRow(
                'unlockUntil',
                _formatDateTime(attempt.unlockUntil!),
                valueColor: isCurrentlyActive ? DevLabTheme.statusSuccess : DevLabTheme.statusWarning,
              ),
              _dataRow(
                'Live Access State',
                isCurrentlyActive ? 'ACTIVE (Unlocked)' : 'EXPIRED (Historically Confirmed)',
                valueColor: isCurrentlyActive ? DevLabTheme.statusSuccess : DevLabTheme.statusWarning,
              ),
            ],
            if (attempt.failureReason != null) ...[
              const SizedBox(height: 4),
              _dataRow(
                'Failure Reason',
                attempt.failureReason!,
                valueColor: DevLabTheme.statusError,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.fitness_center_outlined, size: 14),
                  label: const Text('Workout', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: DevLabTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    _tabController.animateTo(0);
                    _searchController.text = attempt.sessionId;
                    setState(() => _searchQuery = attempt.sessionId);
                  },
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: DevLabTheme.surfaceElevated,
                    foregroundColor: DevLabTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkoutResultScreen(sessionId: attempt.sessionId),
                      ),
                    );
                  },
                  child: const Text('Inspect Result'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: DevLabTheme.textMuted),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _dataItem(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? DevLabTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _dataRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 12),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? DevLabTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
