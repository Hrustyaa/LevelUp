import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../core/errors/challenge_exceptions.dart';
import '../../../models/workout_session_status.dart';
import '../di/dev_lab_scope.dart';
import '../models/dev_mode.dart';
import '../models/diagnostic_event.dart';
import '../models/module_status.dart';
import '../theme/dev_lab_theme.dart';
import '../widgets/diagnostic_card.dart';
import '../widgets/live_event_log_view.dart';
import '../widgets/status_badge.dart';
import 'history_database_screen.dart';
import 'live_challenge_screen.dart';
import 'preflight_focus_screen.dart';
import 'test_center_screen.dart';
import 'workout_result_screen.dart';

/// Screen 1 — Developer Lab System Hub: Full real-mode health & state inspection.
class SystemHubScreen extends StatefulWidget {
  const SystemHubScreen({super.key});

  @override
  State<SystemHubScreen> createState() => _SystemHubScreenState();
}

class _SystemHubScreenState extends State<SystemHubScreen> with WidgetsBindingObserver {
  bool _isLaunchingUnlock = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = DevLabScope.of(context);
      if (controller.isInitializing) {
        controller.refreshAll();
      }
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final controller = DevLabScope.of(context);
      final focus = controller.currentFocusState;
      if (focus != null && focus.unlockUntil != null) {
        final remainingMs = focus.unlockUntil!.difference(DateTime.now()).inMilliseconds;
        // Trigger authoritative native refresh the moment access expires
        if (remainingMs <= 0 && focus.isAccessActive) {
          controller.refreshAll();
        } else {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final controller = DevLabScope.of(context);
      controller.refreshAll();
    }
  }

  String _formatAccessStatus(dynamic focus) {
    if (focus == null) return 'Unknown';
    final unlockUntil = focus.unlockUntil as DateTime?;
    if (unlockUntil == null) {
      return focus.isUserEnabled == true ? 'RESTRICTED (No grant)' : 'INACTIVE (Focus off)';
    }

    final now = DateTime.now();
    final remainingMs = math.max(0, unlockUntil.difference(now).inMilliseconds);
    final isCurrentlyActive = remainingMs > 0;

    if (isCurrentlyActive) {
      final totalSeconds = (remainingMs / 1000).ceil();
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      final formatted =
          '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      return 'UNLOCKED ($formatted remaining)';
    } else {
      return 'RESTRICTED / EXPIRED';
    }
  }

