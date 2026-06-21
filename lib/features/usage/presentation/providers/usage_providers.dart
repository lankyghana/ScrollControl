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
final dailyUsageProvider =
    FutureProvider.family<List<AppUsage>, DateTime>((ref, date) {
  return ref.watch(usageRepositoryProvider).getDailyUsage(date);
});

// ── Sync ──────────────────────────────────────────────────────────────────────

/// Pulls today's live usage stats from Android, saves them to SQLite,
/// and returns the merged list.
///
/// autoDispose ensures a fresh sync runs each time the provider is re-watched
/// (e.g. when the user navigates back to the Home Screen).
final syncTodayUsageProvider =
    FutureProvider.autoDispose<List<AppUsage>>((ref) {
  final repo = ref.watch(usageRepositoryProvider);
  return repo.fetchAndSyncUsage(DateTime.now());
});

// ── Weekly summary ────────────────────────────────────────────────────────────

/// Total screen time per day for the last 7 days, oldest → newest.
final weeklyUsageProvider =
    FutureProvider<List<DailyUsageSummary>>((ref) {
  return ref.watch(usageRepositoryProvider).getUsageLast7Days();
});
