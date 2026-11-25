import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/dashboard_data.dart';
import 'package:levelup_test/free_workout/workout_history.dart';
import 'package:levelup_test/free_workout/workout_session.dart';
import 'package:levelup_test/progress/progress_chart.dart';
import 'package:levelup_test/progress/progress_models.dart';
import 'package:levelup_test/progress/progress_repository.dart';
import 'package:levelup_test/progress/progress_tab.dart';
import 'package:levelup_test/screens/levelup_home_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutResult workoutAt(DateTime ended, List<int> sets) => WorkoutResult(
  exercise: 'squat',
  startedAt: ended.subtract(const Duration(minutes: 4, seconds: 22)),
  endedAt: ended,
  sets: sets,
);

class _TestProgressRepository implements ProgressRepository {
  List<WorkoutResult> workouts = [];
  FocusUsageRead usage = const FocusUsageRead(
    FocusUsageStatus.permissionDenied,
  );
  bool workoutError = false;
  bool usageError = false;

  @override
  Future<List<WorkoutResult>> loadWorkouts() async {
    if (workoutError) throw StateError('cannot read workouts');
    return workouts;
  }

  @override
  Future<FocusUsageRead> loadFocusUsage(
    Set<String> packageIds,
    DateTime now,
  ) async {
    if (usageError) throw StateError('cannot read usage');
    return usage;
  }
}

class _InactiveFocus implements DashboardFocusGateway {
  const _InactiveFocus();

  @override
  Future<FocusSnapshot> read() async =>
      const FocusSnapshot(enabled: false, serviceEnabled: false);

  @override
  Future<void> enable({String? target}) async {}

  @override
  Future<void> disable() async {}
}

