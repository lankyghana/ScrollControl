import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/interrupt/data/services/usage_monitor_service.dart';
import 'package:scroll_control/features/settings/domain/interrupt_settings.dart';
import 'package:scroll_control/features/usage/domain/entities/app_usage.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeUsageRepository repo;
  late FakeNotificationSender notifications;
  late InterruptSettings settings;
  late UsageMonitorService service;

  AppUsage usage(String pkg, String name, int minutes) => AppUsage(
        appName: name,
        packageName: pkg,
        usageTime: minutes * 60,
        date: DateTime.now(),
      );

  setUp(() {
    repo = FakeUsageRepository();
    notifications = FakeNotificationSender();
    settings = InterruptSettings.defaults.copyWith(thresholdMinutes: 5, cooldownMinutes: 15);
    service = UsageMonitorService(
      repository: repo,
      notificationService: notifications,
      getSettings: () => settings,
    );
  });

  test('does nothing when Smart Interrupt is disabled', () async {
    settings = settings.copyWith(enabled: false);
    repo.foregroundApp = 'com.example.app';
    repo.dailyUsage = [usage('com.example.app', 'Example', 10)];

    await service.checkOnce();

    expect(notifications.interruptCalls, 0);
  });

  test('does nothing when no app is in the foreground', () async {
    repo.foregroundApp = null;
    repo.dailyUsage = [usage('com.example.app', 'Example', 10)];

    await service.checkOnce();

    expect(notifications.interruptCalls, 0);
  });

  test('does nothing when the foreground app has no usage recorded yet', () async {
    repo.foregroundApp = 'com.example.app';
    repo.dailyUsage = const [];

    await service.checkOnce();

    expect(notifications.interruptCalls, 0);
  });

  test('does nothing while usage is under the threshold', () async {
    repo.foregroundApp = 'com.example.app';
    repo.dailyUsage = [usage('com.example.app', 'Example', 4)];

    await service.checkOnce();

    expect(notifications.interruptCalls, 0);
  });

  test('fires an interrupt once usage reaches the threshold', () async {
    repo.foregroundApp = 'com.example.app';
    repo.dailyUsage = [usage('com.example.app', 'Example', 5)];

    await service.checkOnce();

    expect(notifications.interruptCalls, 1);
    expect(notifications.lastInterruptAppName, 'Example');
    expect(notifications.lastInterruptMinutes, 5);
  });

  test('suppresses a repeat interrupt for the same app within the cooldown', () async {
    repo.foregroundApp = 'com.example.app';
    repo.dailyUsage = [usage('com.example.app', 'Example', 5)];

    await service.checkOnce();
    await service.checkOnce();

    expect(notifications.interruptCalls, 1);
  });

  test('fires again immediately when the cooldown is 0', () async {
    settings = settings.copyWith(cooldownMinutes: 0);
    repo.foregroundApp = 'com.example.app';
    repo.dailyUsage = [usage('com.example.app', 'Example', 5)];

    await service.checkOnce();
    await service.checkOnce();

    expect(notifications.interruptCalls, 2);
  });

  test('tracks cooldowns per app independently', () async {
    repo.foregroundApp = 'com.a';
    repo.dailyUsage = [usage('com.a', 'App A', 5)];
    await service.checkOnce(); // fires + starts cooldown for com.a

    repo.foregroundApp = 'com.b';
    repo.dailyUsage = [usage('com.b', 'App B', 5)];
    await service.checkOnce(); // com.b has no cooldown yet, should fire

    expect(notifications.interruptCalls, 2);
  });
}
