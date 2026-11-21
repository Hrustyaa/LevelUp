import 'package:flutter/services.dart';

import '../core/constants/channel_constants.dart';
import '../core/errors/native_bridge_exception.dart';
import '../models/native_focus_status.dart';

/// Abstract contract for communicating with the Android native layer (MainActivity & Blocker v3).
abstract class INativeBridge {
  /// Fetches the current native restriction gate status.
  Future<NativeFocusStatus> getState();

  /// Updates the target package in native SharedPreferences.
  /// Throws [UnsupportedTargetPackageException] if package is not in the allowed targets set.
  Future<bool> setTarget(String targetPackage);

  /// Toggles voluntary restriction on/off.
  Future<bool> setEnabled(bool enabled);

  /// Dispatches the Android system intent to open Accessibility Settings.
  Future<bool> openAccessibilitySettings();

  /// Atomically reads and resets the transient "open_challenge" flag set by the native overlay.
  Future<bool> consumeChallengeRequest();

  /// Grants temporary access for the specified [minutes] (coerced by native to 1..15, default: 5).
  /// Launches the target app if supported, and returns the calculated [DateTime] expiration.
  Future<DateTime> grantAccess({int minutes = 5});

  /// Immediately resets temporary access and re-arms restriction.
  Future<bool> resetAccess();

  /// Diagnostic utility to verify whether the native channel is accessible and responsive.
  Future<bool> isAvailable();
}

/// Concrete implementation of [INativeBridge] wrapping the existing platform channel.
class NativeBridge implements INativeBridge {
  final MethodChannel _channel;

  /// Default constructor using the canonical channel name `levelup_test/control`.
  /// Allows dependency injection of a custom or mock [MethodChannel] for testing.
  const NativeBridge({
    MethodChannel channel = const MethodChannel(ChannelConstants.controlChannel),
  }) : _channel = channel;

  @override
  Future<NativeFocusStatus> getState() async {
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        ChannelConstants.methodGetState,
      );
      return NativeFocusStatus.fromMap(raw);
    } on PlatformException catch (e) {
      throw _handlePlatformException(ChannelConstants.methodGetState, e);
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodGetState,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message: 'Unexpected error calling ${ChannelConstants.methodGetState}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> setTarget(String targetPackage) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelConstants.methodSetTarget,
        {ChannelConstants.argTarget: targetPackage},
      );
      return result ?? true;
    } on PlatformException catch (e) {
      if (e.code == 'TARGET') {
        throw UnsupportedTargetPackageException(
          targetPackage,
          message: e.message,
          details: e.details,
          cause: e,
        );
      }
      throw _handlePlatformException(ChannelConstants.methodSetTarget, e);
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodSetTarget,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message: 'Unexpected error calling ${ChannelConstants.methodSetTarget}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelConstants.methodSetEnabled,
        {ChannelConstants.argEnabled: enabled},
      );
      return result ?? true;
    } on PlatformException catch (e) {
      throw _handlePlatformException(ChannelConstants.methodSetEnabled, e);
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodSetEnabled,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message: 'Unexpected error calling ${ChannelConstants.methodSetEnabled}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> openAccessibilitySettings() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelConstants.methodOpenAccessibilitySettings,
      );
      return result ?? true;
    } on PlatformException catch (e) {
      throw _handlePlatformException(
        ChannelConstants.methodOpenAccessibilitySettings,
        e,
      );
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodOpenAccessibilitySettings,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message:
            'Unexpected error calling ${ChannelConstants.methodOpenAccessibilitySettings}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> consumeChallengeRequest() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelConstants.methodConsumeChallengeRequest,
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw _handlePlatformException(
        ChannelConstants.methodConsumeChallengeRequest,
        e,
      );
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodConsumeChallengeRequest,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message:
            'Unexpected error calling ${ChannelConstants.methodConsumeChallengeRequest}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<DateTime> grantAccess({int minutes = 5}) async {
    try {
      final unlockUntilMs = await _channel.invokeMethod<num>(
        ChannelConstants.methodGrantAccess,
        {ChannelConstants.argMinutes: minutes},
      );

      if (unlockUntilMs == null || unlockUntilMs <= 0) {
        throw MalformedNativeResponseException(
          'Native grantAccess returned invalid timestamp: $unlockUntilMs',
        );
      }

      return DateTime.fromMillisecondsSinceEpoch(unlockUntilMs.toInt());
    } on PlatformException catch (e) {
      throw _handlePlatformException(ChannelConstants.methodGrantAccess, e);
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodGrantAccess,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message: 'Unexpected error calling ${ChannelConstants.methodGrantAccess}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> resetAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelConstants.methodResetAccess,
      );
      return result ?? true;
    } on PlatformException catch (e) {
      throw _handlePlatformException(ChannelConstants.methodResetAccess, e);
    } on MissingPluginException catch (e) {
      throw NativeBridgeNotImplementedException(
        ChannelConstants.methodResetAccess,
        message: e.message,
        cause: e,
      );
    } catch (e) {
      if (e is NativeBridgeException) rethrow;
      throw NativeBridgeException(
        message: 'Unexpected error calling ${ChannelConstants.methodResetAccess}: $e',
        cause: e,
      );
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      await getState();
      return true;
    } catch (_) {
      return false;
    }
  }

  NativeBridgeException _handlePlatformException(
    String method,
    PlatformException e,
  ) {
    return NativeBridgeException(
      message: 'Platform error in method "$method": ${e.message}',
      code: e.code,
      details: e.details,
      cause: e,
    );
  }
}
