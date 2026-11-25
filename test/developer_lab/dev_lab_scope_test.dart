import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/models/diagnostic_event.dart';
import 'package:levelup_test/features/developer_lab/models/module_status.dart';
import 'package:levelup_test/features/developer_lab/services/dev_lab_log_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('DevLabLogService Unit Tests', () {
    test('buffers events up to maximum capacity and discards oldest', () {
      final logService = DevLabLogService(maxEvents: 5);

      for (int i = 1; i <= 7; i++) {
        logService.info(BackendModuleId.developerLab, 'Event $i');
      }

      final events = logService.events;
      expect(events.length, equals(5));
      expect(events.first.message, equals('Event 3'));
      expect(events.last.message, equals('Event 7'));
    });

    test('exports formatted log text containing all buffered events', () {
      final logService = DevLabLogService();
      logService.info(BackendModuleId.nativeBridge, 'Bridge connected');
      logService.warning(BackendModuleId.focusEngine, 'Permission missing');
      logService.error(BackendModuleId.localDatabase, 'Table query error');
      logService.success(BackendModuleId.sessionManager, '5 reps completed');

      final export = logService.exportLogs();
      expect(export, contains('=== LevelUp Developer Lab Diagnostic Log ==='));
      expect(export, contains('[INFO   ] [Native Bridge   ] Bridge connected'));
      expect(export, contains('[WARNING] [Focus Engine    ] Permission missing'));
      expect(export, contains('[ERROR  ] [Local Database  ] Table query error'));
      expect(export, contains('[SUCCESS] [Session Manager ] 5 reps completed'));
    });
  });

  group('SimulationBridge Unit Tests', () {
    test('updates target package and clears unlock until', () async {
      final bridge = SimulationBridge();
      expect(bridge.status.targetPackage, equals(ChannelConstants.targetYouTube));

      final success = await bridge.setTarget(ChannelConstants.targetInstagram);
      expect(success, isTrue);
      expect(bridge.status.targetPackage, equals(ChannelConstants.targetInstagram));
      expect(bridge.status.accessStatus.unlockUntil, isNull);
    });

    test('updates voluntary gate enabled state', () async {
      final bridge = SimulationBridge();
      await bridge.setEnabled(false);
      expect(bridge.status.isGateEnabled, isFalse);

      await bridge.setEnabled(true);
      expect(bridge.status.isGateEnabled, isTrue);
    });

    test('grantAccess computes future timestamp and updates access status', () async {
      final bridge = SimulationBridge();
      final before = DateTime.now();
      final unlockUntil = await bridge.grantAccess(minutes: 5);

      expect(unlockUntil.isAfter(before), isTrue);
      expect(bridge.unlockTimestamp, equals(unlockUntil));
      expect(bridge.status.accessStatus.unlockUntil, equals(unlockUntil));

      await bridge.resetAccess();
      expect(bridge.status.accessStatus.unlockUntil, isNull);
    });

    test('consumeChallengeRequest returns true once and resets to false', () async {
      final bridge = SimulationBridge(challengeRequested: true);

      final first = await bridge.consumeChallengeRequest();
      expect(first, isTrue);

      final second = await bridge.consumeChallengeRequest();
      expect(second, isFalse);
    });
  });

  group('DevLabController Integration & State Tests', () {
    late Directory tempDir;
    late String dbPath;
    late LevelUpDatabase database;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('devlab_test_');
      dbPath = p.join(tempDir.path, 'devlab.db');
      database = LevelUpDatabase(
        databaseFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
    });

    tearDown(() async {
      await database.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('initializes all modules in Simulation mode', () async {
      final bridge = SimulationBridge(challengeRequested: false);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      expect(controller.executionMode, equals(DevExecutionMode.simulation));
      expect(controller.isInitializing, isTrue);

      await controller.refreshAll();

      expect(controller.isInitializing, isFalse);
      expect(controller.initError, isNull);
      expect(
        controller.moduleHealth[BackendModuleId.nativeBridge],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.focusEngine],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.challengeEngine],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.poseEngine],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.sessionManager],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.accessEngine],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.localDatabase],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.coordinator],
        equals(ModuleHealthStatus.ready),
      );
      expect(
        controller.moduleHealth[BackendModuleId.settingsEngine],
        equals(ModuleHealthStatus.ready),
      );

      controller.dispose();
    });

    test('refreshAll does NOT consume native challenge request flag', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      // Verify that refreshing module statuses does not eagerly consume the one-time flag
      await controller.refreshAll();
      expect(bridge.challengeRequested, isTrue);

      controller.dispose();
    });

    test('switchMode safely terminates active session and switches dependencies', () async {
      final bridge = SimulationBridge(challengeRequested: true);
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: bridge,
        customDatabase: database,
      );

      await controller.refreshAll();
      await controller.coordinator.launchFreeWorkout();

      expect(controller.coordinator.currentState.sessionStatus.name, equals('active'));

      // Switch mode while session is active
      await controller.switchMode(DevExecutionMode.realDevice);

      // Previous session must be terminated
      expect(controller.executionMode, equals(DevExecutionMode.realDevice));
      expect(controller.coordinator.currentState.sessionStatus.name, equals('created'));

      controller.dispose();
    });
  });
}
