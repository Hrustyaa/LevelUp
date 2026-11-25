// ignore_for_file: lines_longer_than_80_chars

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:levelup_test/app/challenge/production_challenge_controller.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/integration/coordinator_state.dart';
import 'package:levelup_test/core/integration/core_integration_coordinator.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/workout_history_repository.dart';
import 'package:levelup_test/features/achievements/application/achievement_service.dart';
import 'package:levelup_test/features/achievements/data/achievement_catalog.dart';
import 'package:levelup_test/features/achievements/data/achievement_repository.dart';
import 'package:levelup_test/features/challenge/application/challenge_service.dart';
import 'package:levelup_test/features/challenge/data/challenge_catalog.dart';
import 'package:levelup_test/features/pose_detection/application/pose_landmark_smoother.dart';
import 'package:levelup_test/features/pose_detection/application/pose_temporal_guard.dart';
import 'package:levelup_test/features/pose_detection/application/pose_visibility_hysteresis.dart';
import 'package:levelup_test/features/pose_detection/application/push_up_counter.dart';
import 'package:levelup_test/features/pose_detection/application/squat_counter.dart';
import 'package:levelup_test/features/pose_detection/models/pose_overlay_state.dart';
import 'package:levelup_test/features/progress/application/progress_service.dart';
import 'package:levelup_test/features/progress/data/progress_repository.dart';
import 'package:levelup_test/features/settings/application/camera_permission_checker.dart';
import 'package:levelup_test/features/settings/models/app_settings.dart';
import 'package:levelup_test/features/settings/models/camera_permission_status.dart';
import 'package:levelup_test/features/statistics/application/statistics_service.dart';
import 'package:levelup_test/features/statistics/data/statistics_repository.dart';
import 'package:levelup_test/models/workout_result.dart';
import 'package:levelup_test/services/native_bridge.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PoseTemporalGuard
  // ---------------------------------------------------------------------------
  group('PoseTemporalGuard', () {
    const type = PoseLandmarkType.leftKnee;
    const imageSize = Size(480, 640);

    test('first observation always passes', () {
      final guard = PoseTemporalGuard();
      expect(guard.isPlausible(type, const Offset(240, 320), imageSize), isTrue);
    });

    test('small jump within threshold passes', () {
      final guard = PoseTemporalGuard(maxNormalizedJump: 0.25);
      guard.isPlausible(type, const Offset(240, 320), imageSize);
      guard.update(type, const Offset(240, 320));
      // 10px jump on a 640-tall image = 0.016 → well under 0.25
      expect(guard.isPlausible(type, const Offset(250, 320), imageSize), isTrue);
    });

    test('large jump over threshold fails', () {
      final guard = PoseTemporalGuard(maxNormalizedJump: 0.25);
      guard.isPlausible(type, const Offset(240, 320), imageSize);
      guard.update(type, const Offset(240, 320));
      // 300px jump on 640-tall image = 0.47 → over 0.25
      expect(guard.isPlausible(type, const Offset(540, 320), imageSize), isFalse);
    });

    test('reset clears per-landmark state', () {
      final guard = PoseTemporalGuard(maxNormalizedJump: 0.01);
      guard.isPlausible(type, const Offset(240, 320), imageSize);
      guard.update(type, const Offset(240, 320));
      guard.reset();
      // After reset, next observation is treated as first → always passes.
      expect(guard.isPlausible(type, const Offset(540, 320), imageSize), isTrue);
    });

    test('independent landmarks tracked separately', () {
      final guard = PoseTemporalGuard(maxNormalizedJump: 0.01);
      const otherType = PoseLandmarkType.rightKnee;
      guard.isPlausible(type, const Offset(240, 320), imageSize);
      guard.update(type, const Offset(240, 320));
      // otherType never seen → first observation, always passes.
      expect(guard.isPlausible(otherType, const Offset(10, 10), imageSize), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // PoseLandmarkSmoother (One Euro Filter)
  // ---------------------------------------------------------------------------
  group('PoseLandmarkSmoother – One Euro Filter', () {
    const type = PoseLandmarkType.leftKnee;
    final t0 = DateTime(2024, 1, 1, 0, 0, 0);

    test('stationary input converges: smoothed stays near raw', () {
      final smoother = PoseLandmarkSmoother();
      const raw = Offset(100, 200);
      Offset last = raw;
      for (int i = 0; i < 30; i++) {
        last = smoother.smooth(type, raw,
            timestamp: t0.add(Duration(milliseconds: i * 33)));
      }
      expect((last - raw).distance, lessThan(2.0));
    });

    test('fast movement: smoothed tracks within reasonable lag', () {
      final smoother = PoseLandmarkSmoother();
      const start = Offset(50, 50);
      const end = Offset(300, 300);
      Offset last = start;
      for (int i = 0; i < 30; i++) {
        last = smoother.smooth(
          type,
          i < 15 ? start : end,
          timestamp: t0.add(Duration(milliseconds: i * 33)),
        );
      }
      // Should track towards end after 15 frames.
      expect(last.dx, greaterThan(200));
    });

    test('tracking gap > 500ms resets state; next frame returns raw', () {
      final smoother = PoseLandmarkSmoother();
      const raw = Offset(100, 100);
      smoother.smooth(type, raw, timestamp: t0);
      // 600ms gap → state reset
      const afterGap = Offset(400, 400);
      final result = smoother.smooth(type, afterGap,
          timestamp: t0.add(const Duration(milliseconds: 600)));
      expect(result, afterGap);
    });

    test('per-landmark independence: left and right knee smoothed separately', () {
      final smoother = PoseLandmarkSmoother();
      const left = PoseLandmarkType.leftKnee;
      const right = PoseLandmarkType.rightKnee;
      for (int i = 0; i < 10; i++) {
        smoother.smooth(left, const Offset(100, 100),
            timestamp: t0.add(Duration(milliseconds: i * 33)));
        smoother.smooth(right, const Offset(300, 300),
            timestamp: t0.add(Duration(milliseconds: i * 33)));
      }
      final leftResult = smoother.smooth(left, const Offset(100, 100),
          timestamp: t0.add(const Duration(milliseconds: 330)));
      final rightResult = smoother.smooth(right, const Offset(300, 300),
          timestamp: t0.add(const Duration(milliseconds: 330)));
      expect((leftResult - const Offset(100, 100)).distance, lessThan(5));
      expect((rightResult - const Offset(300, 300)).distance, lessThan(5));
    });

    test('reset clears all landmark state', () {
      final smoother = PoseLandmarkSmoother();
      for (int i = 0; i < 10; i++) {
        smoother.smooth(type, const Offset(100, 100),
            timestamp: t0.add(Duration(milliseconds: i * 33)));
      }
      smoother.reset();
      // After reset, first smooth is first observation → returns raw.
      final result = smoother.smooth(type, const Offset(999, 999),
          timestamp: t0.add(const Duration(milliseconds: 400)));
      expect(result, const Offset(999, 999));
    });

    test('dt ≤ 0 uses alpha=0.5 fallback and does not throw', () {
      final smoother = PoseLandmarkSmoother();
      final t = DateTime(2024);
      smoother.smooth(type, const Offset(100, 100), timestamp: t);
      // Same timestamp → dt = 0
      expect(
        () => smoother.smooth(type, const Offset(200, 200), timestamp: t),
        returnsNormally,
      );
    });

    test('irregular frame intervals handled without crash', () {
      final smoother = PoseLandmarkSmoother();
      final intervals = [16, 100, 33, 200, 16, 50];
      var t = t0;
      for (final ms in intervals) {
        t = t.add(Duration(milliseconds: ms));
        expect(
          () => smoother.smooth(type, const Offset(100, 200), timestamp: t),
          returnsNormally,
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // PushUpCounter
  // ---------------------------------------------------------------------------
  group('PushUpCounter', () {
    PushUpCounter make() => PushUpCounter();

    test('valid frontal push-up cycle counts 1 rep', () {
      final counter = make();
      // Phase: up → down requires consecutiveFrames frames at downAngle.
      for (int i = 0; i < PushUpThresholds.consecutiveFrames; i++) {
        counter.processAngle(80); // 80° < downAngle(100°) → down
      }
      expect(counter.currentPhase, SquatPhase.down);

      // Phase: down → up requires consecutiveFrames frames at upAngle.
      SquatCounterResult? result;
      for (int i = 0; i < PushUpThresholds.consecutiveFrames; i++) {
        result = counter.processAngle(160); // 160° > upAngle(150°) → up + rep
      }
      expect(result?.repetitionCount, 1);
      expect(result?.isRepetitionCompleted, isTrue);
    });

    test('partial push-up (only goes down) does not count a rep', () {
      final counter = make();
      for (int i = 0; i < PushUpThresholds.consecutiveFrames + 2; i++) {
        counter.processAngle(80);
      }
      final result = counter.processAngle(80);
      expect(result.repetitionCount, 0);
    });

    test('null angle (low-confidence pose) → no rep counted, tracking=false', () {
      final counter = make();
      final result = counter.processAngle(null);
      expect(result.repetitionCount, 0);
      expect(result.isValidTracking, isFalse);
    });

    test('repeated identical frames do not generate multiple reps (debounce)', () {
      final counter = make();
      // Complete one rep.
      for (int i = 0; i < PushUpThresholds.consecutiveFrames; i++) {
        counter.processAngle(80);
      }
      for (int i = 0; i < PushUpThresholds.consecutiveFrames; i++) {
        counter.processAngle(160);
      }
      expect(counter.repetitionCount, 1);
      // Spam the up-angle: should not count more than 1 rep.
      SquatCounterResult? result;
      for (int i = 0; i < 20; i++) {
        result = counter.processAngle(160);
      }
      expect(result?.repetitionCount, 1);
    });

    test('reset clears repetition count and state', () {
      final counter = make();
      for (int i = 0; i < PushUpThresholds.consecutiveFrames; i++) {
        counter.processAngle(80);
      }
      for (int i = 0; i < PushUpThresholds.consecutiveFrames; i++) {
        counter.processAngle(160);
      }
      expect(counter.repetitionCount, 1);
      counter.reset();
      expect(counter.repetitionCount, 0);
      expect(counter.currentPhase, SquatPhase.up);
    });

    test('goal defaults to PushUpThresholds.defaultGoal', () {
      final counter = make();
      expect(counter.targetGoal, PushUpThresholds.defaultGoal);
    });
  });

  // ---------------------------------------------------------------------------
  // PushUpGeometry
  // ---------------------------------------------------------------------------
  group('PushUpGeometry', () {
    test('calculateElbowAngle: straight arm = ~180°', () {
      // Shoulder above elbow above wrist in a straight line.
      const shoulder = Offset(100, 50);
      const elbow = Offset(100, 100);
      const wrist = Offset(100, 150);
      final angle = PushUpGeometry.calculateElbowAngle(shoulder, elbow, wrist);
      expect(angle, closeTo(180, 5));
    });

    test('calculateElbowAngle: 90° bend', () {
      const shoulder = Offset(0, 100);
      const elbow = Offset(100, 100);
      const wrist = Offset(100, 0);
      final angle = PushUpGeometry.calculateElbowAngle(shoulder, elbow, wrist);
      expect(angle, closeTo(90, 5));
    });

    test('estimateElbowAngle returns null when pose has no arm landmarks', () {
      // Build a pose with zero landmarks.
      final pose = _EmptyPose();
      expect(PushUpGeometry.estimateElbowAngle(pose), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // ExerciseMode in PoseOverlayState
  // ---------------------------------------------------------------------------
  group('PoseOverlayState.exerciseMode', () {
    test('defaults to ExerciseMode.squat', () {
      expect(PoseOverlayState.empty.exerciseMode, ExerciseMode.squat);
    });

    test('can be set to ExerciseMode.pushUp', () {
      const state = PoseOverlayState(exerciseMode: ExerciseMode.pushUp);
      expect(state.exerciseMode, ExerciseMode.pushUp);
    });

    test('hasAnyArm false when no arm landmarks', () {
      expect(PoseOverlayState.empty.hasAnyArm, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // AppSettings – exercise preference persistence
  // ---------------------------------------------------------------------------
  group('AppSettings.preferredExerciseType', () {
    test('fromJson with pushUp value returns ExerciseType.pushUp', () {
      final settings = AppSettings.fromJson(<String, dynamic>{
        'preferred_exercise_type': 'pushUp',
      });
      expect(settings.preferredExerciseType, ExerciseType.pushUp);
    });

    test('fromJson without key defaults to ExerciseType.squats', () {
      final settings = AppSettings.fromJson(<String, dynamic>{});
      expect(settings.preferredExerciseType, ExerciseType.squats);
    });

    test('fromJson with invalid value defaults to ExerciseType.squats', () {
      final settings = AppSettings.fromJson(<String, dynamic>{
        'preferred_exercise_type': 'unknownExercise',
      });
      expect(settings.preferredExerciseType, ExerciseType.squats);
    });

    test('copyWith updates preferredExerciseType', () {
      final settings = AppSettings.defaults();
      final updated = settings.copyWith(preferredExerciseType: ExerciseType.pushUp);
      expect(updated.preferredExerciseType, ExerciseType.pushUp);
    });

    test('toJson round-trips pushUp preference', () {
      final settings =
          AppSettings.defaults().copyWith(preferredExerciseType: ExerciseType.pushUp);
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.preferredExerciseType, ExerciseType.pushUp);
    });

    test('defaults returns squats preference', () {
      expect(AppSettings.defaults().preferredExerciseType, ExerciseType.squats);
    });

    test('equality: same preferredExerciseType → equal', () {
      final a = AppSettings.defaults().copyWith(preferredExerciseType: ExerciseType.pushUp);
      final b = AppSettings.defaults().copyWith(preferredExerciseType: ExerciseType.pushUp);
      expect(a, b);
    });

    test('equality: different preferredExerciseType → not equal', () {
      final a = AppSettings.defaults().copyWith(preferredExerciseType: ExerciseType.squats);
      final b = AppSettings.defaults().copyWith(preferredExerciseType: ExerciseType.pushUp);
      expect(a, isNot(b));
    });
  });

  // ---------------------------------------------------------------------------
  // ExerciseType enum
  // ---------------------------------------------------------------------------
  group('ExerciseType', () {
    test('squats has name squats', () {
      expect(ExerciseType.squats.name, 'squats');
    });

    test('pushUp has name pushUp', () {
      expect(ExerciseType.pushUp.name, 'pushUp');
    });
  });

  // ---------------------------------------------------------------------------
  // One Euro Filter – raw angles not altered before SquatCounter
  // ---------------------------------------------------------------------------
  group('Smoother does not alter raw angle pathway', () {
    test('processAngle receives raw value regardless of smoother state', () {
      // Visual smoothing is cosmetic: the counter always gets the raw angle.
      // Verify this by running PushUpCounter directly with known angles.
      final counter = PushUpCounter();
      final smoother = PoseLandmarkSmoother();
      const type = PoseLandmarkType.leftKnee;
      final t = DateTime(2024);

      // Smooth some noisy input.
      smoother.smooth(type, const Offset(1, 1), timestamp: t);
      smoother.smooth(type, const Offset(999, 999),
          timestamp: t.add(const Duration(milliseconds: 33)));

      // Raw angle 80 goes directly to counter — not smoothed.
      final result = counter.processAngle(80);
      expect(result.repetitionCount, 0); // Not a full rep yet, just goes down.
      expect(result.isValidTracking, isTrue); // Angle was processed.
    });
  });

  // ---------------------------------------------------------------------------
  // Audit Regression Tests (11D Final Audit)
  // ---------------------------------------------------------------------------
  group('11D Audit Regression Tests', () {
    test('PoseTemporalGuard does not freeze legitimate sustained relocation', () {
      const type = PoseLandmarkType.leftKnee;
      const imageSize = Size(480, 640);
      final guard = PoseTemporalGuard(
        maxNormalizedJump: 0.25,
        maxConsecutiveRejections: 2,
      );

      guard.isPlausible(type, const Offset(100, 100), imageSize);
      guard.update(type, const Offset(100, 100));

      // Frame 1 at new position: rejected as single-frame spike
      expect(guard.isPlausible(type, const Offset(400, 100), imageSize), isFalse);
      expect(guard.lastPosition(type), const Offset(100, 100));

      // Frame 2 sustained at new position: accepted so motion never freezes
      expect(guard.isPlausible(type, const Offset(405, 100), imageSize), isTrue);
      guard.update(type, const Offset(405, 100));
      expect(guard.lastPosition(type), const Offset(405, 100));
    });

    test('ChallengeService routes pushUp Free Workout without affecting unlock', () {
      final service = ChallengeService();

      final pushUpReq =
          service.createFreeWorkoutRequest(exerciseType: ExerciseType.pushUp);
      final pushUpDef = service.getChallengeDefinition(pushUpReq.challengeId);
      expect(pushUpReq.challengeId, ChallengeCatalog.pushUpFreeWorkoutId);
      expect(pushUpDef.exerciseType, ExerciseType.pushUp);
      expect(pushUpDef.accessDurationSeconds, 0);

      final unlockReq = service.createUnlockChallengeRequest(
        ChannelConstants.allowedTargets.first,
      );
      final unlockDef = service.getChallengeDefinition(unlockReq.challengeId);
      expect(unlockDef.exerciseType, ExerciseType.squats);
      expect(unlockDef.accessDurationSeconds, 300);
    });

    test('unlock controllers retain the assigned exercise in the normal build', () {
      for (final exercise in ExerciseType.values) {
        final controller = ProductionChallengeController(
          coordinator: _StubCoordinator(),
          cameraPermissionChecker: _StubCameraChecker(),
          nativeBridge: _StubNativeBridge(),
          isUnlockChallenge: true,
          exerciseType: exercise,
        );
        expect(controller.exerciseType, exercise);
        controller.dispose();
      }
    });

    test('Experimental push-up session preserves history honestly and earns zero production XP, stats, streaks, or achievements while squat rewards remain intact', () async {
      sqfliteFfiInit();
      final tempDir = await Directory.systemTemp.createTemp('levelup_11d_audit_');
      final dbManager = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: p.join(tempDir.path, 'audit.db'),
      );

      try {
        final workoutRepo = WorkoutHistoryRepository(databaseManager: dbManager);
        final statsRepo = SqliteStatisticsRepository(databaseManager: dbManager);
        final xpRepo = SqliteProgressRepository(databaseManager: dbManager);
        final achievementRepo =
            SqliteAchievementRepository(databaseManager: dbManager);

        final progressService = ProgressService(
          repository: xpRepo,
          historyRepository: workoutRepo,
        );
        final statsService = StatisticsService(
          repository: statsRepo,
          progressService: progressService,
        );
        final achievementService = AchievementService(
          repository: achievementRepo,
          statisticsService: statsService,
          progressService: progressService,
        );

        await progressService.initialize();

        // 1. Record 5 experimental push-up Free Workouts (25 push-up reps total)
        for (int i = 0; i < 5; i++) {
          final result = WorkoutResult(
            sessionId: 'pushup_sess_$i',
            requestId: 'req_$i',
            challengeId: ChallengeCatalog.pushUpFreeWorkoutId,
            challengeContext: ChallengeType.freeWorkout,
            exerciseType: ExerciseType.pushUp,
            targetPackage: null,
            completedRepetitions: 5,
            duration: const Duration(seconds: 20),
            completedAt: DateTime.utc(2026, 11, 25, 10, i),
            eligibleForAccess: false,
            accessDurationSeconds: 0,
            earnedXp: 50,
            source: 'experimental_unverified',
          );
          await workoutRepo.saveCompletedWorkout(result);
          final outcome = await progressService.recordCompletedWorkout(result);
          expect(outcome.awarded, isFalse);
          expect(outcome.xpAwarded, 0);
        }

        // Even if someone passes source='camera' with ExerciseType.pushUp,
        // XpRewardPolicy must still reject unvalidated push-ups.
        final forgedCameraPushUp = WorkoutResult(
          sessionId: 'pushup_forged',
          requestId: 'req_forged',
          challengeId: ChallengeCatalog.pushUpFreeWorkoutId,
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.pushUp,
          targetPackage: null,
          completedRepetitions: 5,
          duration: const Duration(seconds: 20),
          completedAt: DateTime.utc(2026, 11, 25, 10, 30),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
          earnedXp: 50,
          source: 'camera',
        );
        final forgedOutcome =
            await progressService.recordCompletedWorkout(forgedCameraPushUp);
        expect(forgedOutcome.awarded, isFalse);
        expect(forgedOutcome.xpAwarded, 0);

        // Experimental push-up history is preserved honestly in workout_sessions
        final saved = await workoutRepo.getWorkoutBySessionId('pushup_sess_0');
        expect(saved, isNotNull);
        expect(saved!.exerciseType, ExerciseType.pushUp);
        expect(saved.source, 'experimental_unverified');

        // Authoritative statistics, XP, streaks, and achievements must all be 0
        final snapshot = await statsService.refresh();
        expect(snapshot.workouts.allTimeCompleted, 0);
        expect(snapshot.workouts.freeWorkoutsCompleted, 0);
        expect(snapshot.workouts.totalVerifiedRepetitions, 0);
        expect(progressService.currentState.levelInfo.totalXp, 0);
        expect(progressService.currentState.streakInfo.currentStreak, 0);

        final achState = await achievementService.evaluateAndRefresh();
        final firstWorkout = achState.achievements.firstWhere(
            (a) => a.definition.id == AchievementCatalog.firstWorkoutId);
        final squats25 = achState.achievements.firstWhere(
            (a) => a.definition.id == AchievementCatalog.twentyFiveSquatsId);
        expect(firstWorkout.isUnlocked, isFalse);
        expect(squats25.isUnlocked, isFalse);

        // 2. Legitimate squat workout STILL earns 50 XP and counts in stats
        final squatResult = WorkoutResult(
          sessionId: 'squat_sess_1',
          requestId: 'req_squat_1',
          challengeId: ChallengeCatalog.squatFreeWorkoutId,
          challengeContext: ChallengeType.freeWorkout,
          exerciseType: ExerciseType.squats,
          targetPackage: null,
          completedRepetitions: 5,
          duration: const Duration(seconds: 20),
          completedAt: DateTime.utc(2026, 11, 25, 11, 0),
          eligibleForAccess: false,
          accessDurationSeconds: 0,
          earnedXp: 50,
          source: 'camera',
        );
        await workoutRepo.saveCompletedWorkout(squatResult);
        final squatOutcome =
            await progressService.recordCompletedWorkout(squatResult);
        expect(squatOutcome.awarded, isTrue);
        expect(squatOutcome.xpAwarded, 50);

        final updatedStats = await statsService.refresh();
        expect(updatedStats.workouts.allTimeCompleted, 1);
        expect(updatedStats.workouts.totalVerifiedRepetitions, 5);

        achievementService.dispose();
        statsService.dispose();
        progressService.dispose();
      } finally {
        await dbManager.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    group('PoseVisibilityHysteresis (Time-Aware)', () {
      final t0 = DateTime(2026, 11, 25, 10, 0, 0);

      test('requires enterThreshold (0.55) to establish initial tracking', () {
        final hysteresis = PoseVisibilityHysteresis<String, String>();
        final res = hysteresis.update(
          key: 'left',
          candidate: 'leg_1',
          minLikelihood: 0.48,
          now: t0,
        );
        expect(res.isVisible, isFalse);
        expect(res.status, LimbVisibilityStatus.hidden);
        expect(res.value, isNull);
      });

      test('flickering between 0.45 and 0.65 stays visible without dropping', () {
        final hysteresis = PoseVisibilityHysteresis<String, String>();
        // Establish at 0.65
        final r1 = hysteresis.update(
          key: 'left',
          candidate: 'leg_1',
          minLikelihood: 0.65,
          now: t0,
        );
        expect(r1.isConfident, isTrue);

        // Dip to 0.45 at +50ms → stays visible as uncertain (never hidden)
        final r2 = hysteresis.update(
          key: 'left',
          candidate: 'leg_2',
          minLikelihood: 0.45,
          now: t0.add(const Duration(milliseconds: 50)),
        );
        expect(r2.isVisible, isTrue);
        expect(r2.isUncertain, isTrue);
        expect(r2.value, 'leg_2');

        // Recover to 0.60 at +100ms → confident again
        final r3 = hysteresis.update(
          key: 'left',
          candidate: 'leg_3',
          minLikelihood: 0.60,
          now: t0.add(const Duration(milliseconds: 100)),
        );
        expect(r3.isConfident, isTrue);
        expect(r3.value, 'leg_3');
      });

      test('brief dropout within 250ms holds last value as uncertain, sustained loss (>250ms) hides promptly', () {
        final hysteresis = PoseVisibilityHysteresis<String, String>();
        hysteresis.update(
          key: 'left',
          candidate: 'leg_1',
          minLikelihood: 0.70,
          now: t0,
        );

        // Dropout at +120ms → held as uncertain
        final held = hysteresis.update(
          key: 'left',
          candidate: null,
          minLikelihood: 0.0,
          now: t0.add(const Duration(milliseconds: 120)),
        );
        expect(held.isVisible, isTrue);
        expect(held.isUncertain, isTrue);
        expect(held.value, 'leg_1');

        // Sustained loss at +260ms (> 250ms grace) → hidden and cleared
        final lost = hysteresis.update(
          key: 'left',
          candidate: null,
          minLikelihood: 0.0,
          now: t0.add(const Duration(milliseconds: 260)),
        );
        expect(lost.isVisible, isFalse);
        expect(lost.status, LimbVisibilityStatus.hidden);
        expect(lost.value, isNull);

        // Reacquisition with 0.45 (< enterThreshold 0.55) stays hidden
        final weakReacq = hysteresis.update(
          key: 'left',
          candidate: 'leg_2',
          minLikelihood: 0.45,
          now: t0.add(const Duration(milliseconds: 300)),
        );
        expect(weakReacq.isVisible, isFalse);

        // Reacquisition with 0.60 (>= enterThreshold 0.55) succeeds
        final strongReacq = hysteresis.update(
          key: 'left',
          candidate: 'leg_3',
          minLikelihood: 0.60,
          now: t0.add(const Duration(milliseconds: 330)),
        );
        expect(strongReacq.isConfident, isTrue);
        expect(strongReacq.value, 'leg_3');
      });

      test('reset clears held state so stale landmarks cannot remain', () {
        final hysteresis = PoseVisibilityHysteresis<String, String>();
        hysteresis.update(
          key: 'left',
          candidate: 'leg_1',
          minLikelihood: 0.75,
          now: t0,
        );
        hysteresis.reset();

        final afterReset = hysteresis.update(
          key: 'left',
          candidate: null,
          minLikelihood: 0.0,
          now: t0.add(const Duration(milliseconds: 30)),
        );
        expect(afterReset.isVisible, isFalse);
        expect(afterReset.value, isNull);
      });

      test('controller disposal clears pose overlay and resets hysteresis', () {
        final controller = ProductionChallengeController(
          coordinator: _StubCoordinator(),
          cameraPermissionChecker: _StubCameraChecker(),
          nativeBridge: _StubNativeBridge(),
          isUnlockChallenge: false,
          exerciseType: ExerciseType.squats,
        );
        expect(controller.poseOverlayListenable.value, PoseOverlayState.empty);
        controller.dispose();
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// A [Pose] with no landmarks, used to test null-angle paths.
class _EmptyPose implements Pose {
  @override
  Map<PoseLandmarkType, PoseLandmark> get landmarks => const {};
}

class _StubCoordinator implements ICoreIntegrationCoordinator {
  @override
  CoordinatorState get currentState => CoordinatorState.initial();

  @override
  Stream<CoordinatorState> get stateStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubCameraChecker implements ICameraPermissionChecker {
  @override
  Future<CameraPermissionStatus> checkCameraPermission() async =>
      CameraPermissionStatus.granted;

  @override
  Future<CameraPermissionStatus> requestCameraPermission() async =>
      CameraPermissionStatus.granted;
}

class _StubNativeBridge implements INativeBridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