Widget _host(
  _TestProgressRepository repo, {
  Future<void> Function()? onPermissions,
  double textScale = 1,
  String language = 'ru',
}) => MaterialApp(
  theme: ThemeData.dark(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: ListView(
      children: [
        LevelUpProgressTab(
          trackedPackageIds: const {'com.google.android.youtube'},
          language: language,
          repository: repo,
          onOpenUsagePermissions: onPermissions,
        ),
      ],
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const usageChannel = MethodChannel('levelup/usage');
  const permissionsChannel = MethodChannel('levelup/permissions');

  testWidgets('shows workouts, opens grouped history and details', (
    tester,
  ) async {
    final now = DateTime.now();
    final repo = _TestProgressRepository()
      ..workouts = [
        workoutAt(now.subtract(const Duration(minutes: 4)), [12, 9]),
        workoutAt(now.subtract(const Duration(days: 1, minutes: 4)), [7]),
      ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('28'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('progress_period_30')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ProgressChart>(find.byType(ProgressChart)).points,
      hasLength(30),
    );

    final open = find.byKey(const ValueKey('progress_open_history'));
    await tester.scrollUntilVisible(open, 200);
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workout_exercise_filter')));
    await tester.pumpAndSettle();
    expect(find.text('Отжимания'), findsNothing);
    await tester.tap(find.text('Приседания').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Приседания').at(1));
    await tester.pumpAndSettle();
    expect(find.text('Подход 1'), findsOneWidget);
    expect(find.text('12 повторений'), findsOneWidget);
    expect(find.text('9 повторений'), findsOneWidget);
    expect(find.text('Продолжительность · 4 мин 22 с'), findsOneWidget);
  });

  testWidgets('display distinguishes empty history and read errors', (
    tester,
  ) async {
    final repo = _TestProgressRepository()..workoutError = true;
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить тренировки'), findsOneWidget);
    expect(find.text('Пока нет тренировок'), findsNothing);
    repo.workoutError = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет тренировок'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets(
    'Focus reports absent Usage Access and refreshes after settings',
    (tester) async {
      final repo = _TestProgressRepository();
      await tester.pumpWidget(
        _host(
          repo,
          onPermissions: () async {
            final today = localDay(DateTime.now());
            repo.usage = FocusUsageRead.ready(
              FocusUsageSnapshot.fromNative({
                'week': [
                  {
                    'dateMs': today.millisecondsSinceEpoch,
                    'durationMs': 181500,
                  },
                ],
              }, now: today),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('progress_section_focus')));
      await tester.pumpAndSettle();
      expect(
        find.text('Нет доступа к статистике использования Android.'),
        findsOneWidget,
      );
      expect(
        find.text('История разблокировок пока недоступна'),
        findsOneWidget,
      );
      expect(find.text('30 дней'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('progress_open_usage_permissions')),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 мин 1 с'), findsOneWidget);
      expect(find.text('Экранное время выбранных приложений'), findsOneWidget);
      expect(
        tester
            .widget<ProgressChart>(find.byType(ProgressChart))
            .points
            .first
            .value,
        isNull,
      );
    },
  );

  testWidgets('a Focus read failure leaves workout results available', (
    tester,
  ) async {
    final repo = _TestProgressRepository()
      ..usageError = true
      ..workouts = [
        workoutAt(DateTime.now().subtract(const Duration(minutes: 2)), [12]),
      ];
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('progress_section_focus')));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить экранное время'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('progress_section_workouts')));
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('re-entering dashboard Progress sees a newly saved workout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: LevelUpHomeScreen(
          gateway: _InactiveFocus(),
          language: DashboardLanguage.en,
          logoAsset: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final progress = find.byKey(const ValueKey('tab_3'));
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(find.text('No workouts yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab_2')));
    await tester.pumpAndSettle();
    final history = WorkoutHistory(await SharedPreferences.getInstance());
    expect(
      await history.add(
        workoutAt(DateTime.now().subtract(const Duration(minutes: 1)), [13, 6]),
      ),
      isTrue,
    );
    await tester.tap(progress);
    await tester.pumpAndSettle();
    expect(find.text('No workouts yet'), findsNothing);
    expect(find.text('19'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('charts fit a 320 dp viewport at double text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final today = localDay(DateTime.now());
    final repo = _TestProgressRepository()
      ..workouts = [
        workoutAt(DateTime.now().subtract(const Duration(minutes: 5)), [12, 3]),
      ]
      ..usage = FocusUsageRead.ready(
        FocusUsageSnapshot.fromNative({
          'week': [
            {'dateMs': today.millisecondsSinceEpoch, 'durationMs': 3600000},
          ],
        }, now: today),
      );
    await tester.pumpWidget(_host(repo, textScale: 2, language: 'kk'));
    await tester.pumpAndSettle();
    expect(find.text('Жаттығулар'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('progress_period_30')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('progress_section_focus')));
    await tester.pumpAndSettle();
    expect(find.text('1 сағ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('reads valid stored records alongside corrupt records', () async {
    SharedPreferences.setMockInitialValues({
      WorkoutHistory.key: [
        'not JSON',
        '{"exercise":"squat","startedAt":"2026-11-23","endedAt":"2026-11-24","sets":[2,"x"]}',
        jsonEncode(
          workoutAt(DateTime.now().subtract(const Duration(minutes: 2)), [
            12,
            10,
          ]).toJson(),
        ),
      ],
    });
    final records = await const LocalProgressRepository().loadWorkouts();
    expect(records.single.totalReps, 22);
  });

  test(
    'native query distinguishes denial, missing bridge, and platform error',
    () async {
      addTearDown(() {
        messenger.setMockMethodCallHandler(usageChannel, null);
        messenger.setMockMethodCallHandler(permissionsChannel, null);
      });
      const repo = LocalProgressRepository();
      final now = DateTime.now();
      const apps = {'com.google.android.youtube'};
      final missing = await repo.loadFocusUsage(apps, now);
      expect(missing.status, FocusUsageStatus.unavailable);

      messenger.setMockMethodCallHandler(usageChannel, (call) async {
        expect(call.method, 'getScreenTime');
        expect(call.arguments, {'packageIds': apps.toList()});
        return null;
      });
      messenger.setMockMethodCallHandler(
        permissionsChannel,
        (_) async => {'usage': 'denied'},
      );
      expect(
        (await repo.loadFocusUsage(apps, now)).status,
        FocusUsageStatus.permissionDenied,
      );
      messenger.setMockMethodCallHandler(
        permissionsChannel,
        (_) async => {'usage': 'granted'},
      );
      expect(
        (await repo.loadFocusUsage(apps, now)).status,
        FocusUsageStatus.noData,
      );
      messenger.setMockMethodCallHandler(usageChannel, (_) async {
        throw PlatformException(code: 'USAGE_UNAVAILABLE');
      });
      await expectLater(
        repo.loadFocusUsage(apps, now),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
