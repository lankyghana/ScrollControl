import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/app_limit_model.dart';
import '../models/focus_settings_model.dart';
import '../../../../core/database/database_helper.dart';

class FocusLimitsLocalDatasource {
  static const _keyFocusSettings = 'focus_settings_json';

  /// Load focus settings from SharedPreferences.
  /// Returns default disabled settings if not found.
  Future<FocusSettingsModel> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keyFocusSettings);

    if (json == null) {
      return const FocusSettingsModel(
        isEnabled: false,
        globalLimitMinutes: null,
        perAppLimits: [],
      );
    }

    return FocusSettingsModel.fromJson(json);
  }

  /// Save focus settings to SharedPreferences.
  Future<void> saveSettings(FocusSettingsModel settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFocusSettings, settings.toJson());
  }

  /// Get a specific app limit from SQLite.
  Future<AppLimitModel?> getAppLimit(String packageName) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      'app_limits',
      where: 'package_name = ?',
      whereArgs: [packageName],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return AppLimitModel.fromMap(result.first);
  }

  /// Insert or update an app limit in SQLite.
  Future<void> setAppLimit(AppLimitModel limit) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'app_limits',
      limit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Remove an app limit from SQLite.
  Future<void> removeAppLimit(String packageName) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(
      'app_limits',
      where: 'package_name = ?',
      whereArgs: [packageName],
    );
  }

  /// Get all app limits from SQLite.
  Future<List<AppLimitModel>> getAllLimits() async {
    final db = await DatabaseHelper.instance.database;
    final results = await db.query('app_limits');
    return results.map(AppLimitModel.fromMap).toList();
  }
}
