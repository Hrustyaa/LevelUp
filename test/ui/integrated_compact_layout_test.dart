import 'package:flutter_test/flutter_test.dart';
import 'package:levelup_test/focus_v2/focus_v2_models.dart';
import 'package:levelup_test/focus_v2/focus_v2_screens.dart';
import 'package:levelup_test/free_workout/workout_challenge_tab.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const target = FocusTarget(
    packageName: 'com.instagram.android',
    appName: 'Instagram',
  );
  final screens = <String, Widget Function(String)>{
    'workout exercise selection': (language) =>
        WorkoutDetailsScreen(language: language),
    'camera controls': (language) => FocusV2CameraScreen(
      cameraPreview: const ColoredBox(color: Colors.black),
      repetitions: 4,
      poseDetected: true,
      language: language,
      exerciseName: 'Қолды бүгіп-жазу',
      status:
          'Keep your full body visible and hold the lower position briefly.',
      onCancel: () {},
    ),
    'unlock confirmation': (language) => FocusV2SuccessScreen(
      target: target,
      accessMinutes: 5,
      language: language,
      onOpenApp: () {},
    ),
    'camera error recovery': (language) => FocusV2ErrorScreen(
      message:
          'Camera access is denied. Open app settings to allow camera access.',
      language: language,
      onRetry: () {},
      onCancel: () {},
    ),
  };

  for (final entry in screens.entries) {
    testWidgets(
      '${entry.key} fits a compact viewport with large text in EN, RU and KK',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final language in ['en', 'ru', 'kk']) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(language),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: entry.value(language),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: language);
        }
      },
    );
  }
}
