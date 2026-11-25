import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:levelup_test/onboarding_polish/levelup_welcome_polished.dart';
import 'package:levelup_test/ui_polish/levelup_setup_checklist.dart';
import 'package:levelup_test/ui_polish/levelup_ui.dart';

void main() {
  testWidgets('Welcome does not auto-enable Focus or skip setup', (
    tester,
  ) async {
    var continued = 0;
    String? changedLanguage;
    await tester.pumpWidget(
      MaterialApp(
        home: LevelUpWelcomePolishedScreen(
          language: 'ru',
          onLanguageChanged: (value) => changedLanguage = value,
          onContinue: () => continued++,
        ),
      ),
    );

    expect(continued, 0);
    expect(find.text('Начать'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('onboarding_language_kk')));
    await tester.tap(find.byKey(const Key('onboarding_language_kk')));
    expect(changedLanguage, 'kk');
    expect(continued, 0);
    await tester.ensureVisible(find.text('Начать'));
    await tester.tap(find.text('Начать'));
    expect(continued, 1);
  });

  testWidgets('How-it-works is dismissible without changing app state', (
    tester,
  ) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LevelUpWelcomePolishedScreen(
          language: 'en',
          onLanguageChanged: (_) {},
          onContinue: () => continued = true,
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('onboarding_how')));
    await tester.tap(find.byKey(const Key('onboarding_how')));
    await tester.pumpAndSettle();
    expect(find.text('How LevelUp works'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(continued, isFalse);
  });

  testWidgets('Setup checklist never invents a granted permission', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LevelUpSetupChecklist(
            language: 'ru',
            items: [
              LevelUpSetupItem(
                title: 'Usage Access',
                description: 'Android',
                icon: Icons.query_stats,
                status: LevelUpSetupStatus.unknown,
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Не проверено'), findsOneWidget);
    expect(find.text('Готово'), findsNothing);
    await tester.tap(find.text('Usage Access'));
    expect(taps, 1);
  });

  testWidgets('Empty state does not show action when not connected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LevelUpContentState(
            icon: Icons.history,
            title: 'Нет тренировок',
            message: 'Здесь появятся реальные результаты.',
            actionLabel: 'Открыть',
          ),
        ),
      ),
    );
    expect(find.text('Нет тренировок'), findsOneWidget);
    expect(find.text('Открыть'), findsNothing);
  });

  testWidgets('Confirm sheet dismisses without confirming', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await showLevelUpConfirmSheet(
                  context: context,
                  title: 'Выйти?',
                  message: 'Несохранённые данные будут потеряны.',
                  confirmLabel: 'Выйти',
                  cancelLabel: 'Отмена',
                  isDangerous: true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(answer, false);
  });

  testWidgets('Welcome on 320dp compact screen can scroll', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LevelUpWelcomePolishedScreen(
          language: 'kk',
          onLanguageChanged: (_) {},
          onContinue: () {},
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('onboarding_language_en')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
