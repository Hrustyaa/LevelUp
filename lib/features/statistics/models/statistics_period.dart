/// Supported aggregation periods for LevelUp statistics.
enum StatisticsPeriod {
  /// Current local calendar day `[00:00, next 00:00)`.
  today,

  /// Current local calendar week (Monday `00:00` to next Monday `00:00`).
  currentWeek,

  /// Rolling 7 local calendar days ending today.
  last7Days,

  /// Unbounded lifetime history.
  allTime,
}
