import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/constants/channel_constants.dart';
import '../../../core/errors/focus_exceptions.dart';
import '../di/dev_lab_scope.dart';
import '../models/diagnostic_event.dart';
import '../theme/dev_lab_theme.dart';
import '../widgets/diagnostic_card.dart';
import '../widgets/live_event_log_view.dart';
import '../widgets/status_badge.dart';

/// Screen 2 — Preflight & Focus Configuration.
///
/// Verifies hardware/permission prerequisites (Camera, Accessibility) and
/// controls voluntary focus gating and single-target restriction parameters.
class PreflightFocusScreen extends StatefulWidget {
  const PreflightFocusScreen({super.key});

  @override
  State<PreflightFocusScreen> createState() => _PreflightFocusScreenState();
}

class _PreflightFocusScreenState extends State<PreflightFocusScreen>
    with WidgetsBindingObserver {
  bool _isCheckingCamera = false;
  int _cameraCount = 0;
  bool _frontCameraAvailable = false;
  String? _cameraErrorMessage;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = DevLabScope.of(context);
      if (controller.isInitializing) {
        controller.refreshAll();
      }
      _checkCameraHardware();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final controller = DevLabScope.of(context);
      controller.refreshAll();
      _checkCameraHardware();
    }
  }

  Future<void> _checkCameraHardware() async {
    if (!mounted) return;
    setState(() {
      _isCheckingCamera = true;
      _cameraErrorMessage = null;
    });

    try {
      final cameras = await availableCameras().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => <CameraDescription>[],
      );
      if (!mounted) return;

      final hasFront = cameras.any(
        (cam) => cam.lensDirection == CameraLensDirection.front,
      );

      setState(() {
        _cameraCount = cameras.length;
        _frontCameraAvailable = hasFront;
        _isCheckingCamera = false;
      });

      final controller = DevLabScope.of(context);
      controller.logService.info(
        BackendModuleId.poseEngine,
        'Camera preflight check: $cameras found. Front lens: ${hasFront ? "Available" : "Missing"}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingCamera = false;
        _cameraErrorMessage = e.toString();
        _cameraCount = 0;
        _frontCameraAvailable = false;
      });

      final controller = DevLabScope.of(context);
      controller.logService.error(
        BackendModuleId.poseEngine,
        'Camera preflight check error: $e',
      );
    }
  }

  Future<void> _toggleFocus(bool enable) async {
    final controller = DevLabScope.of(context);
    setState(() => _isActionInProgress = true);

    try {
      if (enable) {
        await controller.focusService.enableFocus();
        await controller.refreshAll();
        controller.logService.success(
          BackendModuleId.focusEngine,
          'Focus restriction voluntarily ENABLED for target ${controller.currentFocusState?.targetDisplayName}',
        );
      } else {
        await controller.focusService.disableFocus();
        await controller.refreshAll();
        controller.logService.info(
          BackendModuleId.focusEngine,
          'Focus restriction voluntarily DISABLED',
        );
      }
    } on AccessibilityPermissionRequiredException {
      controller.logService.warning(
        BackendModuleId.focusEngine,
        'Cannot enable Focus: Accessibility permission missing.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Accessibility permission required before enabling restriction.',
            ),
            backgroundColor: DevLabTheme.statusWarning,
          ),
        );
      }
    } catch (e) {
      controller.logService.error(
        BackendModuleId.focusEngine,
        'Focus toggle failed: $e',
      );
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _selectTarget(String targetPackage) async {
    final controller = DevLabScope.of(context);
    setState(() => _isActionInProgress = true);

    try {
      await controller.focusService.selectTargetApp(targetPackage);
      await controller.refreshAll();
      controller.logService.info(
        BackendModuleId.focusEngine,
        'Target changed to $targetPackage (temporary access reset)',
      );
    } catch (e) {
      controller.logService.error(
        BackendModuleId.focusEngine,
        'Failed to set target package: $e',
      );
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _openAccessibilitySettings() async {
    final controller = DevLabScope.of(context);
    try {
      controller.logService.info(
        BackendModuleId.focusEngine,
        'Requesting Android Accessibility Settings...',
      );
      await controller.focusService.openAccessibilitySettings();
    } catch (e) {
      controller.logService.error(
        BackendModuleId.focusEngine,
        'Failed to open settings: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = DevLabScope.of(context);
    final focus = controller.currentFocusState;
    final isAccessibilityGranted = focus?.isAccessibilityGranted ?? false;
    final isFocusEnabled = focus?.isUserEnabled ?? false;
    final currentTarget = focus?.selectedTarget ?? ChannelConstants.defaultTarget;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PREFLIGHT & FOCUS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh state & preflight',
            onPressed: () {
              controller.refreshAll();
              _checkCameraHardware();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Hardware & System Prerequisites
            DiagnosticCard(
              title: 'Hardware & OS Prerequisites',
              subtitle: 'Camera hardware and Android Accessibility Service readiness',
              icon: Icons.checklist_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Camera Preflight Row
                  _checklistRow(
                    title: 'Front Camera (NV21 / YUV)',
                    subtitle: _isCheckingCamera
                        ? 'Checking camera sensors...'
                        : _cameraErrorMessage != null
                            ? 'Error: $_cameraErrorMessage'
                            : '$_cameraCount camera(s) detected. Front lens: ${_frontCameraAvailable ? "Ready" : "Not Found"}',
                    badge: _isCheckingCamera
                        ? const StatusBadge(label: 'Checking', color: DevLabTheme.statusNeutral)
                        : _frontCameraAvailable
                            ? const StatusBadge(label: 'Ready', color: DevLabTheme.statusSuccess)
                            : const StatusBadge(label: 'Unavailable', color: DevLabTheme.statusError),
                    trailingAction: TextButton.icon(
                      icon: const Icon(Icons.sync, size: 14),
                      label: const Text('Probe'),
                      onPressed: _isCheckingCamera ? null : _checkCameraHardware,
                    ),
                  ),
                  const Divider(color: DevLabTheme.surfaceElevated, height: 20),

                  // Accessibility Permission Row
                  _checklistRow(
                    title: 'Android Accessibility Service',
                    subtitle: isAccessibilityGranted
                        ? 'Granted in OS Settings (LevelUpAccessibilityService active)'
                        : 'Missing permission. Required for Android Blocker v3 target gating',
                    badge: isAccessibilityGranted
                        ? const StatusBadge(label: 'Granted', color: DevLabTheme.statusSuccess)
                        : const StatusBadge(label: 'Missing', color: DevLabTheme.statusWarning),
                    trailingAction: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Open Settings'),
                      onPressed: _openAccessibilitySettings,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 2. Voluntary Focus Gating Control
            DiagnosticCard(
              title: 'Voluntary Focus Gating',
              subtitle: 'User-controlled application restriction gate',
              icon: Icons.lock_clock_outlined,
              badge: StatusBadge(
                label: isFocusEnabled ? 'Active (Gated)' : 'Inactive',
                color: isFocusEnabled ? DevLabTheme.statusSuccess : DevLabTheme.statusNeutral,
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Enable Focus Restriction',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: DevLabTheme.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      isFocusEnabled
                          ? 'Target application (${focus?.targetDisplayName}) is gated.'
                          : 'Target application is currently unrestricted.',
                      style: const TextStyle(color: DevLabTheme.textSecondary, fontSize: 12),
                    ),
                    value: isFocusEnabled,
                    activeThumbColor: DevLabTheme.accent,
                    onChanged: _isActionInProgress
                        ? null
                        : (val) => _toggleFocus(val),
                  ),
                  if (!isAccessibilityGranted && !isFocusEnabled)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DevLabTheme.statusWarning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: DevLabTheme.statusWarning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 18, color: DevLabTheme.statusWarning),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Enabling focus requires Android Accessibility permission. Grant permission first.',
                              style: TextStyle(
                                color: DevLabTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 3. Single-Target Restriction Selection
            DiagnosticCard(
              title: 'Restricted Target Application',
              subtitle: 'Select one application to restrict with Android Blocker v3',
              icon: Icons.apps_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _targetOption(
                    title: 'YouTube',
                    package: ChannelConstants.targetYouTube,
                    currentSelected: currentTarget,
                    icon: Icons.play_circle_fill_rounded,
                  ),
                  _targetOption(
                    title: 'Instagram',
                    package: ChannelConstants.targetInstagram,
                    currentSelected: currentTarget,
                    icon: Icons.camera_alt_rounded,
                  ),
                  _targetOption(
                    title: 'TikTok',
                    package: ChannelConstants.targetTikTok,
                    currentSelected: currentTarget,
                    icon: Icons.music_note_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Architectural Disclaimer Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DevLabTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DevLabTheme.textMuted.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: DevLabTheme.accent,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Single-Target Restriction Contract',
                                style: TextStyle(
                                  color: DevLabTheme.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Android Blocker v3 enforces restriction on exactly ONE selected package at a time. Switching targets immediately updates the active blocker target and clears any active temporary access unlock.',
                                style: TextStyle(
                                  color: DevLabTheme.textSecondary,
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Live Diagnostics Log
            LiveEventLogView(
              logService: controller.logService,
              initialExpanded: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklistRow({
    required String title,
    required String subtitle,
    required Widget badge,
    Widget? trailingAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: DevLabTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  badge,
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: DevLabTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (trailingAction != null) ...[
          const SizedBox(width: 8),
          trailingAction,
        ],
      ],
    );
  }

  Widget _targetOption({
    required String title,
    required String package,
    required String currentSelected,
    required IconData icon,
  }) {
    final isSelected = package == currentSelected;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSelected
            ? DevLabTheme.accent.withValues(alpha: 0.08)
            : DevLabTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? DevLabTheme.accent : DevLabTheme.surfaceElevated,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onTap: _isActionInProgress ? null : () => _selectTarget(package),
          leading: Icon(
            icon,
            size: 20,
            color: isSelected ? DevLabTheme.accent : DevLabTheme.textSecondary,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? DevLabTheme.accent : DevLabTheme.textPrimary,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            package,
            style: const TextStyle(color: DevLabTheme.textMuted, fontSize: 11),
          ),
          trailing: Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isSelected ? DevLabTheme.accent : DevLabTheme.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}
