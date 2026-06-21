/// Total screen time for a single calendar day.
class DailyUsageSummary {
  const DailyUsageSummary({required this.date, required this.totalSeconds});

  /// The calendar day (time components are zeroed out).
  final DateTime date;

  /// Sum of all app usage_time values for this day (in seconds).
  final int totalSeconds;
}
