import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/blocking/domain/block_snapshot.dart';
import 'package:scroll_control/features/blocking/domain/snapshot_composer.dart';
import 'package:scroll_control/features/focus/domain/entities/daily_focus_summary.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_session.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';
import 'package:scroll_control/features/focus/domain/repositories/focus_repository.dart';
import 'package:scroll_control/features/focus/presentation/providers/focus_providers.dart';
import 'package:scroll_control/features/home/presentation/providers/focus_session_provider.dart';

import '../../helpers/fakes.dart';

class _Repo implements FocusRepository {
  final List<FocusSession> saved = [];

  @override
  Future<void> saveSession(FocusSession session) async => saved.add(session);

  @override
  Future<List<FocusSession>> getDailySessions(DateTime date) async => saved;

  @override
  Future<List<DailyFocusSummary>> getSessionsLast7Days() async => const [];
}

const _insta = BlockedApp(packageName: 'com.insta', appName: 'Instagram');

void main() {
  late FakeFocusSessionStore store;
  late _Repo repo;
  late DateTime now;

  /// A fresh container is a fresh process: what survives is only [store].
  (ProviderContainer, FocusSessionNotifier) boot() {
    final container = ProviderContainer(overrides: [
      focusSessionStoreProvider.overrideWithValue(store),
      focusRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(focusSessionProvider.notifier)
      ..clock = () => now;
    return (container, notifier);
  }

  setUp(() {
    store = FakeFocusSessionStore();
    repo = _Repo();
    now = DateTime(2026, 3, 10, 9, 0);
  });

  group('session start and end', () {
    test('starting exposes the end time and the apps to the blocker', () {
      final (c, n) = boot();
      n.setBlockedApps(const [_insta]);

      n.start();

      final s = c.read(focusSessionProvider);
      expect(s.isRunning, isTrue);
      expect(s.endsAt, now.add(const Duration(minutes: 25)));
      expect(s.blockSignature, contains('com.insta'));

      final snap = composeSnapshot(
        settings: FocusSettings.disabled, // Daily Focus Mode is OFF
        sessionApps: s.blockedApps,
        sessionEndsAt: s.endsAt,
        breaksUntil: const {},
        now: now,
      );
      expect(snap.session, isNotNull);
    });

    test('ending a session stops enforcing it', () {
      final (c, n) = boot();
      n.setBlockedApps(const [_insta]);
      n.start();

      n.stop();

      final s = c.read(focusSessionProvider);
      expect(s.isIdle, isTrue);
      expect(s.endsAt, isNull);
      expect(s.blockSignature, 'none');
      expect(s.blockedApps, const [_insta], reason: 'selection is remembered');
    });

    test('a session that runs out stops being enforced', () {
      final (c, n) = boot();
      n.setBlockedApps(const [_insta]);
      n.start();

      now = now.add(const Duration(minutes: 25));
      n.syncWithClock();

      final s = c.read(focusSessionProvider);
      expect(s.status, FocusSessionStatus.finished);
      expect(s.blockSignature, 'none');
    });

    test('pausing lifts the block; resuming re-applies it with a new end time',
        () {
      final (c, n) = boot();
      n.setBlockedApps(const [_insta]);
      n.start();
      now = now.add(const Duration(minutes: 5));
      n.syncWithClock();

      n.pause();
      expect(c.read(focusSessionProvider).blockSignature, 'none');

      now = now.add(const Duration(minutes: 30)); // paused time is not counted
      n.resume();

      final s = c.read(focusSessionProvider);
      expect(s.endsAt, now.add(const Duration(minutes: 20)));
      expect(s.blockSignature, isNot('none'));
    });

    test('duration and apps can only change while no countdown is running', () {
      final (c, n) = boot();
      n.start();

      n.setDurationMinutes(60);
      n.setBlockedApps(const [_insta]);

      final s = c.read(focusSessionProvider);
      expect(s.totalSeconds, 25 * 60);
      expect(s.blockedApps, isEmpty);
    });

    test('a chosen duration is used by the next session', () {
      final (c, n) = boot();
      n.setDurationMinutes(45);
      n.start();

      expect(c.read(focusSessionProvider).remainingSeconds, 45 * 60);
    });
  });

  group('device reboot and state recovery', () {
    test('a running session resumes with the correct time left', () async {
      final (_, n) = boot();
      n.setBlockedApps(const [_insta]);
      n.start();
      await Future<void>.delayed(Duration.zero);

      // The process dies; 10 minutes pass; the app starts again.
      now = now.add(const Duration(minutes: 10));
      final (c2, n2) = boot();
      await n2.restore();

      final s = c2.read(focusSessionProvider);
      expect(s.isRunning, isTrue);
      expect(s.remainingSeconds, 15 * 60);
      expect(s.blockedApps, const [_insta]);
      expect(s.endsAt, DateTime(2026, 3, 10, 9, 25),
          reason: 'the original end time, not "now + remaining"');
    });

    test('a session that ended while the phone was off is recorded, not resumed',
        () async {
      final (_, n) = boot();
      n.start();
      await Future<void>.delayed(Duration.zero);

      now = now.add(const Duration(hours: 3));
      final (c2, n2) = boot();
      await n2.restore();
      await Future<void>.delayed(Duration.zero);

      expect(c2.read(focusSessionProvider).status, FocusSessionStatus.finished);
      expect(c2.read(focusSessionProvider).blockSignature, 'none');
      expect(repo.saved, hasLength(1));
      expect(repo.saved.single.endTime, DateTime(2026, 3, 10, 9, 25));
    });

    test('a paused session comes back paused with its remaining time',
        () async {
      final (_, n) = boot();
      n.start();
      now = now.add(const Duration(minutes: 5));
      n.syncWithClock();
      n.pause();
      await Future<void>.delayed(Duration.zero);

      now = now.add(const Duration(hours: 2));
      final (c2, n2) = boot();
      await n2.restore();

      final s = c2.read(focusSessionProvider);
      expect(s.status, FocusSessionStatus.paused);
      expect(s.remainingSeconds, 20 * 60);
    });

    test('the idle selection (apps, duration) survives a restart', () async {
      final (_, n) = boot();
      n.setDurationMinutes(60);
      n.setBlockedApps(const [_insta]);
      await Future<void>.delayed(Duration.zero);

      final (c2, n2) = boot();
      await n2.restore();

      final s = c2.read(focusSessionProvider);
      expect(s.isIdle, isTrue);
      expect(s.totalSeconds, 60 * 60);
      expect(s.blockedApps, const [_insta]);
    });

    test('restore never overwrites a session the user already started',
        () async {
      final (_, n) = boot();
      n.setDurationMinutes(60);
      await Future<void>.delayed(Duration.zero);

      final (c2, n2) = boot();
      n2.start();
      await n2.restore();

      expect(c2.read(focusSessionProvider).isRunning, isTrue);
      expect(c2.read(focusSessionProvider).totalSeconds, 25 * 60);
    });

    test('with nothing saved, restore leaves the defaults alone', () async {
      final (c, n) = boot();
      await n.restore();

      expect(c.read(focusSessionProvider).isIdle, isTrue);
      expect(c.read(focusSessionProvider).remainingSeconds, 25 * 60);
    });
  });
}
