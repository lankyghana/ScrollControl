import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/focus/domain/entities/daily_focus_summary.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_session.dart';
import 'package:scroll_control/features/focus/domain/repositories/focus_repository.dart';
import 'package:scroll_control/features/focus/presentation/providers/focus_providers.dart';
import 'package:scroll_control/features/home/presentation/providers/focus_session_provider.dart';

class _FakeFocusRepository implements FocusRepository {
  final List<FocusSession> saved = [];

  @override
  Future<void> saveSession(FocusSession session) async => saved.add(session);

  @override
  Future<List<FocusSession>> getDailySessions(DateTime date) async => saved;

  @override
  Future<List<DailyFocusSummary>> getSessionsLast7Days() async => const [];
}

void main() {
  late ProviderContainer container;
  late _FakeFocusRepository repo;
  late FocusSessionNotifier notifier;
  late DateTime now;

  setUp(() {
    repo = _FakeFocusRepository();
    container = ProviderContainer(
      overrides: [focusRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    notifier = container.read(focusSessionProvider.notifier);
    now = DateTime(2026, 3, 10, 9, 0);
    notifier.clock = () => now;
  });

  FocusSessionState state() => container.read(focusSessionProvider);
  void advance(Duration d) {
    now = now.add(d);
    notifier.syncWithClock();
  }

  test('starts idle with a full 25-minute timer', () {
    expect(state().status, FocusSessionStatus.idle);
    expect(state().remainingSeconds, 25 * 60);
  });

  test('start runs the session and the countdown follows the wall clock', () {
    notifier.start();
    expect(state().status, FocusSessionStatus.running);

    advance(const Duration(minutes: 10));
    expect(state().remainingSeconds, 15 * 60);
  });

  test('time spent with the app backgrounded is accounted for on resume', () {
    notifier.start();
    advance(const Duration(minutes: 24, seconds: 30)); // timers were frozen
    expect(state().remainingSeconds, 30);
    expect(state().status, FocusSessionStatus.running);
  });

  test('pause freezes the countdown and resume continues from it', () {
    notifier.start();
    advance(const Duration(minutes: 5));
    notifier.pause();
    expect(state().status, FocusSessionStatus.paused);
    final frozen = state().remainingSeconds;
    expect(frozen, 20 * 60);

    now = now.add(const Duration(minutes: 30)); // paused time doesn't count
    notifier.syncWithClock();
    expect(state().remainingSeconds, frozen);

    notifier.resume();
    expect(state().status, FocusSessionStatus.running);
    advance(const Duration(minutes: 1));
    expect(state().remainingSeconds, frozen - 60);
  });

  test('start while paused resumes instead of restarting', () {
    notifier.start();
    advance(const Duration(minutes: 5));
    notifier.pause();
    notifier.start();
    expect(state().status, FocusSessionStatus.running);
    expect(state().remainingSeconds, 20 * 60);
  });

  test('completing a session saves exactly one record with the right data', () async {
    notifier.start();
    final startedAt = now;
    advance(const Duration(minutes: 25));
    await Future<void>.delayed(Duration.zero);

    expect(state().status, FocusSessionStatus.finished);
    expect(state().remainingSeconds, 0);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.startTime, startedAt);
    expect(repo.saved.single.duration, 25 * 60);

    // More clock movement must not save it again.
    advance(const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);
    expect(repo.saved, hasLength(1));
  });

  test('starting again after a finished session begins a full timer (no bogus instant session)', () async {
    notifier.start();
    advance(const Duration(minutes: 25));
    await Future<void>.delayed(Duration.zero);
    expect(repo.saved, hasLength(1));

    notifier.start();
    expect(state().status, FocusSessionStatus.running);
    expect(state().remainingSeconds, 25 * 60);

    advance(const Duration(seconds: 3));
    await Future<void>.delayed(Duration.zero);
    expect(repo.saved, hasLength(1)); // still just the first one
  });

  test('stop and reset return to idle without saving', () async {
    notifier.start();
    advance(const Duration(minutes: 3));
    notifier.stop();
    expect(state().status, FocusSessionStatus.idle);
    expect(state().remainingSeconds, 25 * 60);

    notifier.start();
    advance(const Duration(minutes: 3));
    notifier.reset();
    expect(state().status, FocusSessionStatus.idle);

    // A stale clock tick after stopping must not change anything.
    advance(const Duration(hours: 1));
    await Future<void>.delayed(Duration.zero);
    expect(state().status, FocusSessionStatus.idle);
    expect(repo.saved, isEmpty);
  });

  test('pause on a session that already ran out finishes it instead of pausing', () async {
    notifier.start();
    now = now.add(const Duration(minutes: 26)); // no sync happened yet
    notifier.pause();
    await Future<void>.delayed(Duration.zero);

    expect(state().status, FocusSessionStatus.finished);
    expect(repo.saved, hasLength(1));
  });

  test('start is ignored while already running', () {
    notifier.start();
    advance(const Duration(minutes: 2));
    notifier.start();
    expect(state().remainingSeconds, 23 * 60);
  });
}
