import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import '../../../focus/presentation/providers/focus_providers.dart';
import '../../../usage/presentation/providers/usage_providers.dart';
import '../../../usage/domain/entities/app_usage.dart';

class TodayStats {
  const TodayStats({
    required this.screenTimeMinutes,
    required this.mostUsedApp,
    required this.mostUsedAppMinutes,
    required this.focusSessionsDone,
  });

  final int screenTimeMinutes;
  final String mostUsedApp;
  final int mostUsedAppMinutes;
  final int focusSessionsDone;

  static const empty = TodayStats(
    screenTimeMinutes: 0,
    mostUsedApp: '—',
    mostUsedAppMinutes: 0,
    focusSessionsDone: 0,
  );
}

class AppUsageSummary {
  const AppUsageSummary({
    required this.appName,
    required this.packageName,
    required this.usageMinutes,
    this.icon,
  });

  final String appName;
  final String packageName;
  final int usageMinutes;
  final Uint8List? icon;
}

enum AppUsageRange {
  today,
  last7Days,
}

final appUsageRangeProvider = StateProvider<AppUsageRange>(
  (_) => AppUsageRange.today,
);

/// Alias used by the Home Screen so the dashboard reads naturally.
final usageProvider = todayStatsProvider;

/// Derives today's usage summary.
///
/// Flow:
///   1. Trigger [syncTodayUsageProvider] to pull from Android + persist to SQLite.
///   2. If sync returns data → use it directly (freshest possible).
///   3. If sync returns empty (permission denied / non-Android / first boot) →
///      fall back to whatever is already cached in SQLite.
///   4. If both are empty → return [TodayStats.empty].
final todayStatsProvider = FutureProvider<TodayStats>((ref) async {
  // Watch the auto-refresh stream to trigger re-computation every 60 seconds
  ref.watch(usageRefreshTickProvider);

  // Attempt OS sync (no-op on web/desktop or when permission is denied)
  final synced = await ref.watch(syncTodayUsageProvider.future);

  final usages = synced.isNotEmpty
      ? synced
      : await ref.watch(dailyUsageProvider(DateTime.now()).future);

  final sessions =
      await ref.watch(dailyFocusSessionsProvider(DateTime.now()).future);

  if (usages.isEmpty) {
    return TodayStats(
      screenTimeMinutes: 0,
      mostUsedApp: '—',
      mostUsedAppMinutes: 0,
      focusSessionsDone: sessions.length,
    );
  }

  final totalSeconds = usages.fold<int>(0, (sum, u) => sum + u.usageTime);
  final topApp = usages.first; // already ordered by usage_time DESC

  return TodayStats(
    screenTimeMinutes: totalSeconds ~/ 60,
    mostUsedApp: topApp.appName,
    mostUsedAppMinutes: topApp.usageTime ~/ 60,
    focusSessionsDone: sessions.length,
  );
});

final appUsageProvider =
    FutureProvider.family<List<AppUsageSummary>, AppUsageRange>(
        (ref, range) async {
  // Watch the auto-refresh stream to trigger re-computation every 60 seconds
  ref.watch(usageRefreshTickProvider);

  final usages = <AppUsage>[];

  switch (range) {
    case AppUsageRange.today:
      final today = DateTime.now();
      final todayUsage = await ref.watch(dailyUsageProvider(today).future);
      usages.addAll(todayUsage);
      break;
    case AppUsageRange.last7Days:
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 6));

      final futures = List.generate(7, (index) {
        return ref.watch(
          dailyUsageProvider(start.add(Duration(days: index))).future,
        );
      });

      final results = await Future.wait(futures);
      for (final dayUsage in results) {
        usages.addAll(dayUsage);
      }
      break;
  }

  final aggregated = <String, AppUsageSummary>{};

  for (final usage in usages) {
    final existing = aggregated[usage.packageName];
    final nextMinutes = usage.usageTime ~/ 60;

    if (existing == null) {
      aggregated[usage.packageName] = AppUsageSummary(
        appName: usage.appName,
        packageName: usage.packageName,
        usageMinutes: nextMinutes,
        icon: usage.icon, // Preserve the icon
      );
    } else {
      aggregated[usage.packageName] = AppUsageSummary(
        appName: existing.appName,
        packageName: existing.packageName,
        usageMinutes: existing.usageMinutes + nextMinutes,
        icon: existing.icon, // Keep the existing icon (from first occurrence)
      );
    }
  }

  final sorted = aggregated.values.toList()
    ..sort((a, b) => b.usageMinutes.compareTo(a.usageMinutes));

  return sorted;
});
