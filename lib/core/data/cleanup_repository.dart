import 'cleanup_datasource.dart';

/// Repository for data cleanup operations.
/// Follows clean architecture pattern: datasource → repository → provider
class CleanupRepository {
  const CleanupRepository(this._dataSource);

  final CleanupDataSource _dataSource;

  /// Deletes old app_usage records (keeps last 7 days).
  /// Returns count of deleted rows.
  Future<int> deleteOldAppUsage() =>
      _dataSource.deleteOldAppUsage(daysToKeep: 7);

  /// Deletes old focus_sessions records (keeps last 30 days).
  /// Returns count of deleted rows.
  Future<int> deleteOldFocusSessions() =>
      _dataSource.deleteOldFocusSessions(daysToKeep: 30);

  /// Runs full cleanup: deletes old app_usage and old focus_sessions.
  /// Returns a map with cleanup stats.
  Future<Map<String, int>> runCleanup() async {
    final appUsageDeleted = await deleteOldAppUsage();
    final focusSessionsDeleted = await deleteOldFocusSessions();

    return {
      'app_usage_deleted': appUsageDeleted,
      'focus_sessions_deleted': focusSessionsDeleted,
    };
  }

  /// Clears all data from both tables.
  /// Returns a map with counts of deleted rows from each table.
  Future<Map<String, int>> clearAllData() => _dataSource.clearAllData();
}
