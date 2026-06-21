import '../../domain/entities/daily_focus_summary.dart';
import '../../domain/entities/focus_session.dart';
import '../../domain/repositories/focus_repository.dart';
import '../datasources/focus_local_datasource.dart';
import '../models/focus_session_model.dart';

class FocusRepositoryImpl implements FocusRepository {
  const FocusRepositoryImpl(this._localDataSource);

  final FocusLocalDataSource _localDataSource;

  @override
  Future<void> saveSession(FocusSession session) {
    return _localDataSource.insertSession(FocusSessionModel.fromEntity(session));
  }

  @override
  Future<List<FocusSession>> getDailySessions(DateTime date) {
    return _localDataSource.getSessionsByDate(date);
  }

  @override
  Future<List<DailyFocusSummary>> getSessionsLast7Days() {
    return _localDataSource.getSessionSummaryLast7Days();
  }
}
