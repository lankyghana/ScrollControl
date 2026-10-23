import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';

class DatabaseHelper {
  DatabaseHelper._();

  /// Wraps an already-open database (tests use an in-memory one).
  @visibleForTesting
  DatabaseHelper.forTesting(Database db) : _db = db;

  /// Singleton instance — use [DatabaseHelper.instance] everywhere.
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  /// Returns the open database, initialising it on first access.
  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  // ── Schema ─────────────────────────────────────────────────────────────────

  /// v2: UNIQUE(package_name, date) prevents duplicate sync rows.
  static const _createAppUsage = '''
    CREATE TABLE IF NOT EXISTS app_usage (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      app_name     TEXT    NOT NULL,
      package_name TEXT    NOT NULL,
      usage_time   INTEGER NOT NULL,
      date         TEXT    NOT NULL,
      UNIQUE(package_name, date) ON CONFLICT REPLACE
    )
  ''';

  /// v3: Stores completed focus timer sessions.
  static const _createFocusSessions = '''
    CREATE TABLE IF NOT EXISTS focus_sessions (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      start_time TEXT    NOT NULL,
      end_time   TEXT    NOT NULL,
      duration   INTEGER NOT NULL
    )
  ''';

  /// v4: Stores per-app daily usage limits for Focus Mode.
  static const _createAppLimits = '''
    CREATE TABLE IF NOT EXISTS app_limits (
      id                   INTEGER PRIMARY KEY AUTOINCREMENT,
      package_name         TEXT    NOT NULL UNIQUE,
      app_name             TEXT    NOT NULL,
      daily_limit_minutes  INTEGER NOT NULL
    )
  ''';

  @visibleForTesting
  static Future<void> onCreate(Database db, int version) async {
    await db.execute(_createAppUsage);
    await db.execute(_createFocusSessions);
    await db.execute(_createAppLimits);
  }

  /// Incremental migrations — each block only runs if needed.
  @visibleForTesting
  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: add UNIQUE constraint (drop + recreate in dev).
      await db.execute('DROP TABLE IF EXISTS app_usage');
      await db.execute(_createAppUsage);
    }
    if (oldVersion < 3) {
      // v2 → v3: add focus_sessions table.
      await db.execute(_createFocusSessions);
    }
    if (oldVersion < 4) {
      // v3 → v4: add app_limits table for Focus Mode.
      await db.execute(_createAppLimits);
    }
  }

  /// Closes the database. Call only when the app is terminating.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
