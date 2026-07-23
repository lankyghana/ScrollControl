import 'package:scroll_control/core/notifications/notification_service.dart';
import 'package:scroll_control/features/focus/domain/entities/app_limit.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';
import 'package:scroll_control/features/focus/domain/repositories/focus_limits_repository.dart';
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
