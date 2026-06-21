/// Number of completed focus sessions for a single calendar day.
class DailyFocusSummary {
  const DailyFocusSummary({required this.date, required this.sessionCount});

  /// The calendar day (time components are zeroed out).
  final DateTime date;

  /// How many focus sessions were completed on this day.
  final int sessionCount;
}
