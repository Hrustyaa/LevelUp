import 'package:flutter/foundation.dart' show setEquals;
import 'package:material_ui/material_ui.dart';

import '../focus_experience/focus_style.dart';
import '../free_workout/workout_session.dart';
import 'progress_chart.dart';
import 'progress_labels.dart';
import 'progress_models.dart';
import 'progress_repository.dart';
import 'workout_history_page.dart';

enum ProgressSection { workouts, focus }

/// Content of the dashboard's existing scroll view.
class LevelUpProgressTab extends StatefulWidget {
  const LevelUpProgressTab({
    super.key,
    required this.trackedPackageIds,
    required this.language,
    this.repository = const LocalProgressRepository(),
    this.onOpenUsagePermissions,
  });

  final Set<String> trackedPackageIds;
  final String language;
  final ProgressRepository repository;
  final Future<void> Function()? onOpenUsagePermissions;

  @override
  LevelUpProgressTabState createState() => LevelUpProgressTabState();
}

class LevelUpProgressTabState extends State<LevelUpProgressTab>
    with WidgetsBindingObserver {
  static const _readTimeout = Duration(seconds: 5);
  ProgressSection _section = ProgressSection.workouts;
  ProgressPeriod _period = ProgressPeriod.sevenDays;
  late Future<List<WorkoutResult>> _workouts = _loadWorkouts();
  Future<FocusUsageRead>? _usage;

  String _tr(String ru, String en, String kk) =>
      focusTr(widget.language, ru, en, kk);

  Future<List<WorkoutResult>> _loadWorkouts() =>
      _read(widget.repository.loadWorkouts);

  Future<FocusUsageRead> _loadUsage() => _read(
    () => widget.repository.loadFocusUsage(
      widget.trackedPackageIds,
      DateTime.now(),
    ),
  );

  Future<T> _read<T>(Future<T> Function() read) {
    final future = Future<T>.sync(read).timeout(_readTimeout);
    // This can fail before the next frame subscribes its FutureBuilder.
    future.ignore();
    return future;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant LevelUpProgressTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      if (_section == ProgressSection.workouts) {
        _workouts = _loadWorkouts();
      } else {
        _usage = _loadUsage();
      }
    } else if (_section == ProgressSection.focus &&
        !setEquals(oldWidget.trackedPackageIds, widget.trackedPackageIds)) {
      _usage = _loadUsage();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh() async {
    late final Future<Object?> pending;
    setState(() {
      pending = switch (_section) {
        ProgressSection.workouts => _workouts = _loadWorkouts(),
        ProgressSection.focus => _usage = _loadUsage(),
      };
    });
    try {
      await pending;
    } on Object {
      // The FutureBuilder for the selected section displays the read error.
    }
  }

  void _select(ProgressSection next) {
    if (_section == next) return;
    setState(() {
      _section = next;
      if (next == ProgressSection.focus) {
        _usage = _loadUsage();
      } else {
        _workouts = _loadWorkouts();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('levelup_progress_content'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(4),
        decoration: _surface,
        child: Row(
          children: [
            _segment(
              ProgressSection.workouts,
              _tr('Тренировки', 'Workouts', 'Жаттығулар'),
            ),
            _segment(ProgressSection.focus, _tr('Фокус', 'Focus', 'Фокус')),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (_section == ProgressSection.workouts) ...[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final period in ProgressPeriod.values)
              ChoiceChip(
                key: ValueKey('progress_period_${period.days}'),
                showCheckmark: false,
                label: Text(
                  period == ProgressPeriod.sevenDays
                      ? _tr('7 дней', '7 days', '7 күн')
                      : _tr('30 дней', '30 days', '30 күн'),
                ),
                selected: _period == period,
                selectedColor: FocusStyle.accent,
                labelStyle: TextStyle(
                  color: _period == period
                      ? FocusStyle.background
                      : FocusStyle.text,
                ),
                onSelected: (_) => setState(() => _period = period),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<WorkoutResult>>(
          future: _workouts,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _loader;
            }
            if (snapshot.hasError) {
              return _error(
                _tr(
                  'Не удалось загрузить тренировки',
                  'Could not load workouts',
                  'Жаттығулар жүктелмеді',
                ),
              );
            }
            return _workoutsBody(snapshot.requireData);
          },
        ),
      ] else ...[
        Text(
          _tr('Последние 7 дней', 'Last 7 days', 'Соңғы 7 күн'),
          style: const TextStyle(color: FocusStyle.muted),
        ),
        const SizedBox(height: 12),
        FutureBuilder<FocusUsageRead>(
          future: _usage,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _loader;
            }
            if (snapshot.hasError) {
              return _error(
                _tr(
                  'Не удалось загрузить экранное время',
                  'Could not load screen time',
                  'Экран уақытын жүктеу мүмкін болмады',
                ),
              );
            }
            return _focusBody(snapshot.requireData);
          },
        ),
        const SizedBox(height: 18),
        Text(
          _tr(
            'История разблокировок пока недоступна',
            'Unlock history is currently unavailable',
            'Бұғаттан шығару тарихы әзірге қолжетімсіз',
          ),
          style: const TextStyle(color: FocusStyle.muted),
        ),
      ],
    ],
  );

  Widget _segment(ProgressSection section, String label) {
    final selected = section == _section;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: ValueKey('progress_section_${section.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _select(section),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? FocusStyle.accent : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? FocusStyle.background : FocusStyle.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _workoutsBody(List<WorkoutResult> records) {
    final now = DateTime.now();
    final actual = completedWorkouts(records, now: now);
    final summary = WorkoutProgressSummary.fromWorkouts(
      actual,
      now: now,
      period: _period,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (actual.isNotEmpty)
          _metrics([
            (_tr('Тренировки', 'Workouts', 'Жаттығулар'), summary.sessions),
            (
              _tr('Повторения', 'Repetitions', 'Қайталаулар'),
              summary.repetitions,
            ),
            (_tr('Подходы', 'Sets', 'Тәсілдер'), summary.sets),
            (
              _tr('Дни с тренировками', 'Training days', 'Жаттығу күндері'),
              summary.activeDays,
            ),
          ]),
        const SizedBox(height: 12),
        Text(
          _tr(
            'Повторения по дням',
            'Repetitions by day',
            'Күндер бойынша қайталау',
          ),
          style: _heading(17),
        ),
        const SizedBox(height: 8),
        if (summary.sessions == 0)
          _message(
            actual.isEmpty
                ? _tr(
                    'Пока нет тренировок',
                    'No workouts yet',
                    'Әзірге жаттығу жоқ',
                  )
                : _tr(
                    'Нет тренировок за этот период',
                    'No workouts in this period',
                    'Бұл кезеңде жаттығу жоқ',
                  ),
          )
        else
          ProgressChart(
            points: [
              for (final day in summary.dailyRepetitions)
                ProgressChartPoint(day.date, day.value),
            ],
            valueLabel: (value) => '$value ${_tr('повт.', 'reps', 'қайталау')}',
            language: widget.language,
          ),
        const SizedBox(height: 14),
        ListTile(
          key: const ValueKey('progress_open_history'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            _tr('История тренировок', 'Workout history', 'Жаттығу тарихы'),
            style: _heading(17),
          ),
          trailing: const Icon(Icons.chevron_right, color: FocusStyle.accent),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => WorkoutHistoryPage(
                workouts: actual,
                language: widget.language,
              ),
            ),
          ),
        ),
        for (final workout in actual.take(3))
          WorkoutHistoryRow(
            workout: workout,
            language: widget.language,
            includeDate: true,
          ),
      ],
    );
  }

  Widget _focusBody(FocusUsageRead usage) {
    final data = usage.snapshot;
    if (data == null) {
      final text = switch (usage.status) {
        FocusUsageStatus.needsSelection => _tr(
          'Выбери приложения во вкладке «Фокус».',
          'Select apps in the Focus tab.',
          '«Фокус» бөлімінен қолданбаларды таңда.',
        ),
        FocusUsageStatus.permissionDenied => _tr(
          'Нет доступа к статистике использования Android.',
          'Android Usage Access is off.',
          'Android қолдану статистикасына рұқсат жоқ.',
        ),
        FocusUsageStatus.unavailable => _tr(
          'В этой сборке статистика Android недоступна.',
          'Android screen time is unavailable in this build.',
          'Бұл нұсқада Android экран уақыты қолжетімсіз.',
        ),
        _ => _tr(
          'За этот период пока нет данных.',
          'No usage data for this period yet.',
          'Бұл кезеңде қолдану деректері жоқ.',
        ),
      };
      final permissionAction =
          usage.status == FocusUsageStatus.permissionDenied ||
          usage.status == FocusUsageStatus.noData;
      return _message(
        text,
        action: permissionAction && widget.onOpenUsagePermissions != null
            ? TextButton(
                key: const ValueKey('progress_open_usage_permissions'),
                onPressed: _openPermissions,
                child: Text(_tr('Разрешения', 'Permissions', 'Рұқсаттар')),
              )
            : null,
      );
    }

    String time(int value) =>
        progressDuration(Duration(milliseconds: value), widget.language);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _tr(
            'Экранное время выбранных приложений',
            'Screen time in selected apps',
            'Таңдалған қолданбалардағы экран уақыты',
          ),
          style: _heading(17),
        ),
        const SizedBox(height: 4),
        Text(time(data.totalMilliseconds), style: _heading(22)),
        if (data.observedDays < 7) ...[
          const SizedBox(height: 5),
          Text(
            _tr(
              'В сумме учтено ${data.observedDays} из 7 дней. Серые отметки — дни без данных.',
              'Total covers ${data.observedDays} of 7 days. Gray marks indicate missing data.',
              'Жиынтықта 7 күннің ${data.observedDays} күні бар. Сұр белгілер — дерегі жоқ күндер.',
            ),
            style: const TextStyle(color: FocusStyle.muted),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _tr(
            'Время по дням',
            'Screen time by day',
            'Күндер бойынша экран уақыты',
          ),
          style: _heading(17),
        ),
        const SizedBox(height: 8),
        ProgressChart(
          points: [
            for (final day in data.days)
              ProgressChartPoint(day.date, day.milliseconds),
          ],
          valueLabel: time,
          language: widget.language,
        ),
      ],
    );
  }

  Future<void> _openPermissions() async {
    await widget.onOpenUsagePermissions?.call();
    if (mounted) await refresh();
  }

  Widget _metrics(List<(String, int)> metrics) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 8.0;
      final twoColumns = constraints.maxWidth >= 272;
      final width = twoColumns
          ? (constraints.maxWidth - spacing) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final (label, value) in metrics)
            Container(
              width: width,
              padding: const EdgeInsets.all(12),
              decoration: _surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: _heading(22)),
                  Text(label, style: const TextStyle(color: FocusStyle.muted)),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _error(String label) => _message(
    label,
    action: TextButton(
      onPressed: refresh,
      child: Text(_tr('Повторить', 'Retry', 'Қайталау')),
    ),
  );

  Widget _message(String label, {Widget? action}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: _surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: FocusStyle.muted)),
        ?action,
      ],
    ),
  );

  static const _loader = Padding(
    padding: EdgeInsets.all(16),
    child: Center(child: CircularProgressIndicator(color: FocusStyle.accent)),
  );
}

final _surface = BoxDecoration(
  color: FocusStyle.surface,
  border: Border.all(color: FocusStyle.border),
  borderRadius: BorderRadius.circular(12),
);

TextStyle _heading(double size) => TextStyle(
  fontSize: size,
  fontWeight: FontWeight.w600,
  color: FocusStyle.text,
);
