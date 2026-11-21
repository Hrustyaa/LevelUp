import 'dart:async';

import '../../../core/constants/channel_constants.dart';
import '../../../core/errors/focus_exceptions.dart';
import '../../../core/errors/native_bridge_exception.dart';
import '../../../models/focus_state.dart';
import '../../../models/native_permission_status.dart';
import '../../../services/native_bridge.dart';

export '../../../core/errors/focus_exceptions.dart';
export '../../../models/focus_state.dart';

/// Application-level interface for controlling the voluntary Focus restriction gate.
abstract class IFocusService {
  /// The latest cached state snapshot, or null if [refreshState] has not been called yet.
  FocusState? get currentState;

  /// Broadcast stream of [FocusState] changes.
  Stream<FocusState> get stateStream;

  /// Fetches the authoritative live focus status from the Android native layer.
  Future<FocusState> getFocusStatus();

  /// Voluntarily activates the Focus restriction for the currently selected target.
  ///
  /// Throws [AccessibilityPermissionRequiredException] if Android Accessibility permission
  /// has not been granted.
  /// Throws [NativeBridgeUnavailableException] if the native bridge cannot be reached.
  /// Throws [FocusStateSyncException] if state confirmation fails.
  Future<FocusState> enableFocus();

  /// Voluntarily deactivates the Focus restriction.
  ///
  /// Safe exit is always guaranteed: deactivation succeeds regardless of permission status.
  /// Throws [NativeBridgeUnavailableException] if the native bridge cannot be reached.
  /// Throws [FocusStateSyncException] if state confirmation fails.
  Future<FocusState> disableFocus();

  /// Updates the single application targeted for restriction.
  ///
  /// Must be one of the supported targets: YouTube, Instagram, or TikTok.
  /// SIDE EFFECT: Selecting a new target immediately revokes any active temporary access unlock.
  ///
  /// Throws [UnsupportedTargetException] if [packageName] is not in [ChannelConstants.allowedTargets].
  /// Throws [NativeBridgeUnavailableException] if the native bridge cannot be reached.
  Future<FocusState> selectTargetApp(String packageName);

  /// Returns the package identifier of the currently selected target app.
  Future<String> getSelectedTarget();

  /// Returns the current Android Accessibility permission status.
  Future<NativePermissionStatus> getPermissionStatus();

  /// Opens the Android system Accessibility Settings screen so the user can grant permission.
  Future<bool> openAccessibilitySettings();

  /// Queries the native layer and updates the cached [currentState] and [stateStream].
  Future<FocusState> refreshState();

  /// Disposes resources held by the service (e.g. stream controllers).
  void dispose();
}

/// Production implementation of [IFocusService] communicating via [INativeBridge].
class FocusService implements IFocusService {
  final INativeBridge _bridge;
  final StreamController<FocusState> _stateController =
      StreamController<FocusState>.broadcast();
  FocusState? _currentState;

  /// Creates a [FocusService].
  ///
  /// Does NOT trigger any implicit native activation or channel communication on instantiation.
  FocusService({
    INativeBridge? bridge,
  }) : _bridge = bridge ?? const NativeBridge();

  @override
  FocusState? get currentState => _currentState;

  @override
  Stream<FocusState> get stateStream => _stateController.stream;

  @override
  Future<FocusState> getFocusStatus() async {
    return refreshState();
  }

  @override
  Future<FocusState> enableFocus() async {
    await _ensureBridgeAvailable();

    // Verify accessibility permission is granted before enabling restriction.
    final currentNative = await _bridge.getState();
    if (!currentNative.isAccessibilityGranted) {
      throw const AccessibilityPermissionRequiredException();
    }

    try {
      await _bridge.setEnabled(true);
    } on NativeBridgeException catch (e) {
      throw FocusStateSyncException(
        message: 'Bridge error enabling Focus: ${e.message}',
        cause: e,
      );
    }

    final refreshed = await refreshState();
    if (!refreshed.isUserEnabled) {
      throw const FocusStateSyncException(
        message: 'Confirmed native state did not reflect Focus enabled.',
      );
    }

    return refreshed;
  }

  @override
  Future<FocusState> disableFocus() async {
    await _ensureBridgeAvailable();

    try {
      await _bridge.setEnabled(false);
    } on NativeBridgeException catch (e) {
      throw FocusStateSyncException(
        message: 'Bridge error disabling Focus: ${e.message}',
        cause: e,
      );
    }

    final refreshed = await refreshState();
    if (refreshed.isUserEnabled) {
      throw const FocusStateSyncException(
        message: 'Confirmed native state did not reflect Focus disabled.',
      );
    }

    return refreshed;
  }

  @override
  Future<FocusState> selectTargetApp(String packageName) async {
    if (!ChannelConstants.allowedTargets.contains(packageName)) {
      throw UnsupportedTargetException(packageName);
    }

    await _ensureBridgeAvailable();

    try {
      await _bridge.setTarget(packageName);
    } on UnsupportedTargetPackageException catch (e) {
      throw UnsupportedTargetException.fromBridge(e);
    } on NativeBridgeException catch (e) {
      throw FocusStateSyncException(
        message: 'Failed to update target package on native layer: ${e.message}',
        cause: e,
      );
    }

    final refreshed = await refreshState();
    if (refreshed.selectedTarget != packageName) {
      throw FocusStateSyncException(
        message:
            'Target mismatch: expected "$packageName" but confirmed "${refreshed.selectedTarget}".',
      );
    }

    return refreshed;
  }

  @override
  Future<String> getSelectedTarget() async {
    final status = await getFocusStatus();
    return status.selectedTarget;
  }

  @override
  Future<NativePermissionStatus> getPermissionStatus() async {
    final status = await getFocusStatus();
    return NativePermissionStatus(
      isAccessibilityGranted: status.isAccessibilityGranted,
    );
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    await _ensureBridgeAvailable();
    try {
      return await _bridge.openAccessibilitySettings();
    } on NativeBridgeException catch (e) {
      throw FocusStateSyncException(
        message: 'Failed to dispatch accessibility settings intent: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  Future<FocusState> refreshState() async {
    try {
      final isAvailable = await _bridge.isAvailable();
      if (!isAvailable) {
        final fallback = FocusState.unavailable(
          selectedTarget:
              _currentState?.selectedTarget ?? ChannelConstants.defaultTarget,
        );
        _updateState(fallback);
        return fallback;
      }

      final nativeStatus = await _bridge.getState();
      final state = FocusState.fromNative(
        nativeStatus: nativeStatus,
        isBridgeAvailable: true,
      );
      _updateState(state);
      return state;
    } on FocusEngineException {
      rethrow;
    } catch (e) {
      throw FocusStateSyncException(
        message: 'Failed to refresh native focus state: $e',
        cause: e,
      );
    }
  }

  @override
  void dispose() {
    _stateController.close();
  }

  Future<void> _ensureBridgeAvailable() async {
    final available = await _bridge.isAvailable();
    if (!available) {
      throw const NativeBridgeUnavailableException();
    }
  }

  void _updateState(FocusState newState) {
    _currentState = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }
}