  Future<void> _checkAndLaunchUnlock() async {
    final controller = DevLabScope.of(context);
    setState(() => _isLaunchingUnlock = true);

    try {
      await controller.coordinator.launchUnlockChallenge(
        requirePendingRequest: !controller.executionMode.isSimulation,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const LiveChallengeScreen(
            isUnlockFromNative: true,
          ),
        ),
      );
    } on InvalidChallengeRequestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pending challenge request from Android Blocker overlay. Open a restricted app to trigger the blocker first.',
          ),
          backgroundColor: DevLabTheme.statusWarning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot launch unlock challenge: $e'),
          backgroundColor: DevLabTheme.statusError,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLaunchingUnlock = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = DevLabScope.of(context);
    final focus = controller.currentFocusState;
    final coordState = controller.coordinator.currentState;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SYSTEM HUB'),
        actions: [
          // Mode Toggle (Real Device vs Simulation)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: ActionChip(
              avatar: Icon(
                controller.executionMode.isReal
                    ? Icons.smartphone_rounded
                    : Icons.science_outlined,
                size: 14,
                color: controller.executionMode.isReal
                    ? DevLabTheme.accent
                    : DevLabTheme.statusSpecial,
              ),
              label: Text(
                controller.executionMode.label,
                style: TextStyle(
                  color: controller.executionMode.isReal
                      ? DevLabTheme.accent
                      : DevLabTheme.statusSpecial,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              backgroundColor: DevLabTheme.surfaceElevated,
              side: BorderSide(
                color: controller.executionMode.isReal
                    ? DevLabTheme.accent.withValues(alpha: 0.4)
                    : DevLabTheme.statusSpecial.withValues(alpha: 0.4),
              ),
              onPressed: () {
                final nextMode = controller.executionMode == DevExecutionMode.realDevice
                    ? DevExecutionMode.simulation
                    : DevExecutionMode.realDevice;
                controller.switchMode(nextMode);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh all module health',
            onPressed: controller.refreshAll,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Authoritative Blocker Overlay Trigger
            DiagnosticCard(
              title: 'Blocker Overlay Challenge',
              subtitle: 'Check Android Blocker v3 and launch unlock challenge',
              icon: Icons.flash_on_rounded,
              trailing: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Check & Launch'),
                onPressed: _isLaunchingUnlock ? null : _checkAndLaunchUnlock,
              ),
              child: Text(
                controller.executionMode.isReal
                    ? 'Tapping "Check & Launch" authoritatively consumes the pending challenge request flag from Android Blocker v3. If you tapped "Start challenge" on the blocker overlay, it starts the unlock challenge.'
                    : 'Simulation Mode: Tapping "Check & Launch" initiates an unlock challenge session against the simulation bridge without querying the Android OS.',
                style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 12),
              ),
            ),

            const SizedBox(height: 10),

            // Live State Snapshot Card
            DiagnosticCard(
              title: 'Live System Snapshot',
              subtitle: 'Current operational parameters from native layer & coordinator',
              icon: Icons.dashboard_outlined,
              badge: StatusBadge(
                label: controller.isInitializing ? 'Refreshing' : 'Active',
                color: controller.isInitializing
                    ? DevLabTheme.statusWarning
                    : DevLabTheme.statusSuccess,
              ),
              child: Column(
                children: [
                  _infoRow(
                    'Voluntary Focus Mode',
                    focus == null
                        ? 'Unknown'
                        : (focus.isUserEnabled ? 'ENABLED' : 'DISABLED'),
                    focus?.isUserEnabled == true
                        ? DevLabTheme.statusSuccess
                        : DevLabTheme.statusNeutral,
                  ),
                  _infoRow(
                    'Accessibility Permission',
                    focus == null
                        ? 'Unknown'
                        : (focus.isAccessibilityGranted ? 'GRANTED' : 'MISSING'),
                    focus?.isAccessibilityGranted == true
                        ? DevLabTheme.statusSuccess
                        : DevLabTheme.statusWarning,
                  ),
                  _infoRow(
                    'Selected Restricted App',
                    focus?.targetDisplayName ?? 'com.google.android.youtube',
                    DevLabTheme.textPrimary,
                  ),
                  _infoRow(
                    'Temporary Access Unlock',
                    _formatAccessStatus(focus),
                    focus?.unlockUntil != null &&
                            focus!.unlockUntil!.difference(DateTime.now()).inMilliseconds > 0
                        ? DevLabTheme.statusSuccess
                        : DevLabTheme.statusNeutral,
                  ),
                  _infoRow(
                    'Active Workout Session',
                    coordState.sessionId == null
                        ? 'None (Ready)'
                        : '${coordState.sessionId} (${coordState.sessionStatus.name})',
                    coordState.sessionStatus == WorkoutSessionStatus.active
                        ? DevLabTheme.accent
                        : DevLabTheme.textSecondary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // 7 Backend Modules + Coordinator Status Matrix
            DiagnosticCard(
              title: 'Module Integrity Matrix',
              subtitle: 'Factual operational status of all seven backend engines',
              icon: Icons.hub_outlined,
              child: Column(
                children: [
                  _moduleHealthRow(
                    '01 Native Bridge',
                    controller.moduleHealth[BackendModuleId.nativeBridge]!,
                    'MainActivity.kt MethodChannel',
                  ),
                  _moduleHealthRow(
                    '02 Focus Engine',
                    controller.moduleHealth[BackendModuleId.focusEngine]!,
                    'FocusService & target gating',
                  ),
                  _moduleHealthRow(
                    '03 Challenge Engine',
                    controller.moduleHealth[BackendModuleId.challengeEngine]!,
                    'ChallengeCatalog definitions',
                  ),
                  _moduleHealthRow(
                    '04 Pose Engine',
                    controller.moduleHealth[BackendModuleId.poseEngine]!,
                    'SquatCounter & SquatGeometry',
                  ),
                  _moduleHealthRow(
                    '05 Session Manager',
                    controller.moduleHealth[BackendModuleId.sessionManager]!,
                    'WorkoutSession lifecycle',
                  ),
                  _moduleHealthRow(
                    '06 Access Engine',
                    controller.moduleHealth[BackendModuleId.accessEngine]!,
                    'AccessService authorization',
                  ),
                  _moduleHealthRow(
                    '07 Local Database',
                    controller.moduleHealth[BackendModuleId.localDatabase]!,
                    'SQLite ACID persistence',
                  ),
                  _moduleHealthRow(
                    '08 Settings & Permissions',
                    controller.moduleHealth[BackendModuleId.settingsEngine]!,
                    'SettingsService & camera/a11y permissions',
                  ),
                  _moduleHealthRow(
                    'Integration Coordinator',
                    controller.moduleHealth[BackendModuleId.coordinator]!,
                    'Phase A Headless Coordinator',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Navigation Actions to Screens 2-6
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings_suggest_outlined, size: 18),
                    label: const Text('Preflight & Focus'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PreflightFocusScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('Live Challenge'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LiveChallengeScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.assignment_outlined, size: 18),
                    label: const Text('Workout Result'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WorkoutResultScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.storage_outlined, size: 18),
                    label: const Text('History & DB'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HistoryDatabaseScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.science_outlined, size: 18, color: DevLabTheme.accent),
                label: const Text('Diagnostics & Test Center', style: TextStyle(color: DevLabTheme.accent)),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TestCenterScreen()),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // Live Diagnostics Log
            LiveEventLogView(
              logService: controller.logService,
              initialExpanded: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, Color valueColor) {
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
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleHealthRow(String title, ModuleHealthStatus status, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DevLabTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(color: DevLabTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          StatusBadge.fromHealth(status),
        ],
      ),
    );
  }
}
