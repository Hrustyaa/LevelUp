import 'dart:async';

import 'package:flutter/services.dart';

import '../core/constants/channel_constants.dart';
import '../core/errors/access_exceptions.dart';
import '../core/errors/native_bridge_exception.dart';
import '../models/access_grant_request.dart';
import '../models/access_grant_result.dart';
import '../models/access_grant_status.dart';
import '../models/challenge_type.dart';
import '../models/native_access_status.dart';
import '../models/workout_result.dart';
import 'native_bridge.dart';

export '../core/errors/access_exceptions.dart';
export '../models/access_grant_request.dart';
export '../models/access_grant_result.dart';
export '../models/access_grant_status.dart';

/// Contract for authorizing and orchestrating temporary application access grants.
abstract class IAccessService {
  /// Authorizes and grants temporary application access from a validated [WorkoutResult].
  ///
  /// Enforces pre-conditions:
  /// - Reject free workouts ([ChallengeType.freeWorkout]).
  /// - Verify completed repetitions > 0.
  /// - Verify target package matches active native target.
  /// - Verify Android Accessibility permission is granted.
  /// - Verify voluntary Focus restriction is enabled.
  /// - Suppress duplicate or concurrent requests for the same session.
  Future<AccessGrantResult> grantAccessForCompletedWorkout(WorkoutResult result);

  /// Authorizes and grants temporary application access from an explicit [AccessGrantRequest].
  Future<AccessGrantResult> requestAccess(AccessGrantRequest request);

  /// Queries the authoritative native access status (unlock expiration timestamp).
  Future<NativeAccessStatus> getAccessStatus();

  /// Explicitly resets and revokes any active temporary access unlock.
  Future<bool> resetAccess();

  /// Broadcast stream emitting on successful access grants.
  Stream<AccessGrantResult> get grantStream;

  /// Disposes internal broadcast stream resources.
  void dispose();
}

/// Production implementation of [IAccessService] coordinating through [INativeBridge].
class AccessService implements IAccessService {
  final INativeBridge _bridge;
  final DateTime Function() _clock;
  final StreamController<AccessGrantResult> _grantController =
      StreamController<AccessGrantResult>.broadcast();

  final Map<String, AccessGrantResult> _grantedSessions = <String, AccessGrantResult>{};
  final Set<String> _inFlightSessionIds = <String>{};

  /// Creates an [AccessService].
  ///
  /// Allows dependency injection of custom [INativeBridge] and clock for testing.
  AccessService({
    INativeBridge? bridge,
    DateTime Function()? clock,
  })  : _bridge = bridge ?? const NativeBridge(),
        _clock = clock ?? DateTime.now;

  @override
  Stream<AccessGrantResult> get grantStream => _grantController.stream;

  @override
  Future<AccessGrantResult> grantAccessForCompletedWorkout(WorkoutResult result) async {
    final request = AccessGrantRequest.fromWorkoutResult(result);
    return requestAccess(request);
  }

  @override
  Future<AccessGrantResult> requestAccess(AccessGrantRequest request) async {
    // 0. Runtime validation of AccessGrantRequest integrity
    if (request.challengeContext != ChallengeType.unlockChallenge) {
      throw const IneligibleWorkoutContextException();
    }
    if (!ChannelConstants.allowedTargets.contains(request.targetPackage)) {
      throw UnsupportedAccessTargetException(request.targetPackage);
    }
    if (request.durationMinutes < 1 || request.durationMinutes > 15) {
      throw InvalidAccessDurationException(request.durationMinutes * 60);
    }

    // 1. In-process duplicate suppression: check if already granted
    final existing = _grantedSessions[request.sessionId];
    if (existing != null) {
      return existing; // Idempotent return
    }

    // 2. Concurrency guard: reject concurrent requests for same session ID
    if (_inFlightSessionIds.contains(request.sessionId)) {
      throw ConcurrentGrantException(request.sessionId);
    }
    _inFlightSessionIds.add(request.sessionId);

    try {
      // 3. Query authoritative native state
      final nativeStatus = await _bridge.getState();

      // 4. Precondition: Accessibility permission must be granted
      if (!nativeStatus.isAccessibilityGranted) {
        throw const MissingAccessibilityPermissionException();
      }

      // 5. Precondition: Focus restriction must be enabled
      if (!nativeStatus.isGateEnabled) {
        throw const FocusDisabledException();
      }

      // 6. Precondition: Active native target must match workout target
      if (nativeStatus.targetPackage != request.targetPackage) {
        throw TargetPackageMismatchException(
          workoutTarget: request.targetPackage,
          nativeTarget: nativeStatus.targetPackage,
        );
      }

      // 7. Invoke Native Bridge grantAccess
      final unlockUntil = await _bridge.grantAccess(
        minutes: request.durationMinutes,
      );

      final grantResult = AccessGrantResult(
        sessionId: request.sessionId,
        targetPackage: request.targetPackage,
        status: AccessGrantStatus.granted,
        unlockUntil: unlockUntil,
        grantedAt: _clock(),
      );

      // Cache granted session for process-level idempotency
      _grantedSessions[request.sessionId] = grantResult;
      _emitGrant(grantResult);
      return grantResult;
    } on PlatformException catch (e) {
      throw AccessEnginePlatformException(
        message: 'Platform error during native grantAccess: ${e.message}',
        code: e.code,
        cause: e,
      );
    } on NativeBridgeException catch (e) {
      throw AccessEnginePlatformException(
        message: 'Bridge error during native grantAccess: ${e.message}',
        code: e.code,
        cause: e,
      );
    } on AccessEngineException {
      rethrow;
    } catch (e) {
      // Never perform automatic retries on uncertain failures
      throw AccessEngineException(
        message: 'Unexpected error during access grant: $e',
        cause: e,
      );
    } finally {
      _inFlightSessionIds.remove(request.sessionId);
    }
  }

  @override
  Future<NativeAccessStatus> getAccessStatus() async {
    final nativeStatus = await _bridge.getState();
    return nativeStatus.accessStatus;
  }

  @override
  Future<bool> resetAccess() async {
    try {
      return await _bridge.resetAccess();
    } on NativeBridgeException catch (e) {
      throw AccessEnginePlatformException(
        message: 'Failed to reset access: ${e.message}',
        code: e.code,
        cause: e,
      );
    }
  }

  @override
  void dispose() {
    _grantController.close();
  }

  void _emitGrant(AccessGrantResult result) {
    if (!_grantController.isClosed) {
      _grantController.add(result);
    }
  }
}
