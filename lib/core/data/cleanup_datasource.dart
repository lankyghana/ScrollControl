import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../errors/error_logger.dart';

/// Handles deletion of old data to maintain app performance.
class CleanupDataSource {
  const CleanupDataSource(this._dbHelper);

  final DatabaseHelper _dbHelper;

  static const _appUsageTable = 'app_usage';
  static const _focusSessionsTable = 'focus_sessions';

  /// Deletes app_usage records older than [daysToKeep] (default: 7 days).
  /// Returns the number of deleted rows.
  Future<int> deleteOldAppUsage({int daysToKeep = 7}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = _calculateCutoffDate(daysToKeep);

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

  /// Deletes focus_sessions records older than [daysToKeep] (default: 30 days).
  /// Returns the number of deleted rows.
  Future<int> deleteOldFocusSessions({int daysToKeep = 30}) async {
    try {
      final db = await _dbHelper.database;
      final cutoffDate = _calculateCutoffDateIso8601(daysToKeep);

      final deletedCount = await db.delete(
        _focusSessionsTable,
        where: 'start_time < ?',
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

  /// Calculates the cutoff date for app_usage (YYYY-MM-DD format).
  /// Returns date that is [daysToKeep] days ago in YYYY-MM-DD format.
  static String _calculateCutoffDate(int daysToKeep) {
    final cutoffDateTime = DateTime.now().subtract(Duration(days: daysToKeep));
    return _formatDate(cutoffDateTime);
  }

  /// Calculates the cutoff date for focus_sessions (ISO 8601 format).
  /// Returns datetime that is [daysToKeep] days ago in ISO 8601 format.
  /// Uses start of day (00:00:00.000Z) to ensure clean date boundary.
  static String _calculateCutoffDateIso8601(int daysToKeep) {
    final cutoffDateTime = DateTime.now().subtract(Duration(days: daysToKeep));
    // ISO 8601 format: YYYY-MM-DDTHH:mm:ss.sssZ
    // Get the date part and append time at start of day
    final datePart = cutoffDateTime.toIso8601String().split('T')[0];
    return '${datePart}T00:00:00.000Z';
  }

  /// Formats a DateTime to YYYY-MM-DD string.
  static String _formatDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
