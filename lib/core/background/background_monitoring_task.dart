import '../../features/focus/data/datasources/focus_limits_local_datasource.dart';
import '../../features/focus/domain/entities/focus_settings.dart';
import '../../features/focus/domain/limit_evaluator.dart';
import '../../features/usage/data/datasources/usage_stats_datasource.dart';
import '../../features/usage/domain/entities/app_usage.dart';
import '../errors/error_logger.dart';
import '../notifications/notification_cooldown.dart';
import '../notifications/notification_service.dart';

/// Background task that runs periodically to check app limits and send notifications.
/// Called by WorkManager when the app is in the background.
///
/// Android may delay or skip WorkManager runs (Doze, battery saver, OEM
/// task killers), so this is a best-effort safety net, not real-time
/// monitoring.
Future<void> backgroundMonitoringTask() async {
  try {
    final notificationService = NotificationService.instance;

    // Initialize the notification service for background context
    await notificationService.init();

    const usageDataSource = AndroidUsageStatsDatasource();
    await runBackgroundMonitoring(
      loadSettings: FocusLimitsLocalDatasource().loadSettings,
      fetchUsage: usageDataSource.fetchUsageStats,
      notifications: notificationService,
      gate: NotificationGate(const PrefsCooldownStore()),
    );
  } catch (e, st) {
    ErrorLogger.log(e, st, context: 'backgroundMonitoringTask');
  }
}

/// Minimum gap before the background task repeats a limit notification that
/// the foreground monitor already showed. The background task itself notifies
/// at most once per day per limit.
const backgroundNotifyCooldown = Duration(minutes: 10);

/// Testable core of [backgroundMonitoringTask]: all collaborators are injected.
///
/// Each exceeded limit (per-app or global) notifies at most once per calendar
/// day, and not at all if the foreground monitor already notified for it today
/// (both share the same [NotificationGate] keys).
Future<void> runBackgroundMonitoring({
  required Future<FocusSettings> Function() loadSettings,
  required Future<List<AppUsage>> Function(DateTime date) fetchUsage,
  required NotificationSender notifications,
  required NotificationGate gate,
  DateTime? now,
}) async {
  final at = now ?? DateTime.now();

  final settings = await loadSettings();
  if (!settings.isEnabled) return;

  final usages = await fetchUsage(at);
  if (usages.isEmpty) return;

  final breaches = LimitEvaluator.evaluate(settings: settings, usages: usages);

  for (final breach in breaches) {
    final allowed = await gate.tryAcquire(
      breach.key,
      cooldown: backgroundNotifyCooldown,
      oncePerDay: true,
      now: at,
    );
    if (!allowed) continue;

    await notifications.showLimitExceededNotification(
      appName: breach.displayName,
      usedMinutes: breach.usedMinutes,
      limitMinutes: breach.limitMinutes,
    );
  }
}
