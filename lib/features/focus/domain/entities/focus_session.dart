class FocusSession {
  const FocusSession({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });

  final int? id;

  /// When the focus timer started.
  final DateTime startTime;

  /// When the timer reached zero (session completed).
  final DateTime endTime;

  /// Total intended duration in seconds (e.g. 25 * 60 = 1500).
  final int duration;
}
