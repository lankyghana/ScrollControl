import 'package:flutter/foundation.dart';
import '../../features/focus/data/datasources/focus_limits_local_datasource.dart';
import '../../features/usage/data/datasources/usage_stats_datasource.dart';
import '../notifications/notification_service.dart';

/// Background task that runs periodically to check app limits and send notifications.
/// Called by WorkManager when the app is in the background.
Future<void> backgroundMonitoringTask() async {
  try {
    debugPrint('[BackgroundTask] Starting background monitoring');

    final notificationService = NotificationService.instance;

    // Initialize the notification service for background context
    await notificationService.init();

    // Load focus settings
    final focusDataSource = FocusLimitsLocalDatasource();
    final focusSettings = await focusDataSource.loadSettings();

    // Only proceed if Focus Mode is enabled
    if (!focusSettings.isEnabled) {
      debugPrint('[BackgroundTask] Focus Mode disabled, skipping checks');
      return;
    }

    debugPrint('[BackgroundTask] Focus Mode enabled, checking limits...');

    // Get current usage stats
    const usageDataSource = AndroidUsageStatsDatasource();
    final today = DateTime.now();
    final usageStats = await usageDataSource.fetchUsageStats(today);

    if (usageStats.isEmpty) {
      debugPrint('[BackgroundTask] No usage stats available');
      return;
    }

    // Check each app's usage against limits
    int totalUsageSeconds = 0;

    for (final stat in usageStats) {
      totalUsageSeconds += stat.usageTime;

      // Check per-app limits
      for (final limit in focusSettings.perAppLimits) {
        if (limit.packageName == stat.packageName) {
          final usageMinutes = stat.usageTime ~/ 60;
          if (usageMinutes > limit.dailyLimitMinutes) {
            debugPrint(
                '[BackgroundTask] ${stat.appName} exceeded limit: $usageMinutes / ${limit.dailyLimitMinutes} min');

            // Send notification
            await notificationService.showLimitExceededNotification(
              appName: stat.appName,
              usedMinutes: usageMinutes,
              limitMinutes: limit.dailyLimitMinutes,
            );
          }
          break;
        }
      }

      // Check global limit
      final globalLimit = focusSettings.globalLimitMinutes;
      if (globalLimit != null) {
        final totalUsageMinutes = totalUsageSeconds ~/ 60;
        if (totalUsageMinutes > globalLimit) {
          debugPrint(
              '[BackgroundTask] Global limit exceeded: $totalUsageMinutes / $globalLimit min');

          // Send global notification
          await notificationService.showLimitExceededNotification(
            appName: 'Total Screen Time',
            usedMinutes: totalUsageMinutes,
            limitMinutes: globalLimit,
          );
          break; // Only send once per check cycle
        }
      }
    }

    debugPrint('[BackgroundTask] Background monitoring completed');
  } catch (e) {
    debugPrint('[BackgroundTask] Error: $e');
  }
}
