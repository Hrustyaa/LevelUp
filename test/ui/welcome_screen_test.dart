import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/main_ui.dart';
import 'package:levelup_test/screens/levelup_welcome_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _start = Key('welcome_get_started');
const _how = Key('welcome_how_it_works');

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target, warnIfMissed: true);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('compact Welcome keeps language controls and CTA visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 759);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    LevelUpLanguage? startedWith;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(top: 24, bottom: 24)),
          child: child!,
        ),
        home: LevelUpWelcomeScreen(
          onGetStarted: (language) => startedWith = language,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final start = find.byKey(_start);
    final brand = find.text('LevelUp');
    final kazakh = find.byKey(const Key('welcome_language_KZ'));
    expect(tester.getTopRight(kazakh).dx, closeTo(336, 1));
    expect(
      tester.getBottomLeft(kazakh).dy,
      lessThan(tester.getTopLeft(brand).dy),
    );

    for (final (label, language) in [
      ('EN', LevelUpLanguage.en),
      ('RU', LevelUpLanguage.ru),
      ('KZ', LevelUpLanguage.kk),
    ]) {
      final option = find.byKey(Key('welcome_language_$label'));
      expect(option.hitTestable(), findsOneWidget);
      await tester.tap(option);
      await tester.pumpAndSettle();

      final body = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(body.position.pixels, 0);
      expect(start.hitTestable(), findsOneWidget);
      await tester.tap(start);
      expect(startedWith, language);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('language selection localizes the screen and explanation', (
    tester,
  ) async {
    LevelUpLanguage? startedWith;
    final selected = <LevelUpLanguage>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LevelUpWelcomeScreen(
          onGetStarted: (language) => startedWith = language,
          onLanguageChanged: selected.add,
        ),
      ),
    );

    expect(find.text('Get started'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('welcome_language_RU')));
    expect(find.text('Начать'), findsOneWidget);
    expect(find.text('Выбери приложения'), findsOneWidget);
    expect(find.text('Сделай 5 приседаний'), findsOneWidget);
    expect(find.text('Получи 5 минут'), findsOneWidget);
    expect(find.text('Задание можно пропустить.'), findsOneWidget);

    await _tapVisible(tester, find.byKey(_how));
    expect(
      find.text('После 5 приседаний приложение откроется на 5 минут.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Чтобы сделать паузу, выключи фокус. Ты сам решаешь, когда включить его снова.',
      ),
      findsOneWidget,
    );
    await _tapVisible(tester, find.text('Понятно'));
    expect(find.text('Понятно'), findsNothing);

    await _tapVisible(tester, find.byKey(const Key('welcome_language_KZ')));
    expect(find.text('Бастау'), findsOneWidget);
    expect(find.text('Телефонға аз уақыт.\nӨмірге көп уақыт.'), findsOneWidget);
    expect(find.text('Бұл қалай жұмыс істейді?'), findsOneWidget);
    await _tapVisible(tester, find.byKey(_start));
    expect(startedWith, LevelUpLanguage.kk);

    await _tapVisible(tester, find.byKey(const Key('welcome_language_EN')));
    expect(find.text('Get started'), findsOneWidget);
    expect(selected, [
      LevelUpLanguage.ru,
      LevelUpLanguage.kk,
      LevelUpLanguage.en,
    ]);
  });

  testWidgets('Welcome restores the saved language after an app restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(const LevelUpIntroDemo());
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
    await _tapVisible(tester, find.byKey(const Key('welcome_language_KZ')));
    expect(find.text('Бастау'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();

    await tester.pumpWidget(const LevelUpIntroDemo());
    await tester.pumpAndSettle();
    expect(find.text('Бастау'), findsOneWidget);
    expect(find.text('Бұл қалай жұмыс істейді?'), findsOneWidget);
  });

  for (final viewport in [const Size(360, 640), const Size(412, 891)]) {
    testWidgets('Welcome fits ${viewport.width} dp with large text', (
      tester,
    ) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      LevelUpLanguage? startedWith;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.8),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: child!,
          ),
          home: LevelUpWelcomeScreen(
            initialLanguage: LevelUpLanguage.kk,
            onGetStarted: (language) => startedWith = language,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, find.byKey(_start));
      expect(startedWith, LevelUpLanguage.kk);
      await _tapVisible(tester, find.byKey(_how));
      expect(
        find.text('5 рет отырып-тұрсаң, қолданба 5 минутқа ашылады.'),
        findsOneWidget,
      );
      expect(find.text('Түсінікті'), findsOneWidget);
      await _tapVisible(tester, find.text('Түсінікті'));
      expect(find.text('Түсінікті'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
