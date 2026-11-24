import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/core/errors/persistence_exceptions.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/data/repositories/access_attempt_repository.dart';
import 'package:levelup_test/models/access_attempt_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late LevelUpDatabase dbManager;
  late AccessAttemptRepository repository;
  late DateTime fixedTime;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('access_repo_test_');
    final dbPath = p.join(tempDir.path, 'access_test.db');
    dbManager = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
    repository = AccessAttemptRepository(databaseManager: dbManager);
    fixedTime = DateTime.utc(2026, 11, 21, 17, 30);
  });

  tearDown(() async {
    await dbManager.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AccessAttemptRepository Audit Journal & State Transitions', () {
    test('14. creating an access attempt once enters prepared state', () async {
      final record = await repository.createAttemptIfAbsent(
        sessionId: 'session_att_1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      expect(record.sessionId, equals('session_att_1'));
      expect(record.targetPackage, equals(ChannelConstants.targetYouTube));
      expect(record.durationSeconds, equals(300));
      expect(record.state, equals(AccessAttemptState.prepared));
      expect(record.attemptedAt, equals(fixedTime));
      expect(record.confirmedAt, isNull);
      expect(record.unlockUntil, isNull);

      final retrieved = await repository.getAttemptBySessionId('session_att_1');
      expect(retrieved, equals(record));
    });

    test('15. duplicate access attempts do not overwrite existing state', () async {
      // Step 1: Create initial attempt
      await repository.createAttemptIfAbsent(
        sessionId: 'session_dup_state',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      // Step 2: Confirm the attempt
      final confirmedTime = fixedTime.add(const Duration(seconds: 1));
      final unlockUntil = fixedTime.add(const Duration(minutes: 5));
      await repository.markConfirmed(
        sessionId: 'session_dup_state',
        confirmedAt: confirmedTime,
        unlockUntil: unlockUntil,
      );

      // Step 3: Call createAttemptIfAbsent again for the same session
      final duplicateResult = await repository.createAttemptIfAbsent(
        sessionId: 'session_dup_state',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime.add(const Duration(minutes: 10)),
      );

      // Invariant: Must return the existing CONFIRMED record, not overwrite with PREPARED
      expect(duplicateResult.state, equals(AccessAttemptState.confirmed));
      expect(duplicateResult.confirmedAt, equals(confirmedTime));
      expect(duplicateResult.unlockUntil, equals(unlockUntil));
    });

    test('16. confirmed access state persistence stores authoritative timestamps', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 'session_confirm_test',
        targetPackage: ChannelConstants.targetInstagram,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      final confirmedAt = DateTime.utc(2026, 11, 21, 17, 30, 2);
      final unlockUntil = DateTime.utc(2026, 11, 21, 17, 35, 2);

      final confirmedRecord = await repository.markConfirmed(
        sessionId: 'session_confirm_test',
        confirmedAt: confirmedAt,
        unlockUntil: unlockUntil,
      );

      expect(confirmedRecord.state, equals(AccessAttemptState.confirmed));
      expect(confirmedRecord.confirmedAt, equals(confirmedAt));
      expect(confirmedRecord.unlockUntil, equals(unlockUntil));

      final persisted = await repository.getAttemptBySessionId('session_confirm_test');
      expect(persisted!.state, equals(AccessAttemptState.confirmed));
      expect(persisted.unlockUntil, equals(unlockUntil));
    });

    test('17. uncertain native result persistence records failure reason', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 'session_uncertain_test',
        targetPackage: ChannelConstants.targetTikTok,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      final uncertainRecord = await repository.markUncertain(
        sessionId: 'session_uncertain_test',
        reason: 'MethodChannel IPC timeout: response not received',
      );

      expect(uncertainRecord.state, equals(AccessAttemptState.uncertain));
      expect(uncertainRecord.failureReason, contains('IPC timeout'));

      final persisted = await repository.getAttemptBySessionId('session_uncertain_test');
      expect(persisted!.state, equals(AccessAttemptState.uncertain));
      expect(persisted.requiresReconciliation, isTrue);
    });

    test('18. prepared and uncertain records are never automatically treated as safe to retry', () async {
      final prep = await repository.createAttemptIfAbsent(
        sessionId: 'session_prep_safe',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );
      expect(prep.state.requiresReconciliation, isTrue);
      expect(prep.state.isConfirmed, isFalse);

      final uncertain = await repository.markUncertain(
        sessionId: 'session_prep_safe',
        reason: 'Uncertain connection drop',
      );
      expect(uncertain.state.requiresReconciliation, isTrue);
      expect(uncertain.state.isConfirmed, isFalse);
    });

    test('definitively rejected access attempt is recorded', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 'session_rejected_test',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      final rejected = await repository.markDefinitivelyRejected(
        sessionId: 'session_rejected_test',
        reason: 'Focus gate disabled by user',
      );

      expect(rejected.state, equals(AccessAttemptState.definitivelyRejected));
      expect(rejected.state.isDefinitivelyRejected, isTrue);
      expect(rejected.failureReason, contains('Focus gate disabled'));
    });

    test('never downgrades an already confirmed grant to uncertain or rejected', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 'session_no_downgrade',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      await repository.markConfirmed(
        sessionId: 'session_no_downgrade',
        confirmedAt: fixedTime,
        unlockUntil: fixedTime.add(const Duration(minutes: 5)),
      );

      // Attempt to mark uncertain on an already confirmed grant
      final uncertainAttempt = await repository.markUncertain(
        sessionId: 'session_no_downgrade',
        reason: 'Late error callback',
      );
      expect(uncertainAttempt.state, equals(AccessAttemptState.confirmed));

      // Attempt to mark rejected on an already confirmed grant
      final rejectedAttempt = await repository.markDefinitivelyRejected(
        sessionId: 'session_no_downgrade',
        reason: 'Precondition re-check',
      );
      expect(rejectedAttempt.state, equals(AccessAttemptState.confirmed));
    });

    test('updating a non-existent session ID throws RecordNotFoundException', () async {
      await expectLater(
        () => repository.markConfirmed(
          sessionId: 'non_existent_session',
          confirmedAt: fixedTime,
          unlockUntil: fixedTime.add(const Duration(minutes: 5)),
        ),
        throwsA(isA<RecordNotFoundException>()),
      );
    });

    test('rejects invalid attempt input with InvalidWorkoutDataException', () async {
      await expectLater(
        () => repository.createAttemptIfAbsent(
          sessionId: '   ',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 300,
          attemptedAt: fixedTime,
        ),
        throwsA(isA<InvalidWorkoutDataException>()),
      );

      await expectLater(
        () => repository.createAttemptIfAbsent(
          sessionId: 's1',
          targetPackage: 'com.unsupported.package',
          durationSeconds: 300,
          attemptedAt: fixedTime,
        ),
        throwsA(isA<InvalidWorkoutDataException>()),
      );

      await expectLater(
        () => repository.createAttemptIfAbsent(
          sessionId: 's1',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 0,
          attemptedAt: fixedTime,
        ),
        throwsA(isA<InvalidWorkoutDataException>()),
      );
    });

    test('rejects conflicting payloads sharing the same sessionId', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 'session_conflict_1',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      // Same sessionId, different targetPackage
      await expectLater(
        () => repository.createAttemptIfAbsent(
          sessionId: 'session_conflict_1',
          targetPackage: ChannelConstants.targetInstagram,
          durationSeconds: 300,
          attemptedAt: fixedTime,
        ),
        throwsA(
          isA<ConflictingAccessAttemptException>()
              .having((e) => e.sessionId, 'sessionId', equals('session_conflict_1')),
        ),
      );

      // Same sessionId, different durationSeconds
      await expectLater(
        () => repository.createAttemptIfAbsent(
          sessionId: 'session_conflict_1',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 600,
          attemptedAt: fixedTime,
        ),
        throwsA(
          isA<ConflictingAccessAttemptException>()
              .having((e) => e.sessionId, 'sessionId', equals('session_conflict_1')),
        ),
      );
    });

    test('invalid state transitions throw InvalidStateTransitionException', () async {
      // 1. definitivelyRejected cannot transition to uncertain
      await repository.createAttemptIfAbsent(
        sessionId: 's_rej_to_unc',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );
      await repository.markDefinitivelyRejected(
        sessionId: 's_rej_to_unc',
        reason: 'Precondition failed',
      );
      await expectLater(
        () => repository.markUncertain(
          sessionId: 's_rej_to_unc',
          reason: 'Late network error',
        ),
        throwsA(isA<InvalidStateTransitionException>()),
      );

      // 2. uncertain cannot transition to definitivelyRejected
      await repository.createAttemptIfAbsent(
        sessionId: 's_unc_to_rej',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );
      await repository.markUncertain(
        sessionId: 's_unc_to_rej',
        reason: 'Channel timeout',
      );
      await expectLater(
        () => repository.markDefinitivelyRejected(
          sessionId: 's_unc_to_rej',
          reason: 'Attempting to reject uncertain',
        ),
        throwsA(isA<InvalidStateTransitionException>()),
      );

      // 3. definitivelyRejected cannot transition to confirmed
      await repository.createAttemptIfAbsent(
        sessionId: 's_rej_to_conf',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );
      await repository.markDefinitivelyRejected(
        sessionId: 's_rej_to_conf',
        reason: 'Failed preconditions',
      );
      await expectLater(
        () => repository.markConfirmed(
          sessionId: 's_rej_to_conf',
          confirmedAt: fixedTime,
          unlockUntil: fixedTime.add(const Duration(minutes: 5)),
        ),
        throwsA(isA<InvalidStateTransitionException>()),
      );
    });

    test('duplicate transitions to the same state are idempotent', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 's_idempotent',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      // Idempotent markUncertain
      final unc1 = await repository.markUncertain(
        sessionId: 's_idempotent',
        reason: 'Timeout 1',
      );
      final unc2 = await repository.markUncertain(
        sessionId: 's_idempotent',
        reason: 'Timeout 1',
      );
      expect(unc1.state, equals(AccessAttemptState.uncertain));
      expect(unc2.state, equals(AccessAttemptState.uncertain));

      // Idempotent markConfirmed (e.g. following uncertain reconciliation)
      final unlockUntil = fixedTime.add(const Duration(minutes: 5));
      final conf1 = await repository.markConfirmed(
        sessionId: 's_idempotent',
        confirmedAt: fixedTime,
        unlockUntil: unlockUntil,
      );
      final conf2 = await repository.markConfirmed(
        sessionId: 's_idempotent',
        confirmedAt: fixedTime,
        unlockUntil: unlockUntil,
      );
      expect(conf1.state, equals(AccessAttemptState.confirmed));
      expect(conf2.state, equals(AccessAttemptState.confirmed));
    });

    test('concurrent createAttemptIfAbsent calls remain safe and idempotent', () async {
      final results = await Future.wait([
        repository.createAttemptIfAbsent(
          sessionId: 's_concurrent_att',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 300,
          attemptedAt: fixedTime,
        ),
        repository.createAttemptIfAbsent(
          sessionId: 's_concurrent_att',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 300,
          attemptedAt: fixedTime,
        ),
        repository.createAttemptIfAbsent(
          sessionId: 's_concurrent_att',
          targetPackage: ChannelConstants.targetYouTube,
          durationSeconds: 300,
          attemptedAt: fixedTime,
        ),
      ]);

      expect(results.length, equals(3));
      for (final r in results) {
        expect(r.sessionId, equals('s_concurrent_att'));
        expect(r.state, equals(AccessAttemptState.prepared));
      }
    });

    test('getRecentAttempts returns attempts in descending order of attemptedAt', () async {
      await repository.createAttemptIfAbsent(
        sessionId: 'session_old',
        targetPackage: ChannelConstants.targetYouTube,
        durationSeconds: 300,
        attemptedAt: fixedTime.subtract(const Duration(hours: 2)),
      );
      await repository.createAttemptIfAbsent(
        sessionId: 'session_new',
        targetPackage: ChannelConstants.targetInstagram,
        durationSeconds: 300,
        attemptedAt: fixedTime,
      );

      final recent = await repository.getRecentAttempts(limit: 10);
      expect(recent.length, greaterThanOrEqualTo(2));
      expect(recent.first.sessionId, equals('session_new'));
      expect(recent.first.targetPackage, equals(ChannelConstants.targetInstagram));
    });
  });
}
