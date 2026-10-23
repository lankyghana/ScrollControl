import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/focus/presentation/providers/limit_exceeded_provider.dart';

void main() {
  late LimitExceededNotifier notifier;
  final noon = DateTime(2026, 3, 10, 12, 0);

  setUp(() => notifier = LimitExceededNotifier());

  test('marking an app exceeded blocks it (regression: const map was unmodifiable)', () {
    notifier.markLimitExceeded('Instagram', now: noon);

    expect(notifier.state.isAppBlocked('Instagram', now: noon), isTrue);
    expect(notifier.state.getFirstBlockedApp(now: noon), 'Instagram');
  });

  test('marking twice keeps the original timestamp', () {
    notifier.markLimitExceeded('Instagram', now: noon);
    notifier.markLimitExceeded('Instagram', now: noon.add(const Duration(hours: 1)));

    expect(notifier.state.exceededApps['Instagram'], noon);
  });

  test('no app is blocked initially', () {
    expect(notifier.state.getFirstBlockedApp(now: noon), '');
    expect(notifier.state.isAppBlocked('Anything', now: noon), isFalse);
  });

  test('a flag from yesterday no longer blocks and is replaced when re-marked', () {
    notifier.markLimitExceeded('Instagram', now: noon);
    final tomorrow = noon.add(const Duration(days: 1));

    expect(notifier.state.isAppBlocked('Instagram', now: tomorrow), isFalse);

    notifier.markLimitExceeded('Instagram', now: tomorrow);
    expect(notifier.state.exceededApps['Instagram'], tomorrow);
    expect(notifier.state.isAppBlocked('Instagram', now: tomorrow), isTrue);
  });

  test('dismiss unblocks the app until it is marked again', () {
    notifier.markLimitExceeded('Instagram', now: noon);
    notifier.dismiss('Instagram');
    expect(notifier.state.isAppBlocked('Instagram', now: noon), isFalse);

    notifier.markLimitExceeded('Instagram', now: noon);
    expect(notifier.state.isAppBlocked('Instagram', now: noon), isTrue);
  });

  test('dismissing an app that was never flagged is a no-op', () {
    notifier.dismiss('Nope');
    expect(notifier.state.exceededApps, isEmpty);
  });

  test('an active break unblocks only the app it was granted for', () {
    notifier.markLimitExceeded('A', now: DateTime.now());
    notifier.markLimitExceeded('B', now: DateTime.now());
    notifier.grantBreak('A', 5);

    expect(notifier.state.isAppBlocked('A'), isFalse);
    expect(notifier.state.isAppBlocked('B'), isTrue);
  });

  test('resetLimits clears everything', () {
    notifier.markLimitExceeded('A', now: noon);
    notifier.grantBreak('A', 5);
    notifier.resetLimits();

    expect(notifier.state.exceededApps, isEmpty);
    expect(notifier.state.activeBreaks, isEmpty);
  });
}
