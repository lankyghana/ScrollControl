import '../entities/app_limit.dart';
import '../entities/focus_settings.dart';

/// Pure domain contract for managing Focus Mode settings and app limits.
abstract interface class FocusLimitsRepository {
  /// Load the current focus settings (enable state, global/per-app limits).
  Future<FocusSettings> loadSettings();

  /// Save focus settings (enable state and limits).
  Future<void> saveSettings(FocusSettings settings);

  /// Get the limit for a specific app by package name.
  /// Returns null if no limit is set for that app.
  Future<AppLimit?> getAppLimit(String packageName);

  /// Set or update the daily limit for an app.
  Future<void> setAppLimit(AppLimit limit);

  /// Remove the limit for an app.
  Future<void> removeAppLimit(String packageName);

  /// Get all tracked app limits.
  Future<List<AppLimit>> getAllLimits();
}
