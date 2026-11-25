import 'dart:async';

import '../../../core/constants/channel_constants.dart';
import '../../../models/exercise_type.dart';
import '../../../services/native_bridge.dart';
import '../../focus/application/focus_service.dart';
import '../data/settings_repository.dart';
import '../models/app_settings.dart';
import '../models/permissions_state.dart';
import '../models/settings_state.dart';
import 'camera_permission_checker.dart';

/// Contract for the Settings & Permissions Engine (Module 08).
abstract class ISettingsService {
  /// Latest cached snapshot of settings, permissions, and native synchronization.
  SettingsState get currentState;

  /// Broadcast stream of [SettingsState] transitions.
  Stream<SettingsState> get stateStream;

  /// Initializes the engine, loading persisted settings and querying hardware/OS permissions.
  Future<SettingsState> initialize();

  /// Authoritatively refreshes settings, native Focus state, and hardware permissions.
  Future<SettingsState> refresh();

  /// Updates application-level preferences, validating against domain invariants.
  Future<SettingsState> updateSettings(AppSettings newSettings);

  /// Updates the single application targeted for voluntary restriction.
  /// Delegates directly to [IFocusService.selectTargetApp] to preserve native gate authority.
  Future<SettingsState> setTargetApp(String packageName);

  /// Voluntarily activates or deactivates Focus restriction.
  /// Precondition: Requires verified Accessibility permission when enabling.
  Future<SettingsState> toggleFocus(bool enable);

  /// Dispatches the Android system intent to open Accessibility Settings.
  Future<bool> openAccessibilitySettings();

  /// Dispatches the Android system intent to open App Details Settings (Camera permissions).
  Future<bool> openAppSettings();

  /// Resets user preferences to factory defaults while preserving native gate target.
  Future<SettingsState> resetToDefaults();

  /// Updates the preferred exercise type for Free Workout sessions.
  Future<SettingsState> updatePreferredExercise(ExerciseType type);

  /// Disposes stream controllers and subscriptions.
  void dispose();
}

/// Production implementation of [ISettingsService].
class SettingsService implements ISettingsService {
  final ISettingsRepository _repository;
  final IFocusService _focusService;
  final INativeBridge _nativeBridge;
  final ICameraPermissionChecker _cameraPermissionChecker;
  final DateTime Function() _clock;

  final StreamController<SettingsState> _stateController =
      StreamController<SettingsState>.broadcast();

  SettingsState _currentState;

  SettingsService({
    required ISettingsRepository repository,
    required IFocusService focusService,
    required INativeBridge nativeBridge,
    ICameraPermissionChecker? cameraPermissionChecker,
    DateTime Function()? clock,
  })  : _repository = repository,
        _focusService = focusService,
        _nativeBridge = nativeBridge,
        _cameraPermissionChecker =
            cameraPermissionChecker ?? DefaultCameraPermissionChecker(),
        _clock = clock ?? DateTime.now,
        _currentState = SettingsState.initial();

  @override
  SettingsState get currentState => _currentState;

  @override
  Stream<SettingsState> get stateStream => _stateController.stream;

  @override
  Future<SettingsState> initialize() async {
    _currentState = _currentState.copyWith(isLoading: true, clearError: true);
    _emitState(_currentState);

    try {
      // 1. Load persisted preferences from repository
      final persisted = await _repository.loadSettings();

      // 2. Query authoritative native Focus and Accessibility state
      final focusState = await _focusService.getFocusStatus();

      // 3. Query device camera permission status
      final cameraStatus = await _cameraPermissionChecker.checkCameraPermission();

      final permissions = PermissionsState(
        isAccessibilityGranted: focusState.isAccessibilityGranted,
        cameraStatus: cameraStatus,
        lastChecked: _clock(),
      );

      _currentState = SettingsState(
        settings: persisted,
        permissions: permissions,
        activeTargetPackage: focusState.selectedTarget,
        isFocusEnabled: focusState.isUserEnabled,
        isLoading: false,
        errorMessage: null,
      );

      _emitState(_currentState);
      return _currentState;
    } catch (e) {
      _currentState = _currentState.copyWith(
        isLoading: false,
        errorMessage: 'Failed to initialize Settings Engine: $e',
      );
      _emitState(_currentState);
      return _currentState;
    }
  }

