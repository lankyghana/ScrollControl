import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/error_logger.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../focus/domain/repositories/focus_limits_repository.dart';
import '../../../usage/domain/repositories/usage_repository.dart';

/// Monitors daily app usage against Focus Mode limits.
///
/// When an app exceeds its daily limit, fires a limit-exceeded notification.
/// Battery-safe design:
///   - Only one OS query per [checkIntervalSeconds] (1 min).
///   - Per-app cooldown prevents notification spam.
///   - Settings are read on every tick so changes take effect immediately.
class FocusLimitMonitorService {
  FocusLimitMonitorService({
    required UsageRepository usageRepository,
    required FocusLimitsRepository focusLimitsRepository,
    required NotificationSender notificationService,
  })  : _usageRepo = usageRepository,
        _focusLimitsRepo = focusLimitsRepository,
        _notifications = notificationService;

  static const checkIntervalSeconds = 60; // Check every minute

  /// Minimum gap between two limit-exceeded notifications for the same app.
  static const limitCooldownSeconds = 600; // 10 minutes

  final UsageRepository _usageRepo;
  final FocusLimitsRepository _focusLimitsRepo;
  final NotificationSender _notifications;

  Timer? _timer;

  /// Callback when an app exceeds its daily limit.
  /// Called with (appName, usedMinutes, limitMinutes)
  void Function(String, int, int)? onLimitExceeded;

  /// packageName → last time a limit-reached notification was shown
  final Map<String, DateTime> _limitCooldowns = {};

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  void start() {
    if (_timer != null) return;
    if (kDebugMode) {
      debugPrint(
          '[FocusLimitMonitor] started — interval=${checkIntervalSeconds}s');
    }
    _check();
    _timer = Timer.periodic(
      const Duration(seconds: checkIntervalSeconds),
      (_) => _check(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (kDebugMode) debugPrint('[FocusLimitMonitor] stopped');
  }

  // ── Core check ───────────────────────────────────────────────────────────────

  /// Runs a single check outside of the periodic timer. Exposed for tests so
  /// the limit/cooldown logic can be exercised without waiting on real
  /// [Timer]s.
  @visibleForTesting
  Future<void> checkOnce() => _check();

  Future<void> _check() async {
    try {
      // Get current focus settings
      final focusSettings = await _focusLimitsRepo.loadSettings();

      // If Focus Mode is disabled, skip check
      if (!focusSettings.isEnabled || focusSettings.perAppLimits.isEmpty) {
        return;
      }

      // Get today's usage
      final now = DateTime.now();
      final usages = await _usageRepo.getDailyUsage(now);

      // Check each app's limit
      for (final appLimit in focusSettings.perAppLimits) {
        final matchingUsages =
            usages.where((u) => u.packageName == appLimit.packageName).toList();
        if (matchingUsages.isEmpty) continue; // App notth used today

        final usage = matchingUsages.first;

        final usageMinutes = usage.usageTime ~/ 60;
        final limitMinutes = appLimit.dailyLimitMinutes;

        // If limit exceeded and not on cooldown, fire notification
        if (usageMinutes >= limitMinutes) {
          final lastNotified = _limitCooldowns[appLimit.packageName];

          // Cooldown: don't spam notifications (check every 10 minutes)
          if (lastNotified != null) {
            final elapsedSeconds =
                DateTime.now().difference(lastNotified).inSeconds;
            if (elapsedSeconds < limitCooldownSeconds) continue;
          }

          // Fire notification
          _limitCooldowns[appLimit.packageName] = DateTime.now();

          await _notifications.showLimitExceededNotification(
            appName: appLimit.appName,
            usedMinutes: usageMinutes,
            limitMinutes: limitMinutes,
          );

          // Signal to app state that limit was exceeded
          onLimitExceeded?.call(appLimit.appName, usageMinutes, limitMinutes);

          if (kDebugMode) {
            debugPrint(
              '[FocusLimitMonitor] limit exceeded for ${appLimit.appName} '
              '(${usageMinutes}m / ${limitMinutes}m)',
            );
          }
        }
      }
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusLimitMonitorService._check');
    }
  }
}
