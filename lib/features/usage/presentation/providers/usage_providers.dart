import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database_helper.dart';
import '../../data/datasources/app_usage_local_datasource.dart';
import '../../data/datasources/usage_stats_datasource.dart';
import '../../data/repositories/usage_repository_impl.dart';
import '../../domain/entities/app_usage.dart';
import '../../domain/entities/daily_usage_summary.dart';
import '../../domain/repositories/usage_repository.dart';

// ── Infrastructure ────────────────────────────────────────────────────────────

final databaseHelperProvider = Provider<DatabaseHelper>(
  (_) => DatabaseHelper.instance,
);

final usageLocalDataSourceProvider = Provider<AppUsageLocalDataSource>((ref) {
  return AppUsageLocalDataSourceImpl(ref.watch(databaseHelperProvider));
});

final usageStatsDatasourceProvider = Provider<UsageStatsDatasource>(
  (_) => const AndroidUsageStatsDatasource(),
);

// ── Repository ────────────────────────────────────────────────────────────────

final usageRepositoryProvider = Provider<UsageRepository>((ref) {
  return UsageRepositoryImpl(
    localDataSource: ref.watch(usageLocalDataSourceProvider),
    statsDataSource: ref.watch(usageStatsDatasourceProvider),
  );
});

// ── Queries ───────────────────────────────────────────────────────────────────

/// Returns all [AppUsage] records for a given calendar day from SQLite.
///
/// autoDispose: callers pass `DateTime.now()` (a new key on every rebuild),
/// so entries must be released once unwatched instead of accumulating.
final dailyUsageProvider =
    FutureProvider.autoDispose.family<List<AppUsage>, DateTime>((ref, date) {
  ref.watch(usageRefreshTickProvider);
  return ref.watch(usageRepositoryProvider).getDailyUsage(date);
});

// ── Sync ──────────────────────────────────────────────────────────────────────

/// Emits every 60 seconds while watched, so providers that depend on live OS
/// usage re-run.
///
/// Built from an explicit [Timer.periodic] (rather than [Stream.periodic])
/// so [ref.onDispose] can cancel it synchronously — [StreamSubscription.cancel]
/// on `Stream.periodic` left the timer alive past widget-tree disposal
/// (surfaced as a "Timer is still pending" failure in tests).
final usageRefreshTickProvider = StreamProvider.autoDispose<int>((ref) {
  final controller = StreamController<int>();
  var tick = 0;
  final timer = Timer.periodic(
    const Duration(seconds: 60),
    (_) => controller.add(tick++),
  );
  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Pulls today's live usage stats from Android, saves them to SQLite,
/// and returns the merged list.
///
/// autoDispose ensures a fresh sync runs each time the provider is re-watched
/// (e.g. when the user navigates back to the Home Screen).
final syncTodayUsageProvider =
    FutureProvider.autoDispose<List<AppUsage>>((ref) {
  // Re-sync from the OS on every tick while something is watching.
  ref.watch(usageRefreshTickProvider);
  final repo = ref.watch(usageRepositoryProvider);
  return repo.fetchAndSyncUsage(DateTime.now());
});

// ── Weekly summary ────────────────────────────────────────────────────────────

/// Total screen time per day for the last 7 days, oldest → newest.
final weeklyUsageProvider =
    FutureProvider.autoDispose<List<DailyUsageSummary>>((ref) {
  // Refresh with the minute tick so the chart follows live usage.
  ref.watch(usageRefreshTickProvider);
  return ref.watch(usageRepositoryProvider).getUsageLast7Days();
});
