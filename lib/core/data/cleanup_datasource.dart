import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../errors/error_logger.dart';

/// Handles deletion of old data to maintain app performance.
class CleanupDataSource {
  const CleanupDataSource(this._dbHelper);

  final DatabaseHelper _dbHelper;

  static const _appUsageTable = 'app_usage';
  static const _focusSessionsTable = 'focus_sessions';

  /// Deletes app_usage records older than the last [daysToKeep] calendar days
  /// (today included; default 7, which is exactly what the 7-day chart reads).
  /// Returns the number of deleted rows.
  Future<int> deleteOldAppUsage({int daysToKeep = 7, DateTime? now}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = _calculateCutoffDate(daysToKeep, now: now);

      final deletedCount = await db.delete(
        _appUsageTable,
        where: 'date < ?',
        whereArgs: [cutoffDate],
      );

      if (kDebugMode) {
        debugPrint('[Cleanup] Deleted $deletedCount rows from $_appUsageTable');
      }

      return deletedCount;
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'CleanupDataSource.deleteOldAppUsage');
      return 0;
    }
  }

  /// Deletes focus_sessions records older than the last [daysToKeep]
  /// calendar days (today included; default 30). Returns the number of
  /// deleted rows.
  Future<int> deleteOldFocusSessions({int daysToKeep = 30, DateTime? now}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = _calculateCutoffDate(daysToKeep, now: now);

      // Same date extraction the focus queries use, so retention and the
      // statistics screens always agree on which day a session belongs to.
      final deletedCount = await db.delete(
        _focusSessionsTable,
        where: 'substr(start_time, 1, 10) < ?',
        whereArgs: [cutoffDate],
      );

      if (kDebugMode) {
        debugPrint(
            '[Cleanup] Deleted $deletedCount rows from $_focusSessionsTable');
      }

      return deletedCount;
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'CleanupDataSource.deleteOldFocusSessions');
      return 0;
    }
  }

  /// Applies both retention rules atomically: either both tables are pruned
  /// or neither is. Returns {'app_usage_deleted', 'focus_sessions_deleted'}.
  Future<Map<String, int>> runRetention({
    int usageDaysToKeep = 7,
    int sessionDaysToKeep = 30,
    DateTime? now,
  }) async {
    final db = await _dbHelper.database;
    return db.transaction((txn) async {
      final usageDeleted = await txn.delete(
        _appUsageTable,
        where: 'date < ?',
        whereArgs: [_calculateCutoffDate(usageDaysToKeep, now: now)],
      );
      final sessionsDeleted = await txn.delete(
        _focusSessionsTable,
        where: 'substr(start_time, 1, 10) < ?',
        whereArgs: [_calculateCutoffDate(sessionDaysToKeep, now: now)],
      );
      return {
        'app_usage_deleted': usageDeleted,
        'focus_sessions_deleted': sessionsDeleted,
      };
    });
  }

  /// Deletes ALL data from app_usage and focus_sessions.
  /// Returns a map with deletion counts: {'app_usage': int, 'focus_sessions': int}
  Future<Map<String, int>> clearAllData() async {
    try {
      final db = await _dbHelper.database;

      final appUsageCount = await db.delete(_appUsageTable);
      final focusSessionsCount = await db.delete(_focusSessionsTable);

      if (kDebugMode) {
        debugPrint('[Cleanup] Cleared all data: '
            '$_appUsageTable=$appUsageCount, $_focusSessionsTable=$focusSessionsCount');
      }

      return {
        'app_usage': appUsageCount,
        'focus_sessions': focusSessionsCount,
      };
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'CleanupDataSource.clearAllData');
      return {};
    }
  }

  /// First calendar day (YYYY-MM-DD) that is still kept when retaining the
  /// last [daysToKeep] days including today. Rows with an earlier date go.
  static String _calculateCutoffDate(int daysToKeep, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final firstKept = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: daysToKeep - 1));
    return _formatDate(firstKept);
  }

  /// Formats a DateTime to YYYY-MM-DD string.
  static String _formatDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
