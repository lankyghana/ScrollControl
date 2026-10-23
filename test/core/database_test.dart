import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/core/data/cleanup_datasource.dart';
import 'package:scroll_control/core/data/cleanup_repository.dart';
import 'package:scroll_control/core/database/database_helper.dart';
import 'package:scroll_control/features/focus/data/datasources/focus_local_datasource.dart';
import 'package:scroll_control/features/focus/data/models/focus_session_model.dart';
import 'package:scroll_control/features/usage/data/datasources/app_usage_local_datasource.dart';
import 'package:scroll_control/features/usage/data/models/app_usage_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openFresh() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: DatabaseHelper.onCreate,
        onUpgrade: DatabaseHelper.onUpgrade,
      ),
    );

Future<Set<String>> tables(Database db) async {
  final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'");
  return rows.map((r) => r['name'] as String).toSet();
}

String day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  sqfliteFfiInit();

  group('schema', () {
    test('fresh database has every table', () async {
      final db = await openFresh();
      addTearDown(db.close);
      expect(await tables(db), {'app_usage', 'focus_sessions', 'app_limits'});
    });

    test('UNIQUE(package_name, date) keeps one row per app per day (latest wins)', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final ds = AppUsageLocalDataSourceImpl(DatabaseHelper.forTesting(db));
      final date = DateTime(2026, 3, 10);

      await ds.insertUsage(AppUsageModel(appName: 'A', packageName: 'com.a', usageTime: 60, date: date));
      await ds.insertUsage(AppUsageModel(appName: 'A', packageName: 'com.a', usageTime: 300, date: date));

      final rows = await ds.getUsageByDate(date);
      expect(rows, hasLength(1));
      expect(rows.single.usageTime, 300);
    });
  });

  group('migrations', () {
    Future<Database> openAt(int version) => databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: version, onCreate: (db, v) async {
            // Rebuild the historical schema for the version under test.
            await db.execute('''CREATE TABLE app_usage (
              id INTEGER PRIMARY KEY AUTOINCREMENT, app_name TEXT NOT NULL,
              package_name TEXT NOT NULL, usage_time INTEGER NOT NULL,
              date TEXT NOT NULL, UNIQUE(package_name, date) ON CONFLICT REPLACE)''');
            if (v >= 3) {
              await db.execute('''CREATE TABLE focus_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT, start_time TEXT NOT NULL,
                end_time TEXT NOT NULL, duration INTEGER NOT NULL)''');
            }
          }),
        );

    test('v2 -> v4 preserves usage rows and adds the newer tables', () async {
      final db = await openAt(2);
      addTearDown(db.close);
      await db.insert('app_usage',
          {'app_name': 'A', 'package_name': 'com.a', 'usage_time': 120, 'date': '2026-03-10'});

      await DatabaseHelper.onUpgrade(db, 2, 4);

      expect(await tables(db), {'app_usage', 'focus_sessions', 'app_limits'});
      final rows = await db.query('app_usage');
      expect(rows, hasLength(1));
      expect(rows.single['usage_time'], 120);
    });

    test('v3 -> v4 preserves usage and sessions and adds app_limits', () async {
      final db = await openAt(3);
      addTearDown(db.close);
      await db.insert('app_usage',
          {'app_name': 'A', 'package_name': 'com.a', 'usage_time': 120, 'date': '2026-03-10'});
      await db.insert('focus_sessions',
          {'start_time': '2026-03-10T09:00:00.000', 'end_time': '2026-03-10T09:25:00.000', 'duration': 1500});

      await DatabaseHelper.onUpgrade(db, 3, 4);

      expect(await tables(db), {'app_usage', 'focus_sessions', 'app_limits'});
      expect(await db.query('app_usage'), hasLength(1));
      expect(await db.query('focus_sessions'), hasLength(1));
    });

    test('upgrading twice is harmless (CREATE IF NOT EXISTS)', () async {
      final db = await openFresh();
      addTearDown(db.close);
      await DatabaseHelper.onUpgrade(db, 3, 4);
      await DatabaseHelper.onUpgrade(db, 3, 4);
      expect(await tables(db), {'app_usage', 'focus_sessions', 'app_limits'});
    });
  });

  group('usage queries', () {
    test('7-day summary sums per day, groups by date and omits empty days', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final ds = AppUsageLocalDataSourceImpl(DatabaseHelper.forTesting(db));
      final today = DateTime.now();
      final d = DateTime(today.year, today.month, today.day);

      await ds.insertUsage(AppUsageModel(appName: 'A', packageName: 'a', usageTime: 100, date: d));
      await ds.insertUsage(AppUsageModel(appName: 'B', packageName: 'b', usageTime: 50, date: d));
      await ds.insertUsage(AppUsageModel(
          appName: 'A', packageName: 'a', usageTime: 30, date: d.subtract(const Duration(days: 2))));
      await ds.insertUsage(AppUsageModel(
          appName: 'A', packageName: 'a', usageTime: 999, date: d.subtract(const Duration(days: 20))));

      final summary = await ds.getUsageSummaryLast7Days();

      expect(summary.map((s) => s.totalSeconds), [30, 150]); // oldest -> newest
      expect(summary.last.date, d);
      expect(summary, hasLength(2)); // no row for days without data
    });

    test('empty database returns empty results, not errors', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final ds = AppUsageLocalDataSourceImpl(DatabaseHelper.forTesting(db));
      expect(await ds.getUsageByDate(DateTime.now()), isEmpty);
      expect(await ds.getUsageSummaryLast7Days(), isEmpty);
    });

    test('usage is stored per calendar day (midnight rollover)', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final ds = AppUsageLocalDataSourceImpl(DatabaseHelper.forTesting(db));
      await ds.insertUsage(AppUsageModel(
          appName: 'A', packageName: 'a', usageTime: 100, date: DateTime(2026, 3, 10, 23, 59)));
      await ds.insertUsage(AppUsageModel(
          appName: 'A', packageName: 'a', usageTime: 5, date: DateTime(2026, 3, 11, 0, 1)));

      expect((await ds.getUsageByDate(DateTime(2026, 3, 10))).single.usageTime, 100);
      expect((await ds.getUsageByDate(DateTime(2026, 3, 11))).single.usageTime, 5);
    });
  });

  group('focus session queries', () {
    test('sessions are grouped by day and counted', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final ds = FocusLocalDataSourceImpl(DatabaseHelper.forTesting(db));
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      FocusSessionModel s(DateTime start) => FocusSessionModel(
          startTime: start, endTime: start.add(const Duration(minutes: 25)), duration: 1500);

      await ds.insertSession(s(today));
      await ds.insertSession(s(today.add(const Duration(hours: 2))));
      await ds.insertSession(s(twoDaysAgo));
      await ds.insertSession(s(today.subtract(const Duration(days: 30))));

      expect(await ds.getSessionsByDate(today), hasLength(2));
      final weekly = await ds.getSessionSummaryLast7Days();
      expect(weekly.map((w) => w.sessionCount), [1, 2]);
    });
  });

  group('retention', () {
    final now = DateTime(2026, 3, 31, 12);

    Future<void> seed(Database db) async {
      // app_usage: today, 6 days ago (kept), 7 days ago (deleted), 40 days ago (deleted)
      for (final back in [0, 6, 7, 40]) {
        await db.insert('app_usage', {
          'app_name': 'A',
          'package_name': 'com.a',
          'usage_time': 60,
          'date': day(now.subtract(Duration(days: back))),
        });
      }
      // sessions: today, 29 days ago (kept), 30 days ago (deleted), 90 days ago (deleted)
      for (final back in [0, 29, 30, 90]) {
        final start = DateTime(now.year, now.month, now.day, 8).subtract(Duration(days: back));
        await db.insert('focus_sessions', {
          'start_time': start.toIso8601String(),
          'end_time': start.add(const Duration(minutes: 25)).toIso8601String(),
          'duration': 1500,
        });
      }
    }

    test('keeps 7 days of usage and 30 days of sessions, deletes the rest', () async {
      final db = await openFresh();
      addTearDown(db.close);
      await seed(db);

      final stats = await CleanupRepository(CleanupDataSource(DatabaseHelper.forTesting(db)))
          .runCleanup(now: now);

      expect(stats, {'app_usage_deleted': 2, 'focus_sessions_deleted': 2});
      final usageDates = (await db.query('app_usage')).map((r) => r['date']).toSet();
      expect(usageDates, {day(now), day(now.subtract(const Duration(days: 6)))});
      expect(await db.query('focus_sessions'), hasLength(2));
    });

    test('keeps everything the 7-day statistics chart can display', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final ds = AppUsageLocalDataSourceImpl(DatabaseHelper.forTesting(db));
      await seed(db);

      await CleanupRepository(CleanupDataSource(DatabaseHelper.forTesting(db)))
          .runCleanup(now: now);

      // The chart reads today-6..today; the oldest of those days must survive.
      final oldestChartDay = now.subtract(const Duration(days: 6));
      expect(await ds.getUsageByDate(oldestChartDay), isNotEmpty);
      expect(await ds.getUsageByDate(now), isNotEmpty);
    });

    test('running twice deletes nothing the second time', () async {
      final db = await openFresh();
      addTearDown(db.close);
      await seed(db);
      final repo = CleanupRepository(CleanupDataSource(DatabaseHelper.forTesting(db)));

      await repo.runCleanup(now: now);
      final second = await repo.runCleanup(now: now);

      expect(second, {'app_usage_deleted': 0, 'focus_sessions_deleted': 0});
    });

    test('empty tables are fine', () async {
      final db = await openFresh();
      addTearDown(db.close);
      final stats = await CleanupRepository(CleanupDataSource(DatabaseHelper.forTesting(db)))
          .runCleanup(now: now);
      expect(stats, {'app_usage_deleted': 0, 'focus_sessions_deleted': 0});
    });

    test('app limits are never touched by cleanup', () async {
      final db = await openFresh();
      addTearDown(db.close);
      await db.insert('app_limits',
          {'package_name': 'com.a', 'app_name': 'A', 'daily_limit_minutes': 30});
      await CleanupRepository(CleanupDataSource(DatabaseHelper.forTesting(db)))
          .runCleanup(now: now);
      expect(await db.query('app_limits'), hasLength(1));
    });
  });
}
