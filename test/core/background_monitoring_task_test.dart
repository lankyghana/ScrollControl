import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/core/background/background_monitoring_task.dart';
import 'package:scroll_control/core/notifications/notification_cooldown.dart';
import 'package:scroll_control/features/focus/domain/entities/app_limit.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';
import 'package:scroll_control/features/usage/domain/entities/app_usage.dart';

import '../helpers/fakes.dart';

class _RecordingSender extends FakeNotificationSender {
  final List<String> names = [];
  final List<int> used = [];

  @override
  Future<void> showLimitExceededNotification({
    required String appName,
    required int usedMinutes,
    required int limitMinutes,
  }) async {
    names.add(appName);
    used.add(usedMinutes);
    await super.showLimitExceededNotification(
      appName: appName,
      usedMinutes: usedMinutes,
      limitMinutes: limitMinutes,
    );
  }
}

AppUsage usage(String pkg, String name, int minutes) => AppUsage(
      appName: name,
      packageName: pkg,
      usageTime: minutes * 60,
      date: DateTime(2026, 3, 10),
    );

void main() {
  late _RecordingSender sender;
  late InMemoryCooldownStore store;
  late NotificationGate gate;
  late FocusSettings settings;
  late List<AppUsage> usages;
  final t0 = DateTime(2026, 3, 10, 10, 0);

  Future<void> run(DateTime now) => runBackgroundMonitoring(
        loadSettings: () async => settings,
        fetchUsage: (_) async => usages,
        notifications: sender,
        gate: gate,
        now: now,
      );

  setUp(() {
    sender = _RecordingSender();
    store = InMemoryCooldownStore();
    gate = NotificationGate(store);
    settings = const FocusSettings(
      isEnabled: true,
      globalLimitMinutes: 60,
      perAppLimits: [
        AppLimit(packageName: 'com.a', appName: 'App A', dailyLimitMinutes: 30),
      ],
    );
    usages = [usage('com.a', 'App A', 40), usage('com.b', 'App B', 30)];
  });

  test('does nothing when Focus Mode is disabled', () async {
    settings = settings.copyWith(isEnabled: false);
    await run(t0);
    expect(sender.limitExceededCalls, 0);
  });

  test('does nothing with no usage data (e.g. permission revoked)', () async {
    usages = [];
    await run(t0);
    expect(sender.limitExceededCalls, 0);
  });

  test('global limit reports the complete total (70), once, not a partial sum', () async {
    await run(t0);
    expect(sender.names, ['App A', 'Total Screen Time']);
    expect(sender.used, [40, 70]);
  });

  test('per-app and global notifications are independent', () async {
    settings = settings.copyWith(globalLimitMinutes: 600);
    await run(t0);
    expect(sender.names, ['App A']);

    sender = _RecordingSender();
    settings = settings.copyWith(globalLimitMinutes: 60);
    usages = [usage('com.a', 'App A', 5), usage('com.b', 'App B', 90)];
    await run(DateTime(2026, 3, 11, 10, 0)); // next day: state reset
    expect(sender.names, ['Total Screen Time']);
  });

  test('does not repeat the same notification on later hourly runs', () async {
    await run(t0);
    final first = sender.limitExceededCalls;
    await run(t0.add(const Duration(hours: 1)));
    await run(t0.add(const Duration(hours: 2)));
    expect(sender.limitExceededCalls, first);
  });

  test('notifies again the next day', () async {
    await run(t0);
    final first = sender.limitExceededCalls;
    await run(DateTime(2026, 3, 11, 10, 0));
    expect(sender.limitExceededCalls, first * 2);
  });

  test('skips an event the foreground monitor already announced today', () async {
    // Foreground used the same gate keys.
    await gate.tryAcquire('limit:app:com.a',
        cooldown: const Duration(minutes: 10), now: t0.subtract(const Duration(hours: 2)));
    await run(t0);
    expect(sender.names, ['Total Screen Time']);
  });
}
