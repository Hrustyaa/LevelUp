import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/data/android_app_catalog.dart';
import 'package:levelup_test/screens/levelup_app_selection_screen.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';
import 'package:material_ui/material_ui.dart';

const _apps = [
  SelectableApp(
    packageId: 'test.tiktok',
    name: 'TikTok',
    suggested: true,
    category: AppCategory.social,
  ),
  SelectableApp(
    packageId: 'test.instagram',
    name: 'Instagram',
    suggested: true,
    category: AppCategory.social,
  ),
  SelectableApp(
    packageId: 'test.youtube',
    name: 'YouTube',
    suggested: true,
    category: AppCategory.entertainment,
  ),
];

const _continue = ValueKey('continue');
const _skip = ValueKey('skip');

Widget _page({
  AppLoader? load,
  LevelUpLanguage language = LevelUpLanguage.en,
  Set<String> initial = const {},
  ValueChanged<Set<String>>? next,
  ValueChanged<Set<String>>? onSelectionChanged,
  VoidCallback? skip,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LevelUpAppSelectionScreen(
      loadApps: load ?? () async => _apps,
      language: language,
      initialSelectedIds: initial,
      onSelectionChanged: onSelectionChanged,
      onContinue: next ?? (_) {},
      onSkip: skip ?? () {},
      onBack: () {},
    ),
  );
}

void main() {
  testWidgets('selection starts empty and filtering retains selected IDs', (
    tester,
  ) async {
    Set<String>? result;
    await tester.pumpWidget(_page(next: (ids) => result = ids));
    await tester.pumpAndSettle();

    final button = find.byKey(_continue);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.text('0 selected'), findsOneWidget);

    final first = find.byKey(const ValueKey('test.tiktok'));
    expect(
      tester.widget<AnimatedContainer>(first).duration,
      const Duration(milliseconds: 160),
    );
    await tester.tap(find.text('TikTok'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'INSTAGRAM');
    await tester.pumpAndSettle();
    expect(find.text('TikTok'), findsNothing);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Instagram'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(button);
    expect(result, {'test.tiktok', 'test.instagram'});
  });

  testWidgets(
    'search shows an empty result and can be cleared via icon or button',
    (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No matching apps.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Clear search'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('TikTok'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('TikTok'), findsOneWidget);
    },
  );

  testWidgets('an empty installed catalog clears a stale draft', (
    tester,
  ) async {
    Set<String>? draft;
    var skipped = false;
    await tester.pumpWidget(
      _page(
        load: () async => const [],
        initial: {'not.installed'},
        onSelectionChanged: (ids) => draft = ids,
        skip: () => skipped = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(draft, isEmpty);
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('No supported apps found.'), findsOneWidget);
    expect(find.text('YouTube'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(_continue)).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(_skip));
    expect(skipped, isTrue);
  });

  testWidgets('catalog errors have a retry action', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _page(
        load: () async {
          if (++attempts == 1) throw StateError('Catalog unavailable');
          return _apps;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load apps.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('TikTok'), findsOneWidget);
  });

  for (final (viewport, language, step, skip) in [
    (const Size(360, 640), LevelUpLanguage.ru, 'ШАГ 1 ИЗ 3', 'Пока пропустить'),
    (
      const Size(412, 891),
      LevelUpLanguage.kk,
      '1-ҚАДАМ / 3',
      'Әзірге өткізіп жіберу',
    ),
  ]) {
    testWidgets(
      'selection fits ${viewport.width} dp with 180% text and keyboard',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetViewInsets);

        await tester.pumpWidget(_page(language: language, textScale: 1.8));
        await tester.pumpAndSettle();
        expect(find.text(step), findsOneWidget);
        expect(find.text(skip), findsOneWidget);

        final search = find.byType(TextField);
        await tester.scrollUntilVisible(
          search,
          100,
          scrollable: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        );
        await tester.pumpAndSettle();
        expect(search.hitTestable(), findsOneWidget);
        await tester.tap(search);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);

        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(find.byKey(_continue), findsNothing);
        await tester.ensureVisible(search);
        await tester.enterText(search, 'Tik');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        FocusManager.instance.primaryFocus?.unfocus();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.byKey(_continue), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
