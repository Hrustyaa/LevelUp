import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/screens/system_hub_screen.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late String dbPath;
  late LevelUpDatabase database;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('system_hub_test_');
    dbPath = p.join(tempDir.path, 'system_hub.db');
    database = LevelUpDatabase(
      databaseFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
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
        home: const SystemHubScreen(),
      ),
    );
  }

  testWidgets('SystemHubScreen renders all 7 module health rows and live snapshot', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final bridge = SimulationBridge();
    final controller = DevLabController(
      initialMode: DevExecutionMode.simulation,
      customBridge: bridge,
      customDatabase: database,
    );

    await tester.runAsync(() async {
      await controller.refreshAll();
    });

    await tester.pumpWidget(createTestWidget(controller));
    await tester.pumpAndSettle();

    // Verify Title and Mode Chip
    expect(find.text('SYSTEM HUB'), findsOneWidget);
    expect(find.text('Simulation'), findsOneWidget);

    // Verify System Snapshot Card
    expect(find.text('Live System Snapshot'), findsOneWidget);
    expect(find.text('Voluntary Focus Mode'), findsOneWidget);
    expect(find.text('Accessibility Permission'), findsOneWidget);
    expect(find.text('Selected Restricted App'), findsOneWidget);

    // Verify 7 Backend Engines in Module Integrity Matrix
    expect(find.text('Module Integrity Matrix'), findsOneWidget);
    expect(find.text('01 Native Bridge'), findsOneWidget);
    expect(find.text('02 Focus Engine'), findsOneWidget);
    expect(find.text('03 Challenge Engine'), findsOneWidget);
    expect(find.text('04 Pose Engine'), findsOneWidget);
    expect(find.text('05 Session Manager'), findsOneWidget);
    expect(find.text('06 Access Engine'), findsOneWidget);
    expect(find.text('07 Local Database'), findsOneWidget);
    expect(find.text('Integration Coordinator'), findsOneWidget);

    // Verify Navigation Actions for all screens
    expect(find.text('Preflight & Focus'), findsOneWidget);
    expect(find.text('Live Challenge'), findsOneWidget);
    expect(find.text('Workout Result'), findsOneWidget);
    expect(find.text('History & DB'), findsOneWidget);
    expect(find.text('Diagnostics & Test Center'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('SystemHubScreen launches unlock challenge through coordinator when Check & Launch is tapped', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final bridge = SimulationBridge(challengeRequested: true);
    final controller = DevLabController(
      initialMode: DevExecutionMode.simulation,
      customBridge: bridge,
      customDatabase: database,
    );

    await tester.runAsync(() async {
      await controller.refreshAll();
    });

    await tester.pumpWidget(createTestWidget(controller));
    await tester.pumpAndSettle();

    expect(find.text('Blocker Overlay Challenge'), findsOneWidget);
    expect(find.text('Check & Launch'), findsOneWidget);
    // Request must NOT be consumed yet on load
    expect(bridge.challengeRequested, isTrue);

    // Tap Check & Launch
    await tester.runAsync(() async {
      await tester.tap(find.text('Check & Launch'));
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Now request is consumed by coordinator
    expect(bridge.challengeRequested, isFalse);
    expect(controller.coordinator.currentState.sessionStatus.name, equals('active'));

    controller.dispose();
  });
}
