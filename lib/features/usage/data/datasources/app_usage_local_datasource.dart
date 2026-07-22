import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/errors/error_logger.dart';
import '../../domain/entities/daily_usage_summary.dart';
import '../models/app_usage_model.dart';

/// Contract for local persistence of app-usage records.
abstract interface class AppUsageLocalDataSource {
  Future<void> insertUsage(AppUsageModel usage);
  Future<List<AppUsageModel>> getUsageByDate(DateTime date);

  /// Returns total screen time per day for the last 7 days (today − 6 days),
  /// ordered oldest → newest. Days with no data are omitted.
  Future<List<DailyUsageSummary>> getUsageSummaryLast7Days();
}

/// SQLite-backed implementation.
class AppUsageLocalDataSourceImpl implements AppUsageLocalDataSource {
  const AppUsageLocalDataSourceImpl(this._dbHelper);

  final DatabaseHelper _dbHelper;

  static const _table = 'app_usage';

  @override
  Future<void> insertUsage(AppUsageModel usage) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(
        _table,
        usage.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'AppUsageLocalDataSource.insertUsage');
    }
  }

  @override
  Future<List<AppUsageModel>> getUsageByDate(DateTime date) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        _table,
        where: 'date = ?',
        whereArgs: [_dateKey(date)],
        orderBy: 'usage_time DESC',
      );
      return rows.map(AppUsageModel.fromMap).toList();
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'AppUsageLocalDataSource.getUsageByDate');
      return [];
    }
  }

  @override
  Future<List<DailyUsageSummary>> getUsageSummaryLast7Days() async {
    try {
      final db = await _dbHelper.database;
      final cutoff = _dateKey(DateTime.now().subtract(const Duration(days: 6)));
      final rows = await db.rawQuery(
        '''
        SELECT date, SUM(usage_time) AS total_seconds
        FROM $_table
        WHERE date >= ?
        GROUP BY date
        ORDER BY date ASC
        ''',
        [cutoff],
      );
      return rows.map((row) {
        final parts = (row['date'] as String).split('-');
        return DailyUsageSummary(
          date: DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          ),
          totalSeconds: (row['total_seconds'] as num).toInt(),
        );
      }).toList();
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'AppUsageLocalDataSource.getUsageSummaryLast7Days');
      return [];
    }
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
