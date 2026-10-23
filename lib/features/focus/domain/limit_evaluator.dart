import 'entities/focus_settings.dart';
import '../../usage/domain/entities/app_usage.dart';

/// One daily limit (per-app or global) that today's usage has reached.
class LimitBreach {
  const LimitBreach({
    required this.key,
    required this.displayName,
    required this.usedMinutes,
    required this.limitMinutes,
    this.packageName,
  });

  /// Stable identifier used for notification de-duplication.
  final String key;

  /// App name, or [LimitEvaluator.globalDisplayName] for the global limit.
  final String displayName;

  /// Null for the global limit.
  final String? packageName;

  final int usedMinutes;
  final int limitMinutes;

  bool get isGlobal => packageName == null;
}

/// Pure limit calculations shared by the foreground monitor and the
/// background WorkManager task, so both always agree on what "exceeded" means.
class LimitEvaluator {
  LimitEvaluator._();

  static const globalKey = 'limit:global';
  static const globalDisplayName = 'Total Screen Time';

  static String appKey(String packageName) => 'limit:app:$packageName';

  /// Usage in seconds per package. Repeated entries for the same package are
  /// collapsed to the largest value rather than summed, so a duplicated row
  /// can never double-count.
  static Map<String, int> secondsByPackage(Iterable<AppUsage> usages) {
    final result = <String, int>{};
    for (final u in usages) {
      if (u.packageName.isEmpty || u.usageTime <= 0) continue;
      final current = result[u.packageName];
      if (current == null || u.usageTime > current) {
        result[u.packageName] = u.usageTime;
      }
    }
    return result;
  }

  /// Total screen time in whole minutes across all packages.
  static int totalMinutes(Iterable<AppUsage> usages) {
    final seconds = secondsByPackage(usages).values.fold<int>(0, (a, b) => a + b);
    return seconds ~/ 60;
  }

  /// Returns every limit that [usages] has reached (usage >= limit).
  ///
  /// Per-app limits and the global limit are evaluated independently. The
  /// global total is computed from the complete usage list before it is
  /// compared. Returns an empty list when Focus Mode is disabled.
  static List<LimitBreach> evaluate({
    required FocusSettings settings,
    required Iterable<AppUsage> usages,
  }) {
    if (!settings.isEnabled) return const [];

    final byPackage = secondsByPackage(usages);
    final names = <String, String>{};
    for (final u in usages) {
      names.putIfAbsent(u.packageName, () => u.appName);
    }

    final breaches = <LimitBreach>[];
    final seenPackages = <String>{};

    for (final limit in settings.perAppLimits) {
      if (limit.dailyLimitMinutes <= 0) continue;
      if (!seenPackages.add(limit.packageName)) continue; // first limit wins
      final seconds = byPackage[limit.packageName];
      if (seconds == null) continue;
      final used = seconds ~/ 60;
      if (used >= limit.dailyLimitMinutes) {
        breaches.add(LimitBreach(
          key: appKey(limit.packageName),
          displayName: limit.appName,
          packageName: limit.packageName,
          usedMinutes: used,
          limitMinutes: limit.dailyLimitMinutes,
        ));
      }
    }

    final globalLimit = settings.globalLimitMinutes;
    if (globalLimit != null && globalLimit > 0) {
      final total = byPackage.values.fold<int>(0, (a, b) => a + b) ~/ 60;
      if (total >= globalLimit) {
        breaches.add(LimitBreach(
          key: globalKey,
          displayName: globalDisplayName,
          usedMinutes: total,
          limitMinutes: globalLimit,
        ));
      }
    }

    return breaches;
  }
}
