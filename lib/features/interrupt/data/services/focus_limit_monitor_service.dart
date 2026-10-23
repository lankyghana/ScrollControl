import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/errors/error_logger.dart';
import '../../../../core/notifications/notification_cooldown.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../focus/domain/limit_evaluator.dart';
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
    NotificationCooldownStore? cooldownStore,
  })  : _usageRepo = usageRepository,
        _focusLimitsRepo = focusLimitsRepository,
        _notifications = notificationService,
        _gate = NotificationGate(cooldownStore ?? InMemoryCooldownStore());

  static const checkIntervalSeconds = 60; // Check every minute

  /// Minimum gap between two limit-exceeded notifications for the same app.
  static const limitCooldownSeconds = 600; // 10 minutes

  final UsageRepository _usageRepo;
  final FocusLimitsRepository _focusLimitsRepo;
  final NotificationSender _notifications;
  final NotificationGate _gate;

  Timer? _timer;

  /// Callback when an app is at or over its daily limit. Called on every
  /// check while the limit is exceeded (not only when a notification fires),
  /// with (appName, usedMinutes, limitMinutes).
  void Function(String, int, int)? onLimitExceeded;

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
      if (!focusSettings.isEnabled ||
          (focusSettings.perAppLimits.isEmpty &&
              focusSettings.globalLimitMinutes == null)) {
        return;
      }

      // Get today's usage, synced live from the OS (the SQLite cache alone
      // is only as fresh as the last Home screen refresh).
      final now = DateTime.now();
      final usages = await _usageRepo.fetchAndSyncUsage(now);

      final breaches = LimitEvaluator.evaluate(
        settings: focusSettings,
        usages: usages,
      );

      for (final breach in breaches) {
        // The overlay state reflects the breach regardless of whether a
        // notification is due.
        if (!breach.isGlobal) {
          onLimitExceeded?.call(
              breach.displayName, breach.usedMinutes, breach.limitMinutes);
        }

        // Cooldown shared with the background task, so the same breach is
        // never announced twice.
        final allowed = await _gate.tryAcquire(
          breach.key,
          cooldown: const Duration(seconds: limitCooldownSeconds),
          now: now,
        );
        if (!allowed) continue;

        await _notifications.showLimitExceededNotification(
          appName: breach.displayName,
          usedMinutes: breach.usedMinutes,
          limitMinutes: breach.limitMinutes,
        );

        if (kDebugMode) {
          debugPrint(
            '[FocusLimitMonitor] limit exceeded for ${breach.displayName} '
            '(${breach.usedMinutes}m / ${breach.limitMinutes}m)',
          );
        }
      }
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusLimitMonitorService._check');
    }
  }
}
