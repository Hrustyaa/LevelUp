import 'dart:async';

import '../../core/constants/channel_constants.dart';
import '../../data/dashboard_data.dart';
import '../../features/focus/application/focus_service.dart';

/// Production adapter implementing [DashboardFocusGateway] backed by [IFocusService].
///
/// Enforces all native gate invariants:
/// - Explicit user action before enabling Focus.
/// - Mandatory verified Android Accessibility permission before enabling.
/// - Exactly one supported target package from [ChannelConstants.allowedTargets].
/// - Authoritative state synchronization directly from Kotlin SharedPreferences.
/// - Anti-racing lock protecting concurrent enable/disable calls.
/// - Calendar-time preservation of active [unlockUntil] timestamps.
class CoreFocusGatewayAdapter implements DashboardFocusGateway {
  final IFocusService _focusService;

  bool _isOperationInProgress = false;

  CoreFocusGatewayAdapter({
    required IFocusService focusService,
  })  : _focusService = focusService;

  @override
  Future<FocusSnapshot> read() async {
    final state = await _focusService.refreshState();
    final target = state.selectedTarget;
    final targets = target.isNotEmpty ? [target] : <String>[];

    return FocusSnapshot(
      enabled: state.isUserEnabled,
      serviceEnabled: state.isAccessibilityGranted,
      targets: targets,
      accessUntil: {
        if (state.isAccessActive && state.unlockUntil != null && target.isNotEmpty)
          target: state.unlockUntil!,
      },
    );
  }

  @override
  Future<void> enable({String? target}) async {
    if (_isOperationInProgress) {
      throw const FocusStateSyncException(
        message: 'A focus state change is already in progress.',
      );
    }
    _isOperationInProgress = true;

    try {
      if (target != null && target.isNotEmpty) {
        if (!ChannelConstants.allowedTargets.contains(target)) {
          throw UnsupportedTargetException(target);
        }
        await _focusService.selectTargetApp(target);
      }

      // Precondition check and authoritative activation:
      // FocusService.enableFocus() authoritatively checks Accessibility permission
      // and throws AccessibilityPermissionRequiredException if permission is missing.
      await _focusService.enableFocus();
    } finally {
      _isOperationInProgress = false;
    }
  }

  @override
  Future<void> disable() async {
    if (_isOperationInProgress) {
      throw const FocusStateSyncException(
        message: 'A focus state change is already in progress.',
      );
    }
    _isOperationInProgress = true;

    try {
      await _focusService.disableFocus();
    } finally {
      _isOperationInProgress = false;
    }
  }
}