  @override
  Future<SettingsState> refresh() async {
    try {
      // 1. Refresh authoritative Focus state
      final focusState = await _focusService.refreshState();

      // 2. Refresh Camera permission status
      final cameraStatus = await _cameraPermissionChecker.checkCameraPermission();

      final updatedPermissions = PermissionsState(
        isAccessibilityGranted: focusState.isAccessibilityGranted,
        cameraStatus: cameraStatus,
        lastChecked: _clock(),
      );

      _currentState = _currentState.copyWith(
        permissions: updatedPermissions,
        activeTargetPackage: focusState.selectedTarget,
        isFocusEnabled: focusState.isUserEnabled,
        isLoading: false,
        clearError: true,
      );

      _emitState(_currentState);
      return _currentState;
    } catch (e) {
      _currentState = _currentState.copyWith(
        errorMessage: 'Failed to refresh Settings state: $e',
      );
      _emitState(_currentState);
      return _currentState;
    }
  }

  @override
  Future<SettingsState> updateSettings(AppSettings newSettings) async {
    // 1. Validate invariant rules on input
    newSettings.validate();

    // 2. Invariant: User preferences changes must preserve the active native target.
    // Changing the restricted target requires an explicit call to setTargetApp().
    final settingsToPersist = newSettings.copyWith(
      defaultTargetPackage: _currentState.activeTargetPackage,
    );

    // 3. Persist to storage
    await _repository.saveSettings(settingsToPersist);

    _currentState = _currentState.copyWith(
      settings: settingsToPersist,
      clearError: true,
    );

    _emitState(_currentState);
    return _currentState;
  }

  @override
  Future<SettingsState> setTargetApp(String packageName) async {
    if (!ChannelConstants.allowedTargets.contains(packageName)) {
      throw UnsupportedTargetException(packageName);
    }

    // 1. Delegate to FocusService (Android native gate is authoritative)
    final newFocusState = await _focusService.selectTargetApp(packageName);

    // 2. Persist updated preference only after native gate successfully confirms
    final updatedSettings = _currentState.settings.copyWith(
      defaultTargetPackage: newFocusState.selectedTarget,
    );

    try {
      await _repository.saveSettings(updatedSettings);
      _currentState = _currentState.copyWith(
        settings: updatedSettings,
        activeTargetPackage: newFocusState.selectedTarget,
        clearError: true,
      );
    } catch (e) {
      // If persistence fails, native state remains authoritative; report error explicitly
      _currentState = _currentState.copyWith(
        activeTargetPackage: newFocusState.selectedTarget,
        errorMessage:
            'Native target updated to "$packageName", but failed to persist preference: $e',
      );
      _emitState(_currentState);
      rethrow;
    }

    _emitState(_currentState);
    return _currentState;
  }

  @override
  Future<SettingsState> toggleFocus(bool enable) async {
    if (enable) {
      // Precondition: Accessibility permission must be verified
      if (!_currentState.isAccessibilityGranted) {
        throw const AccessibilityPermissionRequiredException();
      }
      await _focusService.enableFocus();
    } else {
      await _focusService.disableFocus();
    }

    final refreshedFocus = await _focusService.refreshState();

    _currentState = _currentState.copyWith(
      isFocusEnabled: refreshedFocus.isUserEnabled,
      clearError: true,
    );

    _emitState(_currentState);
    return _currentState;
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    return _focusService.openAccessibilitySettings();
  }

  @override
  Future<bool> openAppSettings() async {
    return _nativeBridge.openAppSettings();
  }

  @override
  Future<SettingsState> resetToDefaults() async {
    // Invariant: Resetting preferences must NOT unexpectedly change or disable Focus.
    // Preserve the authoritative native target and focus enabled state.
    final currentTarget = _currentState.activeTargetPackage;
    final defaults = AppSettings.defaults().copyWith(
      defaultTargetPackage: currentTarget,
    );

    await _repository.saveSettings(defaults);

    _currentState = _currentState.copyWith(
      settings: defaults,
      activeTargetPackage: currentTarget,
      clearError: true,
    );

    _emitState(_currentState);
    return _currentState;
  }

  @override
  void dispose() {
    _stateController.close();
  }

  @override
  Future<SettingsState> updatePreferredExercise(ExerciseType type) async {
    return updateSettings(
      _currentState.settings.copyWith(preferredExerciseType: type),
    );
  }

  void _emitState(SettingsState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}
