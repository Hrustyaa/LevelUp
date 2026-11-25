import '../models/streak_info.dart';

/// Pure, deterministic calculator for daily workout streaks.
///
/// Uses `'YYYY-MM-DD'` local calendar dates mapped to UTC midnight [DateTime]
/// values so daylight-saving transitions never skew 1-day differences.
class StreakCalculator {
  const StreakCalculator();

  static String formatLocalDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? parseLocalDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final parsed = DateTime.utc(y, m, d);
    if (parsed.year != y || parsed.month != m || parsed.day != d) return null;
    return parsed;
  }

  StreakInfo calculate(
    Iterable<String> localDateStrings, {
    required DateTime now,
  }) {
    final uniqueDays = <DateTime>{};
    for (final raw in localDateStrings) {
      final parsed = parseLocalDate(raw);
      if (parsed != null) {
        uniqueDays.add(parsed);
      }
    }

    if (uniqueDays.isEmpty) {
      return StreakInfo.empty();
    }

    final sorted = uniqueDays.toList()..sort();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final expectedNext = sorted[i - 1].add(const Duration(days: 1));
      if (sorted[i] == expectedNext) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }

    final localNow = now.toLocal();
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final completedToday = uniqueDays.contains(today);

    final lastDay = sorted.last;
    var current = 0;
    if (lastDay == today || lastDay == yesterday) {
      current = 1;
      var cursor = lastDay.subtract(const Duration(days: 1));
      while (uniqueDays.contains(cursor)) {
        current++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
    }

    return StreakInfo(
      currentStreak: current,
      longestStreak: longest,
      lastWorkoutLocalDate: _formatUtcDate(lastDay),
      completedToday: completedToday,
    );
  }

  static String _formatUtcDate(DateTime utcDate) {
    final y = utcDate.year.toString().padLeft(4, '0');
    final m = utcDate.month.toString().padLeft(2, '0');
    final d = utcDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
