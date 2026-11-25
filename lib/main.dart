import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data/dashboard_data.dart';
import 'focus_experience/focus_exercises.dart';
import 'test_kit/challenge_screen.dart';

const native = MethodChannel('levelup_test/control');
const accent = Color(0xFFC7FA5B);
const background = Color(0xFF11161A);

const testApps = <String, String>{
  'com.google.android.youtube': 'YouTube',
  'com.instagram.android': 'Instagram',
  'com.zhiliaoapp.musically': 'TikTok',
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LevelUpApp());
}

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
      if (mounted) {
        setState(() {
          error = '$e';
          checking = false;
        });
      }
    }
  }

  Future<void> checkChallengeRequest() async {
    if (openingChallenge || !mounted) return;
    const gateway = ExistingFocusGateway();
    FocusChallengeRequest? request;
    try {
      request = await gateway.claimChallenge();
      if (request != null && mounted) await openChallenge(request);
    } finally {
      if (request != null) await _cancelChallenge(request);
    }
  }

  Future<void> _cancelChallenge(FocusChallengeRequest request) async {
    try {
      await const ExistingFocusGateway().cancelChallenge(request);
    } on PlatformException catch (error) {
      debugPrint('Could not close diagnostic Focus challenge: ${error.code}');
    }
  }

  Future<void> openChallenge([FocusChallengeRequest? request]) async {
    if (openingChallenge || !mounted) return;
    openingChallenge = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChallengeScreen(
            exercise: focusExercises.first,
            onCompleted: request == null
                ? null
                : (repetitions) => const ExistingFocusGateway()
                      .completeChallenge(request, repetitions),
            onCameraPermissionDenied: request == null
                ? null
                : () => _cancelChallenge(request),
          ),
        ),
      );
    } finally {
      openingChallenge = false;
      if (mounted) await refresh();
    }
  }

  Future<void> changeTarget(String selected) async {
    await native.invokeMethod('setTarget', {'target': selected});
    await refresh();
  }

  Future<void> setGate(bool enabled) async {
    if (enabled && state['serviceEnabled'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сначала включи сервис в настройках Android.'),
          ),
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
    final remaining = DateTime.fromMillisecondsSinceEpoch(
      unlockUntil,
    ).difference(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEVELUP / TEST'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Earn your screen time.',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Тест на одном Android-телефоне. Без облака и загрузки видео.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            _panel(
              title: '1. Выбери приложение для теста',
              child: DropdownButtonFormField<String>(
                initialValue: testApps.containsKey(selected)
                    ? selected
                    : testApps.keys.first,
                items: testApps.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) changeTarget(value);
                },
              ),
            ),
            _panel(
              title: '2. Доступ Android',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serviceEnabled
                        ? '✓ Accessibility Service включён'
                        : '○ Accessibility Service выключен',
                    style: TextStyle(
                      color: serviceEnabled ? accent : Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () =>
                        native.invokeMethod('openAccessibilitySettings'),
                    icon: const Icon(Icons.settings_accessibility),
                    label: const Text('Открыть спец. возможности'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Сервис видит только имя активного приложения. Включается вручную; можно отключить в настройках.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            _panel(
              title: '3. Включи добровольное ограничение',
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                onChanged: setGate,
                title: Text(enabled ? 'Режим включён' : 'Режим выключен'),
                subtitle: const Text(
                  'Экран-барьер только для выбранного приложения',
                ),
              ),
            ),
            _panel(
              title: '4. Проверка камеры и приседаний',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: openChallenge,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Начать: 5 приседаний'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Зачёт только после цикла: стоя → вниз → стоя. Телефон поставь устойчиво, чтобы были видны бедро, колено и стопа.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            _panel(
              title: 'Текущий доступ',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    remaining.isNegative || remaining.inSeconds <= 0
                        ? 'Время разблокировки истекло'
                        : 'Разблокировано ещё примерно на ${remaining.inMinutes + 1} мин.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: resetAccess,
                    child: const Text('Сбросить доступ для теста'),
                  ),
                ],
              ),
            ),
            if (checking) const LinearProgressIndicator(),
            if (error != null)
              Text(
                'Ошибка: $error',
                style: const TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 12),
            const Text(
              'Важно: это исследовательский soft blocker. Он не гарантирует защиту от обхода или стабильную работу на всех устройствах. Можно безопасно выключить ограничение.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}
