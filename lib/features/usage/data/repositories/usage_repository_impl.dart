import '../../domain/entities/app_usage.dart';
import '../../domain/entities/daily_usage_summary.dart';
import '../../domain/repositories/usage_repository.dart';
import '../datasources/app_usage_local_datasource.dart';
import '../datasources/usage_stats_datasource.dart';
import '../datasources/app_icon_cache.dart';
import '../models/app_usage_model.dart';

class UsageRepositoryImpl implements UsageRepository {
  const UsageRepositoryImpl({
    required this.localDataSource,
    required this.statsDataSource,
  });

  final AppUsageLocalDataSource localDataSource;
  final UsageStatsDatasource statsDataSource;

  @override
  Future<void> saveUsage(AppUsage usage) {
    return localDataSource.insertUsage(AppUsageModel.fromEntity(usage));
  }

  @override
  Future<List<AppUsage>> getDailyUsage(DateTime date) async {
    final usages = await localDataSource.getUsageByDate(date);
    // Fetch and attach icons for each app (with caching)
    return _attachIcons(usages);
  }

  @override
  Future<bool> hasUsagePermission() {
    return statsDataSource.hasUsagePermission();
  }

  @override
  Future<String?> getForegroundApp() {
    return statsDataSource.getForegroundApp();
  }

  @override
  Future<List<DailyUsageSummary>> getUsageLast7Days() {
    return localDataSource.getUsageSummaryLast7Days();
  }

  @override
  Future<List<AppUsage>> fetchAndSyncUsage(DateTime date) async {
    // 1. Pull live stats from OS (empty if no permission / non-Android)
    final systemUsages = await statsDataSource.fetchUsageStats(date);

    // 2. Persist each entry; UNIQUE constraint handles duplicates silently
    for (final usage in systemUsages) {
      await localDataSource.insertUsage(usage);
    }

    // 3. Return the full day from SQLite (includes any manually saved entries)
    final usages = await localDataSource.getUsageByDate(date);

    // 4. Fetch and attach icons for each app
    return _attachIcons(usages);
  }

  /// Helper: Fetch and attach icons to each usage entry (with caching)
  Future<List<AppUsage>> _attachIcons(List<AppUsage> usages) async {
    final iconCache = AppIconCache.instance;
    final result = <AppUsage>[];

    for (final usage in usages) {
      final icon = await iconCache.getIcon(usage.packageName, statsDataSource);
      // Attach icon to usage
      final withIcon = (usage is AppUsageModel)
          ? usage.copyWith(icon: icon)
          : usage.copyWith(icon: icon);
      result.add(withIcon);
    }

    return result;
  }
}
