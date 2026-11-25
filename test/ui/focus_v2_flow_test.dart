import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:levelup_test/focus_v2/focus_frame_limiter.dart';
import 'package:levelup_test/focus_v2/focus_v2_flow.dart';
import 'package:levelup_test/focus_v2/focus_v2_models.dart';

void main() {
  const target = FocusTarget(
    packageName: 'com.example.target',
    appName: 'TestApp',
  );

  test(
    'requires future native confirmation rather than detector goal alone',
    () {
      final now = DateTime(2026, 11, 25, 12);
      expect(const VerifiedFocusGrant(granted: true).isConfirmedAt(now), false);
      expect(
        VerifiedFocusGrant(
          granted: false,
          accessUntil: now.add(const Duration(minutes: 5)),
        ).isConfirmedAt(now),
        false,
      );
      expect(
        VerifiedFocusGrant(
          granted: true,
          accessUntil: now.subtract(const Duration(seconds: 1)),
        ).isConfirmedAt(now),
        false,
      );
      expect(
        VerifiedFocusGrant(
          granted: true,
          accessUntil: now.add(const Duration(minutes: 5)),
        ).isConfirmedAt(now),
        true,
      );
    },
  );

  test('camera limiter never processes concurrent frames', () async {
    final ready = Completer<void>();
    final limiter = FocusFrameLimiter(minimumSpacing: Duration.zero);
    final first = limiter.submit((_) async => ready.future);
    expect(limiter.busy, true);
    expect(await limiter.submit((_) async {}), false);
    limiter.invalidate();
    expect(limiter.isCurrent(0), false);
    ready.complete();
    expect(await first, true);
    expect(limiter.busy, false);
  });

  testWidgets('Focus flow uses verified grant before success', (tester) async {
    ValueChanged<FocusPoseReading>? report;
    final grant = Completer<VerifiedFocusGrant>();
    var grantCalls = 0;
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: FocusExperienceV2(
          target: target,
          language: 'ru',
          cameraBuilder: (_, callback) {
            report = callback;
            return const ColoredBox(color: Colors.black);
          },
          requestVerifiedAccess: (_) async {
            grantCalls++;
            return grant.future;
          },
          openTarget: (_) async => opened = true,
          exitFlow: () {},
        ),
      ),
    );

    expect(find.text('TestApp на паузе'), findsOneWidget);
    expect(find.text('Начать задание'), findsOneWidget);
    await tester.tap(find.text('Начать задание'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
    report!(const FocusPoseReading(repetitions: 5, poseDetected: true));
    await tester.pump();
    expect(grantCalls, 1);
    expect(find.text('Готово'), findsNothing);

    grant.complete(
      VerifiedFocusGrant(
        granted: true,
        accessUntil: DateTime.now().add(const Duration(minutes: 5)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsOneWidget);
    await tester.tap(find.text('Открыть TestApp'));
    await tester.pump();
    expect(opened, true);
  });

  testWidgets('Native rejection never shows success', (tester) async {
    ValueChanged<FocusPoseReading>? report;
    await tester.pumpWidget(
      MaterialApp(
        home: FocusExperienceV2(
          target: target,
          language: 'ru',
          cameraBuilder: (_, callback) {
            report = callback;
            return const ColoredBox(color: Colors.black);
          },
          requestVerifiedAccess: (_) async =>
              const VerifiedFocusGrant(granted: false),
          openTarget: (_) async {},
          exitFlow: () {},
        ),
      ),
    );
    await tester.tap(find.text('Начать задание'));
    await tester.pump();
    report!(const FocusPoseReading(repetitions: 5, poseDetected: true));
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsNothing);
    expect(find.text('Повторить'), findsOneWidget);
  });
}
