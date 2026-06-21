extension DurationFormatting on Duration {
  /// Returns "mm:ss" formatted string
  String toMMSS() {
    final m = inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Returns "Xh Ym" for display in stat cards
  String toHoursMinutes() {
    final h = inHours;
    final m = inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}
