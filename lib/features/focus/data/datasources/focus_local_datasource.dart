import 'package:flutter/foundation.dart';
import '../../../../core/database/database_helper.dart';
import '../../domain/entities/daily_focus_summary.dart';
import '../models/focus_session_model.dart';

abstract interface class FocusLocalDataSource {
  Future<void> insertSession(FocusSessionModel session);
  Future<List<FocusSessionModel>> getSessionsByDate(DateTime date);

  /// Returns session count per day for the last 7 days (today − 6 days),
  /// ordered oldest → newest. Days with no sessions are omitted.
  Future<List<DailyFocusSummary>> getSessionSummaryLast7Days();
}

class FocusLocalDataSourceImpl implements FocusLocalDataSource {
  const FocusLocalDataSourceImpl(this._dbHelper);

  final DatabaseHelper _dbHelper;

  static const _table = 'focus_sessions';

  @override
  Future<void> insertSession(FocusSessionModel session) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(_table, session.toMap());
    } catch (e) {
      if (kDebugMode) debugPrint('[FocusDS] insertSession error: $e');
    }
  }

  @override
  Future<List<FocusSessionModel>> getSessionsByDate(DateTime date) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        _table,
        where: 'substr(start_time, 1, 10) = ?',
        whereArgs: [_dateKey(date)],
        orderBy: 'start_time DESC',
      );
      return rows.map(FocusSessionModel.fromMap).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[FocusDS] getSessionsByDate error: $e');
      return [];
    }
  }

  @override
  Future<List<DailyFocusSummary>> getSessionSummaryLast7Days() async {
    try {
      final db = await _dbHelper.database;
      final cutoff = _dateKey(DateTime.now().subtract(const Duration(days: 6)));
      final rows = await db.rawQuery(
        '''
        SELECT substr(start_time, 1, 10) AS day, COUNT(*) AS session_count
        FROM $_table
        WHERE substr(start_time, 1, 10) >= ?
        GROUP BY day
        ORDER BY day ASC
        ''',
        [cutoff],
      );
      return rows.map((row) {
        final parts = (row['day'] as String).split('-');
        return DailyFocusSummary(
          date: DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          ),
          sessionCount: (row['session_count'] as num).toInt(),
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[FocusDS] getSessionSummaryLast7Days error: $e');
      return [];
    }
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
