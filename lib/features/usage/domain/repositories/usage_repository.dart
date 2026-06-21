import '../entities/app_usage.dart';
import '../entities/daily_usage_summary.dart';

/// Pure domain contract — no SQLite, no Flutter, no Riverpod.
abstract interface class UsageRepository {
  /// Persist a single usage entry.
  Future<void> saveUsage(AppUsage usage);

  /// Return all usage entries recorded on [date] (by calendar day).
  /// Returns an empty list when no data exists for that day.
  Future<List<AppUsage>> getDailyUsage(DateTime date);

  /// Pull live usage stats from the OS for [date], persist them to SQLite,
  /// and return the full merged list for that day.
  ///
  /// Returns an empty list when the user has not granted Usage Access or
  /// the app is running on a non-Android platform.
  Future<List<AppUsage>> fetchAndSyncUsage(DateTime date);

  /// Returns true when the OS has granted Usage Access permission.
  Future<bool> hasUsagePermission();

  /// Returns the package name of the app currently in the foreground.
  /// Returns null when permission is denied or platform is non-Android.
  Future<String?> getForegroundApp();

  /// Returns total screen time per day for the last 7 days, oldest first.
  Future<List<DailyUsageSummary>> getUsageLast7Days();
}
