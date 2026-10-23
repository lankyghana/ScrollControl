import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/error_logger.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../settings/domain/interrupt_settings.dart';
import '../../../usage/domain/repositories/usage_repository.dart';
import '../../domain/interrupt_config.dart';

/// Periodically queries usage stats and fires an interrupt notification
/// when a user exceeds the configured threshold on a single app.
///
/// Battery-safe design:
///   - Only one OS query per [InterruptConfig.checkIntervalSeconds] (1 min).
///   - Per-app cooldown prevents notification spam.
///   - Settings are read on every tick so changes take effect immediately.
///   - Timer is cancelled the moment [stop] is called.
class UsageMonitorService {
  UsageMonitorService({
    required UsageRepository repository,
    required NotificationSender notificationService,
    required InterruptSettings Function() getSettings,
  })  : _repo = repository,
        _notifications = notificationService,
        _getSettings = getSettings;

  final UsageRepository _repo;
  final NotificationSender _notifications;
  final InterruptSettings Function() _getSettings;

  Timer? _timer;

  /// packageName → last time a notification was shown for that app
  final Map<String, DateTime> _cooldowns = {};

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  void start() {
    if (_timer != null) return;
    if (kDebugMode) {
      debugPrint('[Monitor] started — '
          'interval=${InterruptConfig.checkIntervalSeconds}s');
    }
    _check();
    _timer = Timer.periodic(
      const Duration(seconds: InterruptConfig.checkIntervalSeconds),
      (_) => _check(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (kDebugMode) debugPrint('[Monitor] stopped');
  }

  // ── Core check ───────────────────────────────────────────────────────────────

  /// Runs a single check outside of the periodic timer. Exposed for tests so
  /// the threshold/cooldown logic can be exercised without waiting on real
  /// [Timer]s.
  @visibleForTesting
  Future<void> checkOnce() => _check();

  Future<void> _check() async {
    try {
      // 0. Respect the user's toggle.
      final settings = _getSettings();
      if (!settings.enabled) return;

      final thresholdSeconds = settings.thresholdMinutes * 60;
      final cooldownSeconds = settings.cooldownMinutes * 60;

      // 1. Which app is currently in the foreground?
      final foregroundPkg = await _repo.getForegroundApp();
      if (foregroundPkg == null) return;

      // 2. How long has the user been using it today?
      final usages = await _repo.fetchAndSyncUsage(DateTime.now());
      final entry = usages.cast<dynamic>().firstWhere(
            (u) => (u.packageName as String) == foregroundPkg,
            orElse: () => null,
          );
      if (entry == null) return;

      final usageSeconds = entry.usageTime as int;

      // 3. Exceeds threshold?
      if (usageSeconds < thresholdSeconds) return;

      // 4. Within cooldown window?
      final lastNotified = _cooldowns[foregroundPkg];
      if (lastNotified != null) {
        final elapsed = DateTime.now().difference(lastNotified).inSeconds;
        if (elapsed < cooldownSeconds) return;
      }

      // 5. Fire notification and record cooldown.
      final appName = entry.appName as String;
      final minutes = usageSeconds ~/ 60;

      _cooldowns[foregroundPkg] = DateTime.now();

      await _notifications.showInterruptNotification(
        appName: appName,
        minutes: minutes,
      );

      if (kDebugMode) debugPrint('[Monitor] interrupt fired for $appName (${minutes}m)');
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'UsageMonitorService._check');
    }
  }
}
