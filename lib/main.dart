import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'main_ui.dart' as production;

const native = MethodChannel('levelup_test/control');
const accent = Color(0xFFC7FA5B);
const background = Color(0xFF11161A);

const testApps = <String, String>{
  'com.google.android.youtube': 'YouTube',
  'com.instagram.android': 'Instagram',
  'com.zhiliaoapp.musically': 'TikTok',
};

void main() => production.main();

class LevelUpApp extends StatelessWidget {
  const LevelUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LevelUp Test',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: background,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic> state = {};
  String? error;
  bool checking = true;
  bool openingChallenge = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await refresh();
      await checkChallengeRequest();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      refresh();
      checkChallengeRequest();
    }
  }

  Future<void> refresh() async {
    try {
      final raw = await native.invokeMapMethod<String, dynamic>('getState');
      if (!mounted) return;
      setState(() {
        state = raw ?? {};
        checking = false;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() { error = '$e'; checking = false; });
    }
  }

  Future<void> checkChallengeRequest() async {
    if (openingChallenge || !mounted) return;
    try {
      final requested = await native.invokeMethod<bool>('consumeChallengeRequest');
      if (requested == true && mounted) {
        await openChallenge();
      }
    } catch (_) {}
  }

  Future<void> openChallenge() async {
    if (openingChallenge || !mounted) return;
    openingChallenge = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ChallengeScreen()),
    );
    openingChallenge = false;
    if (mounted) await refresh();
  }

  Future<void> changeTarget(String selected) async {
    await native.invokeMethod('setTarget', {'target': selected});
    await refresh();
  }

  Future<void> setGate(bool enabled) async {
    if (enabled && state['serviceEnabled'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сначала включи сервис в настройках Android.')),
        );
      }
      return;
    }
    await native.invokeMethod('setEnabled', {'enabled': enabled});
    await refresh();
  }

  Future<void> resetAccess() async {
    await native.invokeMethod('resetAccess');
    await refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = state['target'] as String? ?? 'com.google.android.youtube';
    final enabled = state['enabled'] == true;
    final serviceEnabled = state['serviceEnabled'] == true;
    final unlockUntil = (state['unlockUntil'] as num? ?? 0).toInt();
    final remaining = DateTime.fromMillisecondsSinceEpoch(unlockUntil)
        .difference(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('LEVELUP / TEST'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Earn your screen time.',
                style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Тест на одном Android-телефоне. Без облака и загрузки видео.',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            _panel(
              title: '1. Выбери приложение для теста',
              child: DropdownButtonFormField<String>(
                initialValue: testApps.containsKey(selected) ? selected : testApps.keys.first,
                items: testApps.entries.map((entry) => DropdownMenuItem(
                  value: entry.key, child: Text(entry.value),
                )).toList(),
                onChanged: (value) { if (value != null) changeTarget(value); },
              ),
            ),
            _panel(
              title: '2. Доступ Android',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(serviceEnabled ? '✓ Accessibility Service включён' :
                    '○ Accessibility Service выключен',
                  style: TextStyle(color: serviceEnabled ? accent : Colors.orangeAccent)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => native.invokeMethod('openAccessibilitySettings'),
                  icon: const Icon(Icons.settings_accessibility),
                  label: const Text('Открыть спец. возможности'),
                ),
                const SizedBox(height: 6),
                const Text('Сервис видит только имя активного приложения. Включается вручную; можно отключить в настройках.',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
              ]),
            ),
            _panel(
              title: '3. Включи добровольное ограничение',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: setGate,
                title: Text(enabled ? 'Режим включён' : 'Режим выключен'),
                subtitle: const Text('Экран-барьер только для выбранного приложения'),
              ),
            ),
            _panel(
              title: '4. Проверка камеры и приседаний',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                FilledButton.icon(
                  onPressed: openChallenge,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Начать: 5 приседаний'),
                ),
                const SizedBox(height: 10),
                const Text('Зачёт только после цикла: стоя → вниз → стоя. Телефон поставь устойчиво, чтобы были видны бедро, колено и стопа.',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            _panel(
              title: 'Текущий доступ',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(remaining.isNegative || remaining.inSeconds <= 0
                    ? 'Время разблокировки истекло'
                    : 'Разблокировано ещё примерно на ${remaining.inMinutes + 1} мин.'),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: resetAccess, child: const Text('Сбросить доступ для теста')),
              ]),
            ),
            if (checking) const LinearProgressIndicator(),
            if (error != null) Text('Ошибка: $error', style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            const Text('Важно: это исследовательский soft blocker. Он не гарантирует защиту от обхода или стабильную работу на всех устройствах. Можно безопасно выключить ограничение.',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}

Widget _panel({required String title, required Widget child}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1D252A),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      child,
    ]),
  );
}

