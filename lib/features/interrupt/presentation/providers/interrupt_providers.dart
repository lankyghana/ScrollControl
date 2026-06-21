import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../../settings/domain/interrupt_settings.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../usage/presentation/providers/usage_providers.dart';
import '../../../focus/presentation/providers/focus_providers.dart';
import '../../../focus/presentation/providers/limit_exceeded_provider.dart';
import '../../data/services/usage_monitor_service.dart';
import '../../data/services/focus_limit_monitor_service.dart';

// ── Notification service ──────────────────────────────────────────────────────

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService.instance,
);

// ── Monitor service ───────────────────────────────────────────────────────────

final usageMonitorServiceProvider = Provider<UsageMonitorService>((ref) {
  final service = UsageMonitorService(
    repository: ref.watch(usageRepositoryProvider),
    notificationService: ref.watch(notificationServiceProvider),
    // Read latest settings on every timer tick — changes apply immediately.
    getSettings: () =>
        ref.read(interruptSettingsProvider).valueOrNull ??
        InterruptSettings.defaults,
  );
  ref.onDispose(service.stop);
  return service;
});

final focusLimitMonitorServiceProvider =
    Provider<FocusLimitMonitorService>((ref) {
  final service = FocusLimitMonitorService(
    usageRepository: ref.watch(usageRepositoryProvider),
    focusLimitsRepository: ref.watch(focusLimitsRepositoryProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );

  // Wire up callback to update limit exceeded state
  service.onLimitExceeded = (appName, usedMinutes, limitMinutes) {
    ref.read(limitExceededProvider.notifier).markLimitExceeded(appName);
  };

  ref.onDispose(service.stop);
  return service;
});

// ── Initialiser ───────────────────────────────────────────────────────────────

/// Watch this provider in the root widget to auto-start and auto-stop
/// the monitor with the Riverpod scope lifecycle.
final monitorInitProvider = Provider<void>((ref) {
  ref.watch(usageMonitorServiceProvider).start();
  ref.watch(focusLimitMonitorServiceProvider).start();
});
