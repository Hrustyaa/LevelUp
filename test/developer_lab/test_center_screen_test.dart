import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/models/diagnostic_event.dart';
import 'package:levelup_test/features/developer_lab/screens/test_center_screen.dart';
import 'package:levelup_test/features/developer_lab/test_center/models/test_scenario.dart';
import 'package:levelup_test/features/developer_lab/test_center/services/test_scenario_runner.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String dbPath;
  late LevelUpDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('test_center_test_');
    dbPath = p.join(tempDir.path, 'test_center.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
    await database.database;
  });

  tearDown(() async {
    database.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Widget createTestWidget(DevLabController controller) {
    return DevLabScope(
      notifier: controller,
      child: MaterialApp(
        theme: DevLabTheme.theme,
        home: const TestCenterScreen(),
      ),
    );
  }

  group('Screen 6 — TestCenterScreen Tests', () {
    testWidgets('1. Renders all 8 backend module sections and summary counters', (tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(createTestWidget(controller));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Diagnostics & Test Center'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('PASS'), findsAtLeastNWidgets(1));
      expect(find.text('FAIL'), findsAtLeastNWidgets(1));
      expect(find.text('BLOCKED'), findsAtLeastNWidgets(1));
      expect(find.text('NOT RUN'), findsAtLeastNWidgets(1));

      // Verify all 8 backend modules exist
      expect(find.text('Native Bridge'), findsAtLeastNWidgets(1));
      expect(find.text('Focus Engine'), findsAtLeastNWidgets(1));
      expect(find.text('Challenge Engine'), findsAtLeastNWidgets(1));
      expect(find.text('Pose Engine'), findsAtLeastNWidgets(1));
      expect(find.text('Session Manager'), findsAtLeastNWidgets(1));
      expect(find.text('Access Engine'), findsAtLeastNWidgets(1));
      expect(find.text('Local Database'), findsAtLeastNWidgets(1));
      expect(find.text('Coordinator'), findsAtLeastNWidgets(1));

      controller.dispose();
    });

    testWidgets('2. Executes isolated in-app scenario and transitions status to PASS', (tester) async {
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      final runner = TestScenarioRunner(controller);
      final catalogScenario = runner.scenarios.firstWhere((s) => s.id == 'M03_ISOLATED_CATALOG');

      expect(catalogScenario.status, equals(TestRunStatus.notRun));

      await runner.runScenario(catalogScenario);

      expect(catalogScenario.status, equals(TestRunStatus.pass));
      expect(catalogScenario.outputMessage, contains('Unlock (5 reps = 300s)'));
      expect(catalogScenario.durationMs, isNotNull);

      // Verify diagnostic event was logged
      final logs = controller.logService.events;
      expect(logs.any((e) => e.message.contains('M03_ISOLATED_CATALOG')), isTrue);

      controller.dispose();
    });

    testWidgets('3. Isolation guarantee: isolated scenario does not invoke real bridge or touch real database', (tester) async {
      final realBridge = SimulationBridge(); // Stand-in for real bridge call tracker
      final controller = DevLabController(
        initialMode: DevExecutionMode.realDevice,
        customBridge: realBridge,
        customDatabase: database,
      );

      final runner = TestScenarioRunner(controller);
      final coordScenario = runner.scenarios.firstWhere((s) => s.id == 'COORD_ISOLATED_FULL_WORKFLOW');

      await tester.runAsync(() async {
        await runner.runScenario(coordScenario);
      });

      expect(coordScenario.status, equals(TestRunStatus.pass));

      // Invariant: The isolated scenario created its own sandbox database and simulation bridge.
      // The real bridge callLog must NOT contain any grantAccess calls!
      expect(realBridge.callLog.where((c) => c.startsWith('grantAccess')), isEmpty);

      // Invariant: The real database must remain completely clean!
      int? countInRealDb;
      await tester.runAsync(() async {
        countInRealDb = await controller.workoutHistoryRepository.countCompletedWorkouts();
      });
      expect(countInRealDb, equals(0));

      controller.dispose();
    });

    testWidgets('4. Category D manual checklist requires explicit human verification toggle', (tester) async {
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      final runner = TestScenarioRunner(controller);
      final checklistItem = runner.scenarios.firstWhere((s) => s.id == 'MANUAL_OVERLAY_LATCH');

      expect(checklistItem.status, equals(TestRunStatus.notRun));
      expect(checklistItem.executionType, equals(TestExecutionType.manualChecklist));
      expect(checklistItem.action, isNull); // Never auto-executable by software

      // Human tester marks verified
      runner.toggleChecklistPass(checklistItem);
      expect(checklistItem.status, equals(TestRunStatus.pass));
      expect(checklistItem.outputMessage, contains('Verified manually on physical device'));

      // Human tester toggles off
      runner.toggleChecklistPass(checklistItem);
      expect(checklistItem.status, equals(TestRunStatus.notRun));

      controller.dispose();
    });

    testWidgets('5. Filters scenarios by execution type chip', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      await tester.pumpWidget(createTestWidget(controller));
      await tester.pumpAndSettle();

      // Tap 'D. Manual Device Checklist' filter chip
      await tester.ensureVisible(find.text('D. Manual Device Checklist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('D. Manual Device Checklist'));
      await tester.pumpAndSettle();

      expect(find.text('Target Launch Shows Latched Overlay'), findsOneWidget);
      expect(find.text('Platform Availability Probe'), findsNothing);

      controller.dispose();
    });

    testWidgets('6. Diagnostic log service exports filtered logs', (tester) async {
      final controller = DevLabController(
        initialMode: DevExecutionMode.simulation,
        customBridge: SimulationBridge(),
        customDatabase: database,
      );

      controller.logService.info(BackendModuleId.accessEngine, 'Test access event', 'detail_1', 'session_123');
      controller.logService.error(BackendModuleId.localDatabase, 'Test error event', 'detail_err');

      final exportedAll = controller.logService.exportLogs();
      expect(exportedAll, contains('Test access event'));
      expect(exportedAll, contains('Test error event'));
      expect(exportedAll, contains('(sid: session_123)'));

      final exportedFiltered = controller.logService.exportLogs(
        module: BackendModuleId.accessEngine,
      );
      expect(exportedFiltered, contains('Test access event'));
      expect(exportedFiltered, isNot(contains('Test error event')));

      controller.dispose();
    });
  });
}
