import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/core/constants/channel_constants.dart';
import 'package:levelup_test/data/database/levelup_database.dart';
import 'package:levelup_test/features/developer_lab/di/dev_lab_scope.dart';
import 'package:levelup_test/features/developer_lab/models/dev_mode.dart';
import 'package:levelup_test/features/developer_lab/screens/preflight_focus_screen.dart';
import 'package:levelup_test/features/developer_lab/theme/dev_lab_theme.dart';
import 'package:levelup_test/models/native_access_status.dart';
import 'package:levelup_test/models/native_focus_status.dart';
import 'package:levelup_test/models/native_permission_status.dart';
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
    tempDir = await Directory.systemTemp.createTemp('preflight_focus_test_');
    dbPath = p.join(tempDir.path, 'preflight.db');
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

  Widget createTestWidget(DevLabController controller) {
    return DevLabScope(
      notifier: controller,
      child: MaterialApp(
        theme: DevLabTheme.theme,
        home: const PreflightFocusScreen(),
      ),
    );
  }

  testWidgets('PreflightFocusScreen renders prerequisites and allows focus toggle', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final bridge = SimulationBridge(
      initialStatus: const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: true),
        accessStatus: NativeAccessStatus(),
      ),
    );

    final controller = DevLabController(
      initialMode: DevExecutionMode.simulation,
      customBridge: bridge,
      customDatabase: database,
    );

    await tester.runAsync(() async {
      await controller.refreshAll();
    });

    await tester.pumpWidget(createTestWidget(controller));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Verify Title & Sections
    expect(find.text('PREFLIGHT & FOCUS'), findsOneWidget);
    expect(find.text('Hardware & OS Prerequisites'), findsOneWidget);
    expect(find.text('Voluntary Focus Gating'), findsOneWidget);
    expect(find.text('Restricted Target Application'), findsOneWidget);

    // Verify Target Options
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);

    // Verify Single-Target Contract Notice
    expect(find.text('Single-Target Restriction Contract'), findsOneWidget);

    // Test Toggling Focus On
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(switchFinder);
      // Wait for focusService and refreshAll to finish
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(bridge.status.isGateEnabled, isTrue);

    // Test Selecting Instagram Target
    await tester.runAsync(() async {
      await tester.tap(find.text('Instagram'));
      // Wait for focusService and refreshAll to finish
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(bridge.status.targetPackage, equals(ChannelConstants.targetInstagram));

    controller.dispose();
  });

  testWidgets('PreflightFocusScreen warns when enabling focus without accessibility permission', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final bridge = SimulationBridge(
      initialStatus: const NativeFocusStatus(
        targetPackage: ChannelConstants.targetYouTube,
        isGateEnabled: false,
        permissionStatus: NativePermissionStatus(isAccessibilityGranted: false),
        accessStatus: NativeAccessStatus(),
      ),
    );

    final controller = DevLabController(
      initialMode: DevExecutionMode.simulation,
      customBridge: bridge,
      customDatabase: database,
    );

    await tester.runAsync(() async {
      await controller.refreshAll();
    });

    await tester.pumpWidget(createTestWidget(controller));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    await tester.runAsync(() async {
      await tester.tap(switchFinder);
      await Future.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(
      find.text('Accessibility permission required before enabling restriction.'),
      findsOneWidget,
    );

    controller.dispose();
  });
}
