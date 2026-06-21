import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/cleanup_repository.dart';

/// Service that manages automatic data cleanup with daily throttling.
///
/// - Tracks last cleanup time in SharedPreferences
/// - Ensures cleanup runs at most once per 24 hours
/// - Provides logging for debugging
class CleanupService {
  CleanupService({required CleanupRepository repository})
      : _repository = repository;

  final CleanupRepository _repository;
  static const _lastCleanupKey = 'last_cleanup_timestamp';

  /// Runs cleanup if last cleanup was more than 24 hours ago.
  /// Returns true if cleanup was performed, false if skipped (throttled).
  Future<bool> runCleanupIfNeeded() async {
    try {
      final lastCleanup = await _getLastCleanupTime();
      final now = DateTime.now();

      // Check if 24 hours have passed since last cleanup
      if (lastCleanup != null && now.difference(lastCleanup).inHours < 24) {
        if (kDebugMode) {
          debugPrint('[CleanupService] Cleanup skipped (throttled). '
              'Last cleanup was ${now.difference(lastCleanup).inHours}h ago');
        }
        return false;
      }

      // Run cleanup
      if (kDebugMode) {
        debugPrint('[CleanupService] Running cleanup...');
      }

      final stats = await _repository.runCleanup();

      // Save cleanup timestamp
      await _saveCleanupTime(now);

      if (kDebugMode) {
        debugPrint('[CleanupService] Cleanup completed. '
            'app_usage deleted: ${stats['app_usage_deleted']}, '
            'focus_sessions deleted: ${stats['focus_sessions_deleted']}');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CleanupService] Error during cleanup: $e');
      }
      return false;
    }
  }

  /// Clears all data immediately (used for reset/settings).
  /// Returns deletion stats from both tables.
  Future<Map<String, int>> clearAllData() async {
    try {
      if (kDebugMode) {
        debugPrint('[CleanupService] Clearing ALL data...');
      }

      final result = await _repository.clearAllData();

      if (kDebugMode) {
        debugPrint('[CleanupService] All data cleared. '
            'app_usage: ${result['app_usage']}, '
            'focus_sessions: ${result['focus_sessions']}');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CleanupService] Error clearing data: $e');
      }
      return {};
    }
  }

  /// Gets the timestamp of the last cleanup.
  Future<DateTime?> _getLastCleanupTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastCleanupKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CleanupService] Error getting last cleanup time: $e');
      }
    }
    return null;
  }

  /// Saves the current time as the last cleanup time.
  Future<void> _saveCleanupTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCleanupKey, time.millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[CleanupService] Error saving cleanup time: $e');
      }
    }
  }
}
