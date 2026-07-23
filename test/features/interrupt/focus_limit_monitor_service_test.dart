import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/focus/domain/entities/app_limit.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';
import 'package:scroll_control/features/interrupt/data/services/focus_limit_monitor_service.dart';
import 'package:scroll_control/features/usage/domain/entities/app_usage.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeUsageRepository usageRepo;
  late FakeFocusLimitsRepository focusLimitsRepo;
  late FakeNotificationSender notifications;
  late FocusLimitMonitorService service;

  AppUsage usage(String pkg, String name, int minutes) => AppUsage(
        appName: name,
        packageName: pkg,
        usageTime: minutes * 60,
        date: DateTime.now(),
      );

  setUp(() {
    usageRepo = FakeUsageRepository();
    focusLimitsRepo = FakeFocusLimitsRepository();
    notifications = FakeNotificationSender();
    service = FocusLimitMonitorService(
      usageRepository: usageRepo,
      focusLimitsRepository: focusLimitsRepo,
      notificationService: notifications,
    );
  });

  test('does nothing when Focus Mode is disabled', () async {
    focusLimitsRepo.settings = FocusSettings.disabled;
    usageRepo.dailyUsage = [usage('com.example.app', 'Example', 45)];

    await service.checkOnce();

    expect(notifications.limitExceededCalls, 0);
  });

  test('does nothing when enabled but no per-app limits are set', () async {
    focusLimitsRepo.settings = const FocusSettings(isEnabled: true, perAppLimits: []);
    usageRepo.dailyUsage = [usage('com.example.app', 'Example', 45)];

    await service.checkOnce();

    expect(notifications.limitExceededCalls, 0);
  });

  test('does nothing while usage is under the limit', () async {
    focusLimitsRepo.settings = const FocusSettings(
      isEnabled: true,
      perAppLimits: [
        AppLimit(packageName: 'com.example.app', appName: 'Example', dailyLimitMinutes: 30),
      ],
    );
    usageRepo.dailyUsage = [usage('com.example.app', 'Example', 29)];

    await service.checkOnce();

    expect(notifications.limitExceededCalls, 0);
  });

  test('fires a limit-exceeded notification once the limit is reached', () async {
    focusLimitsRepo.settings = const FocusSettings(
      isEnabled: true,
      perAppLimits: [
        AppLimit(packageName: 'com.example.app', appName: 'Example', dailyLimitMinutes: 30),
      ],
    );
    usageRepo.dailyUsage = [usage('com.example.app', 'Example', 30)];

    String? notifiedApp;
    int? notifiedUsed;
    int? notifiedLimit;
    service.onLimitExceeded = (appName, used, limit) {
      notifiedApp = appName;
      notifiedUsed = used;
      notifiedLimit = limit;
    };

    await service.checkOnce();

    expect(notifications.limitExceededCalls, 1);
    expect(notifications.lastLimitAppName, 'Example');
    expect(notifiedApp, 'Example');
    expect(notifiedUsed, 30);
    expect(notifiedLimit, 30);
  });

  test('suppresses a repeat notification for the same app within the cooldown', () async {
    focusLimitsRepo.settings = const FocusSettings(
      isEnabled: true,
      perAppLimits: [
        AppLimit(packageName: 'com.example.app', appName: 'Example', dailyLimitMinutes: 30),
      ],
    );
    usageRepo.dailyUsage = [usage('com.example.app', 'Example', 35)];

    await service.checkOnce();
    await service.checkOnce();

    expect(notifications.limitExceededCalls, 1);
  });

  test('fires independently for two different apps that both exceed their limits', () async {
    focusLimitsRepo.settings = const FocusSettings(
      isEnabled: true,
      perAppLimits: [
        AppLimit(packageName: 'com.a', appName: 'App A', dailyLimitMinutes: 10),
        AppLimit(packageName: 'com.b', appName: 'App B', dailyLimitMinutes: 20),
      ],
    );
    usageRepo.dailyUsage = [
      usage('com.a', 'App A', 15),
      usage('com.b', 'App B', 25),
    ];

    await service.checkOnce();

    expect(notifications.limitExceededCalls, 2);
  });
}
