import 'package:scroll_control/core/notifications/notification_service.dart';
import 'package:scroll_control/features/blocking/domain/block_snapshot.dart';
import 'package:scroll_control/features/blocking/domain/blocker_platform.dart';
import 'package:scroll_control/features/blocking/domain/blocking_coordinator.dart';
import 'package:scroll_control/features/focus/domain/entities/app_limit.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';
import 'package:scroll_control/features/focus/domain/repositories/focus_limits_repository.dart';
import 'package:scroll_control/features/home/presentation/providers/focus_session_store.dart';
import 'package:scroll_control/features/usage/domain/entities/app_usage.dart';
import 'package:scroll_control/features/usage/domain/entities/daily_usage_summary.dart';
import 'package:scroll_control/features/usage/domain/repositories/usage_repository.dart';

/// In-memory [UsageRepository] fake — no SQLite, no MethodChannel.
class FakeUsageRepository implements UsageRepository {
  String? foregroundApp;
  List<AppUsage> dailyUsage = const [];

  @override
  Future<String?> getForegroundApp() async => foregroundApp;

  @override
  Future<List<AppUsage>> getDailyUsage(DateTime date) async => dailyUsage;

  @override
  Future<void> saveUsage(AppUsage usage) async {}

  @override
  Future<List<AppUsage>> fetchAndSyncUsage(DateTime date) async => dailyUsage;

  @override
  Future<bool> hasUsagePermission() async => true;

  @override
  Future<List<DailyUsageSummary>> getUsageLast7Days() async => const [];
}

/// In-memory [FocusLimitsRepository] fake.
class FakeFocusLimitsRepository implements FocusLimitsRepository {
  FocusSettings settings = FocusSettings.disabled;
  final Map<String, AppLimit> _limits = {};

  @override
  Future<FocusSettings> loadSettings() async => settings;

  @override
  Future<void> saveSettings(FocusSettings newSettings) async {
    settings = newSettings;
  }

  @override
  Future<AppLimit?> getAppLimit(String packageName) async => _limits[packageName];

  @override
  Future<void> setAppLimit(AppLimit limit) async {
    _limits[limit.packageName] = limit;
  }

  @override
  Future<void> removeAppLimit(String packageName) async {
    _limits.remove(packageName);
  }

  @override
  Future<List<AppLimit>> getAllLimits() async => _limits.values.toList();
}

/// Records calls instead of showing real system notifications.
class FakeNotificationSender implements NotificationSender {
  int interruptCalls = 0;
  String? lastInterruptAppName;
  int? lastInterruptMinutes;

  int limitExceededCalls = 0;
  String? lastLimitAppName;
  int? lastLimitUsedMinutes;
  int? lastLimitLimitMinutes;

  @override
  Future<void> showInterruptNotification({
    required String appName,
    required int minutes,
  }) async {
    interruptCalls++;
    lastInterruptAppName = appName;
    lastInterruptMinutes = minutes;
  }

  @override
  Future<void> showLimitExceededNotification({
    required String appName,
    required int usedMinutes,
    required int limitMinutes,
  }) async {
    limitExceededCalls++;
    lastLimitAppName = appName;
    lastLimitUsedMinutes = usedMinutes;
    lastLimitLimitMinutes = limitMinutes;
  }
}

// ── App blocking fakes ───────────────────────────────────────────────────────

/// Records every call so tests can assert exactly what the blocker was told.
class FakeBlockerPlatform implements BlockerPlatform {
  BlockerPermissions perms =
      const BlockerPermissions(usageAccess: true, overlay: true);
  BlockerRuntimeStatus runtime = const BlockerRuntimeStatus();

  /// When set, [startService] throws it (service unavailable / restricted).
  BlockerUnavailableException? startFailure;

  /// When set, [permissions] throws it.
  BlockerUnavailableException? permissionsFailure;

  final List<BlockSnapshot> applied = [];
  int startCalls = 0;
  int stopCalls = 0;
  int overlaySettingsOpened = 0;
  int usageSettingsOpened = 0;
  bool running = false;

  BlockSnapshot? get lastSnapshot => applied.isEmpty ? null : applied.last;

  @override
  Future<BlockerPermissions> permissions() async {
    final failure = permissionsFailure;
    if (failure != null) throw failure;
    return perms;
  }

  @override
  Future<BlockerRuntimeStatus> status() async => runtime;

  @override
  Future<void> openOverlaySettings() async => overlaySettingsOpened++;

  @override
  Future<void> openUsageSettings() async => usageSettingsOpened++;

  @override
  Future<void> openBatterySettings() async {}

  @override
  Future<void> applySnapshot(BlockSnapshot snapshot) async =>
      applied.add(snapshot);

  @override
  Future<void> startService() async {
    final failure = startFailure;
    if (failure != null) throw failure;
    startCalls++;
    running = true;
  }

  @override
  Future<void> stopService() async {
    stopCalls++;
    running = false;
  }

  @override
  Future<List<LaunchableApp>> launchableApps() async => const [];

  @override
  Future<String?> consumePendingRoute() async => null;
}

class FakeBlockingEnabledStore implements BlockingEnabledStore {
  FakeBlockingEnabledStore({this.enabled = false});

  bool enabled;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async => enabled = value;
}

/// In-memory Focus Session persistence: survives a "reboot" (new container).
class FakeFocusSessionStore implements FocusSessionStore {
  SavedFocusSession? saved;

  @override
  Future<SavedFocusSession?> load() async => saved;

  @override
  Future<void> save(SavedFocusSession session) async => saved = session;
}
