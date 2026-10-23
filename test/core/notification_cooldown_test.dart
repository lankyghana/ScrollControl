import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/core/notifications/notification_cooldown.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('NotificationGate', () {
    late InMemoryCooldownStore store;
    late NotificationGate gate;
    final t0 = DateTime(2026, 3, 10, 10, 0);

    setUp(() {
      store = InMemoryCooldownStore();
      gate = NotificationGate(store);
    });

    test('first event is allowed and recorded', () async {
      expect(await gate.tryAcquire('k', cooldown: const Duration(minutes: 10), now: t0), isTrue);
      expect(await store.lastNotified('k'), t0);
    });

    test('repeat inside the cooldown is suppressed and does not extend it', () async {
      const cd = Duration(minutes: 10);
      await gate.tryAcquire('k', cooldown: cd, now: t0);
      expect(await gate.tryAcquire('k', cooldown: cd, now: t0.add(const Duration(minutes: 9))), isFalse);
      expect(await store.lastNotified('k'), t0);
      expect(await gate.tryAcquire('k', cooldown: cd, now: t0.add(const Duration(minutes: 10))), isTrue);
    });

    test('keys are independent', () async {
      const cd = Duration(minutes: 10);
      await gate.tryAcquire('a', cooldown: cd, now: t0);
      expect(await gate.tryAcquire('b', cooldown: cd, now: t0), isTrue);
    });

    test('oncePerDay suppresses any later event the same day', () async {
      const cd = Duration(minutes: 10);
      await gate.tryAcquire('k', cooldown: cd, oncePerDay: true, now: t0);
      expect(
        await gate.tryAcquire('k', cooldown: cd, oncePerDay: true, now: t0.add(const Duration(hours: 9))),
        isFalse,
      );
    });

    test('state resets on a new calendar day (midnight)', () async {
      const cd = Duration(hours: 5);
      final late = DateTime(2026, 3, 10, 23, 55);
      await gate.tryAcquire('k', cooldown: cd, oncePerDay: true, now: late);
      // Only 10 minutes later, but it is a new day.
      expect(
        await gate.tryAcquire('k', cooldown: cd, oncePerDay: true, now: DateTime(2026, 3, 11, 0, 5)),
        isTrue,
      );
    });

    test('a timestamp in the future (clock moved back) does not suppress', () async {
      const cd = Duration(minutes: 10);
      await store.markNotified('k', t0.add(const Duration(hours: 1)));
      expect(await gate.tryAcquire('k', cooldown: cd, now: t0), isTrue);
    });

    test('two gates sharing one store never both announce the same event', () async {
      const cd = Duration(minutes: 10);
      final foreground = NotificationGate(store);
      final background = NotificationGate(store);
      expect(await foreground.tryAcquire('k', cooldown: cd, now: t0), isTrue);
      expect(await background.tryAcquire('k', cooldown: cd, oncePerDay: true, now: t0.add(const Duration(minutes: 1))), isFalse);
    });
  });

  group('PrefsCooldownStore', () {
    test('persists across instances (survives an app restart)', () async {
      SharedPreferences.setMockInitialValues({});
      final at = DateTime(2026, 3, 10, 10, 0);
      await const PrefsCooldownStore().markNotified('limit:global', at);

      final reread = await const PrefsCooldownStore().lastNotified('limit:global');
      expect(reread, at);
      expect(await const PrefsCooldownStore().lastNotified('other'), isNull);
    });
  });
}
