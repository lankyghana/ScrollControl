import '../entities/daily_focus_summary.dart';
import '../entities/focus_session.dart';

abstract interface class FocusRepository {
  Future<void> saveSession(FocusSession session);
  Future<List<FocusSession>> getDailySessions(DateTime date);

  /// Returns session count per day for the last 7 days, oldest first.
  Future<List<DailyFocusSummary>> getSessionsLast7Days();
}
