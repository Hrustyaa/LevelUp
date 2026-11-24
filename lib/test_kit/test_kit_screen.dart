import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../data/dashboard_data.dart';
import '../focus_experience/focus_exercises.dart';
import 'challenge_screen.dart';

const testKitChannel = MethodChannel('levelup_test/control');
const testKitAccent = Color(0xFFC7FA5B);
const testApps = <String, String>{
  'com.google.android.youtube': 'YouTube',
  'com.instagram.android': 'Instagram',
  'com.zhiliaoapp.musically': 'TikTok',
};

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class TestKitScreen extends StatelessWidget {
  const TestKitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (_isAndroid) return const _AndroidTestKit();
    return Scaffold(
      appBar: AppBar(title: const Text('LevelUp Test')),
      body: const Center(
        child: Text('Режим ограничения и проверка камеры доступны на Android.'),
      ),
    );
  }
}

class _AndroidTestKit extends StatefulWidget {
  const _AndroidTestKit();
  @override
  State<_AndroidTestKit> createState() => _AndroidTestKitState();
}

class _AndroidTestKitState extends State<_AndroidTestKit>
    with WidgetsBindingObserver {
  Map<String, dynamic> state = {};
  String? error;
  bool checking = true;
  bool openingChallenge = false;
  bool _updating = false;

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
      final raw = await testKitChannel.invokeMapMethod<String, dynamic>(
        'getState',
      );
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
    try {
      final request = await gateway.claimChallenge();
      if (request != null) {
        try {
          if (mounted) await openChallenge(request);
        } finally {
          await gateway.cancelChallenge(request);
        }
      }
    } on PlatformException {
      // This diagnostic screen can still run a camera-only challenge.
    }
  }

  Future<void> openChallenge([FocusChallengeRequest? request]) async {
    if (openingChallenge || !mounted) return;
    openingChallenge = true;
    const gateway = ExistingFocusGateway();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChallengeScreen(
          exercise: focusExercises.first,
          appName: testApps[request?.target ?? state['target']] ?? 'LevelUp',
          onCompleted: request == null
              ? null
              : (repetitions) =>
                    gateway.completeChallenge(request, repetitions),
          onCameraPermissionDenied: request == null
              ? null
              : () async {
                  try {
                    await gateway.cancelChallenge(request);
                  } on PlatformException {
                    // Leaving the route retries the cancellation.
                  }
                },
        ),
      ),
    );
    openingChallenge = false;
    if (mounted) await refresh();
  }

  Future<void> changeTarget(String selected) async {
    await _runAction('setTarget', {'target': selected});
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
    await _runAction('setEnabled', {'enabled': enabled});
  }

  Future<void> resetAccess() async {
    await _runAction('resetAccess');
  }

  Future<void> _runAction(String method, [Map<String, Object>? args]) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await testKitChannel.invokeMethod<void>(method, args);
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
                key: ValueKey(selected),
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
                onChanged: _updating
                    ? null
                    : (value) {
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
                      color: serviceEnabled
                          ? testKitAccent
                          : Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _runAction('openAccessibilitySettings'),
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
                onChanged: _updating ? null : setGate,
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
                    onPressed: checking || _updating ? null : openChallenge,
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
                    onPressed: _updating ? null : resetAccess,
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
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Material(
      color: const Color(0xFF1D252A),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
      ),
    ),
  );
}
