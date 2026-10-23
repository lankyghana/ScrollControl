import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/blocking/domain/block_snapshot.dart';
import 'package:scroll_control/features/blocking/domain/snapshot_composer.dart';
import 'package:scroll_control/features/focus/domain/entities/app_limit.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';

int ms(DateTime d) => d.millisecondsSinceEpoch;

const insta = BlockedApp(packageName: 'com.insta', appName: 'Instagram');
const tiktok = BlockedApp(packageName: 'com.tiktok', appName: 'TikTok');

BlockSnapshot daily({
  int? globalMin,
  List<(String, String, int)> apps = const [],
  Map<String, int> breaks = const {},
  SessionRule? session,
}) =>
    BlockSnapshot(
      dailyEnabled: true,
      globalLimitSeconds: globalMin == null ? null : globalMin * 60,
      appLimits: [
        for (final (pkg, name, min) in apps)
          AppLimitRule(packageName: pkg, appName: name, limitSeconds: min * 60),
      ],
      breaksUntilMs: breaks,
      session: session,
    );

void main() {
  final noon = DateTime(2026, 3, 10, 12, 0);

  group('daily total limit', () {
    test('blocks every app once total usage reaches the limit', () {
      final snap = daily(globalMin: 60);
      final usage = {'a': 40 * 60, 'b': 20 * 60};

      final d = snap.decide(
          packageName: 'c', usedSecondsByPackage: usage, nowMs: ms(noon));

      expect(d, isNotNull);
      expect(d!.reason, BlockReason.dailyTotal);
      expect(d.usedSeconds, 3600);
      expect(d.limitSeconds, 3600);
    });

    test('does not block below the limit', () {
      final snap = daily(globalMin: 60);
      expect(
        snap.decide(
            packageName: 'a',
            usedSecondsByPackage: {'a': 59 * 60},
            nowMs: ms(noon)),
        isNull,
      );
    });

    test('Focus Mode disabled means no daily blocking', () {
      const snap = BlockSnapshot(dailyEnabled: false, globalLimitSeconds: 60);
      expect(
        snap.decide(
            packageName: 'a',
            usedSecondsByPackage: {'a': 9999},
            nowMs: ms(noon)),
        isNull,
      );
    });
  });

  group('individual app limit', () {
    test('blocks only the app that reached its limit', () {
      final snap = daily(apps: [('com.insta', 'Instagram', 30)]);
      final usage = {'com.insta': 30 * 60, 'com.other': 5};

      final blocked = snap.decide(
          packageName: 'com.insta',
          usedSecondsByPackage: usage,
          nowMs: ms(noon));
      final other = snap.decide(
          packageName: 'com.other',
          usedSecondsByPackage: usage,
          nowMs: ms(noon));

      expect(blocked?.reason, BlockReason.dailyApp);
      expect(blocked?.appName, 'Instagram');
      expect(other, isNull);
    });

    test('an active break waives the app limit until it ends', () {
      final until = ms(noon.add(const Duration(minutes: 5)));
      final snap =
          daily(apps: [('com.insta', 'Instagram', 30)], breaks: {'com.insta': until});
      final usage = {'com.insta': 31 * 60};

      expect(
        snap.decide(
            packageName: 'com.insta',
            usedSecondsByPackage: usage,
            nowMs: ms(noon)),
        isNull,
      );
      expect(
        snap
            .decide(
                packageName: 'com.insta',
                usedSecondsByPackage: usage,
                nowMs: until + 1)
            ?.reason,
        BlockReason.dailyApp,
      );
    });
  });

  group('focus session', () {
    final session = SessionRule(
      endsAtMs: ms(noon.add(const Duration(minutes: 25))),
      apps: const [insta],
    );

    test('blocks its apps until it ends, with no usage needed', () {
      final snap = BlockSnapshot(session: session);

      final during = snap.decide(
          packageName: 'com.insta',
          usedSecondsByPackage: const {},
          nowMs: ms(noon));
      final after = snap.decide(
          packageName: 'com.insta',
          usedSecondsByPackage: const {},
          nowMs: session.endsAtMs);

      expect(during?.reason, BlockReason.session);
      expect(during?.expiresAtMs, session.endsAtMs);
      expect(after, isNull);
    });

    test('works while Daily Focus Mode is off', () {
      final snap = BlockSnapshot(dailyEnabled: false, session: session);
      expect(snap.hasRules, isTrue);
      expect(
        snap.decide(
            packageName: 'com.insta',
            usedSecondsByPackage: const {},
            nowMs: ms(noon)),
        isNotNull,
      );
    });

    test('does not block apps outside the session', () {
      final snap = BlockSnapshot(session: session);
      expect(
        snap.decide(
            packageName: 'com.tiktok',
            usedSecondsByPackage: const {},
            nowMs: ms(noon)),
        isNull,
      );
    });
  });

  group('both restriction systems active', () {
    test('the longer-lasting (daily) restriction wins over a session', () {
      final snap = daily(
        apps: [('com.insta', 'Instagram', 30)],
        session: SessionRule(
          endsAtMs: ms(noon.add(const Duration(minutes: 25))),
          apps: const [insta],
        ),
      );

      final d = snap.decide(
          packageName: 'com.insta',
          usedSecondsByPackage: {'com.insta': 30 * 60},
          nowMs: ms(noon));

      expect(d?.reason, BlockReason.dailyApp);
      expect(d?.expiresAtMs, BlockSnapshot.nextMidnightMs(ms(noon)));
    });

    test('a break cannot lift a session that also covers the app', () {
      final snap = daily(
        apps: [('com.insta', 'Instagram', 30)],
        breaks: {'com.insta': ms(noon.add(const Duration(hours: 1)))},
        session: SessionRule(
          endsAtMs: ms(noon.add(const Duration(minutes: 25))),
          apps: const [insta],
        ),
      );

      final d = snap.decide(
          packageName: 'com.insta',
          usedSecondsByPackage: {'com.insta': 31 * 60},
          nowMs: ms(noon));

      expect(d?.reason, BlockReason.session);
    });

    test('a session still blocks an app that is under its daily limit', () {
      final snap = daily(
        apps: [('com.tiktok', 'TikTok', 60)],
        session: SessionRule(
          endsAtMs: ms(noon.add(const Duration(minutes: 25))),
          apps: const [tiktok],
        ),
      );

      final d = snap.decide(
          packageName: 'com.tiktok',
          usedSecondsByPackage: {'com.tiktok': 60},
          nowMs: ms(noon));

      expect(d?.reason, BlockReason.session);
    });
  });

  group('midnight reset (local calendar day)', () {
    test('daily blocks expire at the next local midnight', () {
      final late = DateTime(2026, 3, 10, 23, 59, 30);
      final snap = daily(globalMin: 10);

      final d = snap.decide(
          packageName: 'a',
          usedSecondsByPackage: {'a': 600},
          nowMs: ms(late));

      expect(DateTime.fromMillisecondsSinceEpoch(d!.expiresAtMs),
          DateTime(2026, 3, 11));
    });

    test('the new day starts from zero usage and is not blocked', () {
      final snap = daily(globalMin: 10, apps: [('a', 'A', 5)]);
      final justBefore = DateTime(2026, 3, 10, 23, 59, 59);
      final justAfter = DateTime(2026, 3, 11, 0, 0, 1);

      expect(
        snap.decide(
            packageName: 'a',
            usedSecondsByPackage: {'a': 600},
            nowMs: ms(justBefore)),
        isNotNull,
      );
      // Usage is reported per calendar day, so the first second of the new
      // day sees (almost) none.
      expect(
        snap.decide(
            packageName: 'a',
            usedSecondsByPackage: {'a': 1},
            nowMs: ms(justAfter)),
        isNull,
      );
    });

    test('nextMidnightMs crosses month and year ends', () {
      expect(
        DateTime.fromMillisecondsSinceEpoch(
            BlockSnapshot.nextMidnightMs(ms(DateTime(2026, 12, 31, 18)))),
        DateTime(2027, 1, 1),
      );
    });
  });

  group('serialisation and composition', () {
    test('survives a JSON round trip (the native contract)', () {
      final snap = daily(
        globalMin: 90,
        apps: [('com.insta', 'Instagram', 30)],
        breaks: {'com.insta': 123456},
        session: const SessionRule(endsAtMs: 999999, apps: [insta, tiktok]),
      );

      final back = BlockSnapshot.fromJson(snap.toJson());

      expect(back.dailyEnabled, isTrue);
      expect(back.globalLimitSeconds, 5400);
      expect(back.appLimits.single.limitSeconds, 1800);
      expect(back.breaksUntilMs, {'com.insta': 123456});
      expect(back.session!.apps, [insta, tiktok]);
      expect(back.session!.endsAtMs, 999999);
    });

    test('composeSnapshot carries limits, breaks and a running session', () {
      const settings = FocusSettings(
        isEnabled: true,
        globalLimitMinutes: 120,
        perAppLimits: [
          AppLimit(
              packageName: 'com.insta',
              appName: 'Instagram',
              dailyLimitMinutes: 30),
        ],
      );
      final snap = composeSnapshot(
        settings: settings,
        sessionApps: const [tiktok],
        sessionEndsAt: noon.add(const Duration(minutes: 10)),
        breaksUntil: {
          'com.insta': noon.add(const Duration(minutes: 5)),
          'com.old': noon.subtract(const Duration(minutes: 1)),
        },
        now: noon,
      );

      expect(snap.globalLimitSeconds, 7200);
      expect(snap.appLimits.single.limitSeconds, 1800);
      expect(snap.session!.apps, [tiktok]);
      expect(snap.breaksUntilMs.keys, ['com.insta']); // expired break dropped
    });

    test('an ended or app-less session is not enforced', () {
      final ended = composeSnapshot(
        settings: FocusSettings.disabled,
        sessionApps: const [insta],
        sessionEndsAt: noon.subtract(const Duration(seconds: 1)),
        breaksUntil: const {},
        now: noon,
      );
      final noApps = composeSnapshot(
        settings: FocusSettings.disabled,
        sessionApps: const [],
        sessionEndsAt: noon.add(const Duration(minutes: 5)),
        breaksUntil: const {},
        now: noon,
      );

      expect(ended.hasRules, isFalse);
      expect(noApps.hasRules, isFalse);
    });
  });
}
