/// Local-calendar time boundary utilities for LevelUp statistics.
///
/// Week definition:
/// - The calendar week starts on **Monday** (`DateTime.monday == 1`, ISO-8601)
///   and ends on **Sunday** (`DateTime.sunday == 7`).
/// - All boundaries use inclusive start and exclusive end (`[start, end)`).
/// - All calendar-day arithmetic uses `DateTime(year, month, day)` rather than
///   adding fixed 24-hour durations, ensuring exact handling across midnight,
///   month/year rollovers, and Daylight Saving Time (23-hour / 25-hour days).
abstract final class StatisticsCalendar {
  /// Returns the local midnight `DateTime` for [dateTime].
  static DateTime startOfLocalDay(DateTime dateTime) {
    final local = dateTime.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Returns `[start, end)` in local time for the calendar day containing [now].
  static DateRange localDayRange(DateTime now) {
    final start = startOfLocalDay(now);
    final end = DateTime(start.year, start.month, start.day + 1);
    return DateRange(start: start, end: end);
  }

  /// Returns `[start, end)` in local time for the current calendar week
  /// (Monday 00:00:00 inclusive to next Monday 00:00:00 exclusive).
  static DateRange currentWeekRange(DateTime now) {
    final todayStart = startOfLocalDay(now);
    final daysFromMonday = todayStart.weekday - DateTime.monday;
    final weekStart = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day - daysFromMonday,
    );
    final weekEnd = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day + 7,
    );
    return DateRange(start: weekStart, end: weekEnd);
  }

  /// Returns `[start, end)` in local time covering the rolling last 7 calendar
  /// days ending with the day containing [now] (inclusive of today).
  static DateRange last7DaysRange(DateTime now) {
    final todayStart = startOfLocalDay(now);
    final start = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day - 6,
    );
    final end = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day + 1,
    );
    return DateRange(start: start, end: end);
  }

  /// Returns the ordered list of 7 local-midnight [DateTime] values for the
  /// rolling last 7 calendar days ending on [now]'s local date (oldest first).
  static List<DateTime> last7LocalDays(DateTime now) {
    final todayStart = startOfLocalDay(now);
    return List<DateTime>.generate(
      7,
      (index) => DateTime(
        todayStart.year,
        todayStart.month,
        todayStart.day - (6 - index),
      ),
      growable: false,
    );
  }

  /// Formats a local calendar date as `'YYYY-MM-DD'`.
  static String formatLocalDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// Half-open time interval `[start, end)` in local time.
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange({required this.start, required this.end});

  int get startUtcMs => start.toUtc().millisecondsSinceEpoch;
  int get endUtcMs => end.toUtc().millisecondsSinceEpoch;

  bool contains(DateTime timestamp) {
    final local = timestamp.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }
}
