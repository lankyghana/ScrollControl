import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/focus/domain/entities/app_limit.dart';
import 'package:scroll_control/features/focus/domain/entities/focus_settings.dart';
import 'package:scroll_control/features/focus/domain/limit_evaluator.dart';
import 'package:scroll_control/features/usage/domain/entities/app_usage.dart';

AppUsage usage(String pkg, String name, int minutes, {int extraSeconds = 0}) =>
    AppUsage(
      appName: name,
      packageName: pkg,
      usageTime: minutes * 60 + extraSeconds,
      date: DateTime(2026, 1, 1),
    );

FocusSettings settings({
  bool enabled = true,
  int? global,
  List<AppLimit> perApp = const [],
}) =>
    FocusSettings(isEnabled: enabled, globalLimitMinutes: global, perAppLimits: perApp);

const limitA = AppLimit(packageName: 'com.a', appName: 'App A', dailyLimitMinutes: 10);

void main() {
  group('LimitEvaluator.evaluate', () {
    test('returns nothing when Focus Mode is disabled', () {
      final result = LimitEvaluator.evaluate(
        settings: settings(enabled: false, global: 5, perApp: [limitA]),
        usages: [usage('com.a', 'App A', 60)],
      );
      expect(result, isEmpty);
    });

    test('per-app limit is reached at exactly the limit, not before', () {
      final under = LimitEvaluator.evaluate(
        settings: settings(perApp: [limitA]),
        usages: [usage('com.a', 'App A', 9, extraSeconds: 59)],
      );
      final at = LimitEvaluator.evaluate(
        settings: settings(perApp: [limitA]),
        usages: [usage('com.a', 'App A', 10)],
      );
      expect(under, isEmpty);
      expect(at, hasLength(1));
      expect(at.single.usedMinutes, 10);
      expect(at.single.limitMinutes, 10);
      expect(at.single.displayName, 'App A');
      expect(at.single.isGlobal, isFalse);
    });

    test('global limit uses the total across ALL apps, computed before comparing', () {
      // Each app alone is below 30 min; only the full total (45) crosses it.
      final result = LimitEvaluator.evaluate(
        settings: settings(global: 30),
        usages: [
          usage('com.a', 'App A', 15),
          usage('com.b', 'App B', 15),
          usage('com.c', 'App C', 15),
        ],
      );
      expect(result, hasLength(1));
      expect(result.single.isGlobal, isTrue);
      expect(result.single.usedMinutes, 45);
      expect(result.single.limitMinutes, 30);
      expect(result.single.displayName, LimitEvaluator.globalDisplayName);
    });

    test('global total reports the full day, not a partial running sum', () {
      // Order must not matter: the old per-app-loop bug reported the running
      // total at the moment the limit was first crossed.
      final result = LimitEvaluator.evaluate(
        settings: settings(global: 20),
        usages: [
          usage('com.a', 'App A', 25),
          usage('com.b', 'App B', 25),
        ],
      );
      expect(result.single.usedMinutes, 50);
    });

    test('per-app and global limits are independent', () {
      final onlyGlobal = LimitEvaluator.evaluate(
        settings: settings(global: 20, perApp: [limitA]),
        usages: [usage('com.a', 'App A', 5), usage('com.b', 'App B', 30)],
      );
      expect(onlyGlobal.map((b) => b.key), [LimitEvaluator.globalKey]);

      final onlyApp = LimitEvaluator.evaluate(
        settings: settings(global: 600, perApp: [limitA]),
        usages: [usage('com.a', 'App A', 12)],
      );
      expect(onlyApp.map((b) => b.key), [LimitEvaluator.appKey('com.a')]);

      final both = LimitEvaluator.evaluate(
        settings: settings(global: 20, perApp: [limitA]),
        usages: [usage('com.a', 'App A', 12), usage('com.b', 'App B', 30)],
      );
      expect(both, hasLength(2));
    });

    test('duplicate rows for one package are not double counted', () {
      final result = LimitEvaluator.evaluate(
        settings: settings(global: 100),
        usages: [usage('com.a', 'App A', 60), usage('com.a', 'App A', 60)],
      );
      expect(result, isEmpty); // 60, not 120
      expect(
        LimitEvaluator.totalMinutes([usage('com.a', 'A', 60), usage('com.a', 'A', 60)]),
        60,
      );
    });

    test('an app with a limit but no usage today is skipped', () {
      final result = LimitEvaluator.evaluate(
        settings: settings(perApp: [limitA]),
        usages: [usage('com.other', 'Other', 99)],
      );
      expect(result, isEmpty);
    });

    test('zero, null and negative limits never fire', () {
      final result = LimitEvaluator.evaluate(
        settings: settings(
          global: 0,
          perApp: const [
            AppLimit(packageName: 'com.a', appName: 'App A', dailyLimitMinutes: 0),
            AppLimit(packageName: 'com.b', appName: 'App B', dailyLimitMinutes: -5),
          ],
        ),
        usages: [usage('com.a', 'App A', 50), usage('com.b', 'App B', 50)],
      );
      expect(result, isEmpty);
    });

    test('empty usage list and invalid rows are handled', () {
      expect(
        LimitEvaluator.evaluate(settings: settings(global: 1, perApp: [limitA]), usages: const []),
        isEmpty,
      );
      expect(
        LimitEvaluator.totalMinutes([
          usage('', 'No package', 100),
          usage('com.a', 'Zero', 0),
          usage('com.b', 'Neg', -4),
        ]),
        0,
      );
    });

    test('a package listed twice in limits yields a single breach (first wins)', () {
      final result = LimitEvaluator.evaluate(
        settings: settings(perApp: const [
          AppLimit(packageName: 'com.a', appName: 'App A', dailyLimitMinutes: 10),
          AppLimit(packageName: 'com.a', appName: 'App A', dailyLimitMinutes: 5),
        ]),
        usages: [usage('com.a', 'App A', 20)],
      );
      expect(result, hasLength(1));
      expect(result.single.limitMinutes, 10);
    });
  });
}
