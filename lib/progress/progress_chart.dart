import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../focus_experience/focus_style.dart';
import 'progress_labels.dart';

class ProgressChartPoint {
  const ProgressChartPoint(this.date, this.value);

  final DateTime date;
  final int? value;
}

class ProgressChart extends StatelessWidget {
  const ProgressChart({
    super.key,
    required this.points,
    required this.valueLabel,
    required this.language,
  });

  final List<ProgressChartPoint> points;
  final String Function(int value) valueLabel;
  final String language;

  @override
  Widget build(BuildContext context) {
    final maximum = points.fold(
      1,
      (max, point) => math.max(max, point.value ?? 0),
    );
    final largeText = MediaQuery.textScalerOf(context).scale(11) > 15;
    final ticks = points.length <= 7 && !largeText
        ? points
        : [points.first, points[points.length ~/ 2], points.last];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FocusStyle.surface,
        border: Border.all(color: FocusStyle.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in points)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: points.length > 7 ? 1 : 4,
                      ),
                      child: _bar(point, maximum),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final point in ticks)
                Flexible(
                  child: Text(
                    progressDate(point.date, includeYear: false),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FocusStyle.muted,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bar(ProgressChartPoint point, int maximum) {
    final value = point.value;
    final label =
        '${progressDate(point.date)} · ${value == null ? focusTr(language, 'Нет данных', 'No data', 'Дерек жоқ') : valueLabel(value)}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          height: value == null || value == 0
              ? 2
              : math.max(4, 100 * value / maximum),
          color: value == null ? FocusStyle.muted : FocusStyle.accent,
        ),
      ),
    );
  }
}