class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});
  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> with WidgetsBindingObserver {
  CameraController? controller;
  CameraDescription? cameraDescription;
  late final PoseDetector poseDetector;
  bool busy = false;
  bool finished = false;
  int reps = 0;
  int consecutiveDown = 0;
  int consecutiveUp = 0;
  String phase = 'up';
  String message = 'Подготовка камеры...';
  String? error;
  double? kneeAngle;
  static const goal = 5;

  final orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    poseDetector = PoseDetector(options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ));
    openCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      releaseCamera();
    } else if (state == AppLifecycleState.resumed && !finished) {
      openCamera();
    }
  }

  Future<void> openCamera() async {
    if (controller != null || finished || !mounted) return;
    try {
      final available = await availableCameras();
      if (available.isEmpty) throw Exception('На устройстве нет доступной камеры');
      final camera = available.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => available.first,
      );
      final next = CameraController(camera, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      controller = next;
      cameraDescription = camera;
      await next.initialize();
      if (!mounted || controller != next) { await next.dispose(); return; }
      await next.startImageStream(onFrame);
      if (mounted) setState(() => message = 'Встань так, чтобы камера видела ноги и корпус');
    } catch (e) {
      if (mounted) setState(() => error = '$e');
      await releaseCamera();
    }
  }

  Future<void> releaseCamera() async {
    final current = controller;
    controller = null;
    cameraDescription = null;
    if (current == null) return;
    try {
      if (current.value.isStreamingImages) await current.stopImageStream();
    } catch (_) {}
    try { await current.dispose(); } catch (_) {}
  }

  InputImage? fromCameraImage(CameraImage image) {
    final active = controller;
    final description = cameraDescription;
    if (active == null || description == null || image.planes.length != 1) return null;
    final frameFormat = InputImageFormatValue.fromRawValue(image.format.raw);
    if (frameFormat != InputImageFormat.nv21) return null;
    final compensation = orientations[active.value.deviceOrientation];
    if (compensation == null) return null;
    final sensor = description.sensorOrientation;
    final rotation = description.lensDirection == CameraLensDirection.front
      ? (sensor + compensation) % 360
      : (sensor - compensation + 360) % 360;
    final imageRotation = InputImageRotationValue.fromRawValue(rotation);
    if (imageRotation == null) return null;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  void onFrame(CameraImage image) {
    if (busy || finished) return;
    final input = fromCameraImage(image);
    if (input == null) {
      if (message != 'Камера не передаёт NV21. Проверь пакет camera_android.') {
        if (mounted) setState(() => message = 'Камера не передаёт NV21. Проверь пакет camera_android.');
      }
      return;
    }
    busy = true;
    processPose(input).whenComplete(() => busy = false);
  }

  Future<void> processPose(InputImage input) async {
    try {
      final poses = await poseDetector.processImage(input);
      if (!mounted || finished) return;
      if (poses.isEmpty) {
        setState(() { message = 'Человек не найден — отойди дальше от телефона'; kneeAngle = null; });
        return;
      }
      final pose = poses.first;
      final angle = estimateKneeAngle(pose);
      if (angle == null) {
        setState(() { message = 'Не вижу бедро, колено и стопу — повернись боком'; kneeAngle = null; });
        return;
      }
      kneeAngle = angle;
      if (phase == 'up') {
        if (angle < 125) {
          consecutiveDown++;
          if (consecutiveDown >= 2) {
            phase = 'down';
            consecutiveDown = 0;
          }
        } else {
          consecutiveDown = 0;
        }
        message = phase == 'down' ? 'Отлично! Теперь встань' : 'Присядь (опусти корпус)';
      } else {
        if (angle > 155) {
          consecutiveUp++;
          if (consecutiveUp >= 2) {
            consecutiveUp = 0;
            reps++;
            phase = 'up';
          }
        } else {
          consecutiveUp = 0;
        }
        message = 'Вернись в положение стоя';
      }
      if (reps >= goal && !finished) {
        finished = true;
        message = 'Готово! Открываем выбранное приложение...';
        unawaited(grantAccess());
      }
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  double? estimateKneeAngle(Pose pose) {
    final map = pose.landmarks;
    double? side(PoseLandmarkType hipType, PoseLandmarkType kneeType, PoseLandmarkType ankleType) {
      final hip = map[hipType];
      final knee = map[kneeType];
      final ankle = map[ankleType];
      if (hip == null || knee == null || ankle == null) return null;
      if (hip.likelihood < 0.55 || knee.likelihood < 0.55 || ankle.likelihood < 0.55) return null;
      final a = Offset(hip.x, hip.y);
      final b = Offset(knee.x, knee.y);
      final c = Offset(ankle.x, ankle.y);
      final ab = a - b;
      final cb = c - b;
      final denominator = ab.distance * cb.distance;
      if (denominator < 1e-5) return null;
      final cosine = ((ab.dx * cb.dx + ab.dy * cb.dy) / denominator).clamp(-1.0, 1.0);
      return math.acos(cosine) * 180 / math.pi;
    }
    return side(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle)
      ?? side(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
  }

  Future<void> grantAccess() async {
    try {
      await releaseCamera();
      await native.invokeMethod('grantAccess', {'minutes': 5});
      if (mounted) setState(() => message = 'Доступ выдан. Можно вернуться в LevelUp.');
    } catch (e) {
      if (mounted) setState(() => error = 'Не удалось открыть: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(releaseCamera());
    unawaited(poseDetector.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('5 SQUATS → 5 MIN')),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Move to unlock', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 380,
              color: const Color(0xFF202A30),
              child: active != null && active.value.isInitialized
                ? Center(child: CameraPreview(active))
                : const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 14),
          Text('$reps / $goal', textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: accent)),
          Text(message, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15)),
          if (kneeAngle != null)
            Text('Угол колена: ${kneeAngle!.toStringAsFixed(0)}° (приблизительно)',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
          if (error != null) Text('Ошибка: $error',
            style: const TextStyle(color: Colors.redAccent)),
          const SizedBox(height: 14),
          const Text('Советы: фронтальная камера, 2–3 м до телефона, хорошо освещённое место. Приседай комфортно, без боли. Можно выйти без выполнения.',
            style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => Navigator.pop(context),
            child: const Text('Вернуться без задания')),
        ],
      )),
    );
  }
}
