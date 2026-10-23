import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/error_logger.dart';
import '../../../usage/presentation/providers/usage_providers.dart';
import '../../data/datasources/focus_local_datasource.dart';
import '../../data/datasources/focus_limits_local_datasource.dart';
import '../../data/repositories/focus_repository_impl.dart';
import '../../data/repositories/focus_limits_repository_impl.dart';
import '../../domain/entities/app_limit.dart';
import '../../domain/entities/daily_focus_summary.dart';
import '../../domain/entities/focus_session.dart';
import '../../domain/limit_evaluator.dart';
import '../../domain/entities/focus_settings.dart';
import '../../domain/repositories/focus_repository.dart';
import '../../domain/repositories/focus_limits_repository.dart';
import 'limit_exceeded_provider.dart';

// ── Infrastructure ─────────────────────────────────────────────────────────────

final focusLocalDataSourceProvider = Provider<FocusLocalDataSource>((ref) {
  final db = ref.watch(databaseHelperProvider);
  return FocusLocalDataSourceImpl(db);
});

// ── Repository ─────────────────────────────────────────────────────────────────

final focusRepositoryProvider = Provider<FocusRepository>((ref) {
  return FocusRepositoryImpl(ref.watch(focusLocalDataSourceProvider));
});

// ── Queries ────────────────────────────────────────────────────────────────────

/// Returns all focus sessions for a given calendar day, newest first.
final dailyFocusSessionsProvider =
    FutureProvider.family<List<FocusSession>, DateTime>((ref, date) {
  return ref.watch(focusRepositoryProvider).getDailySessions(date);
});

// ── Weekly summary ─────────────────────────────────────────────────────────────

/// Session count per day for the last 7 days, oldest → newest.
final weeklyFocusProvider =
    FutureProvider.autoDispose<List<DailyFocusSummary>>((ref) {
  return ref.watch(focusRepositoryProvider).getSessionsLast7Days();
});

// ── Focus Limits (App Usage Limits) ──────────────────────────────────────────

final focusLimitsDataSourceProvider =
    Provider<FocusLimitsLocalDatasource>((ref) {
  return FocusLimitsLocalDatasource();
});

final focusLimitsRepositoryProvider = Provider<FocusLimitsRepository>((ref) {
  return FocusLimitsRepositoryImpl(
    datasource: ref.watch(focusLimitsDataSourceProvider),
  );
});

/// Current focus settings (enable state, global/per-app limits).
final focusSettingsProvider = FutureProvider<FocusSettings>((ref) {
  return ref.watch(focusLimitsRepositoryProvider).loadSettings();
});

/// All tracked app limits.
final focusLimitsProvider = FutureProvider<List<AppLimit>>((ref) {
  return ref.watch(focusLimitsRepositoryProvider).getAllLimits();
});

/// Today's usage in whole minutes for one package, kept current by the
/// 60-second usage sync. Null when no usage is available for it.
final appUsageMinutesProvider =
    FutureProvider.autoDispose.family<int?, String>((ref, packageName) async {
  final usages = await ref.watch(syncTodayUsageProvider.future);
  final seconds = LimitEvaluator.secondsByPackage(usages)[packageName];
  return seconds == null ? null : seconds ~/ 60;
});

/// Notifier for updating focus settings.
class FocusSettingsNotifier extends AsyncNotifier<FocusSettings> {
  @override
  Future<FocusSettings> build() async {
    try {
      if (kDebugMode) debugPrint('[FocusSettings] Loading settings...');
      final settings =
          await ref.read(focusLimitsRepositoryProvider).loadSettings().timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  if (kDebugMode) debugPrint('[FocusSettings] loadSettings timed out, using disabled');
                  return FocusSettings.disabled;
                },
              );
      if (kDebugMode) debugPrint('[FocusSettings] Loaded: enabled=${settings.isEnabled}');
      return settings;
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusSettingsNotifier.build');
      return FocusSettings.disabled;
    }
  }

  /// Toggle Focus Mode on/off.
  Future<void> toggleFocusMode(bool enabled) async {
    try {
      final current = state.valueOrNull ?? FocusSettings.disabled;
      final updated = current.copyWith(isEnabled: enabled);
      await ref.read(focusLimitsRepositoryProvider).saveSettings(updated);
      if (kDebugMode) debugPrint('[FocusSettings] Toggled to: $enabled');
      state = AsyncValue.data(updated);
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusSettingsNotifier.toggleFocusMode');
    }
  }

  /// Update the global daily limit.
  Future<void> setGlobalLimit(int? minutes) async {
    try {
      final current = state.valueOrNull ?? FocusSettings.disabled;
      final updated = minutes == null
          ? current.copyWith(clearGlobalLimit: true)
          : current.copyWith(globalLimitMinutes: minutes);
      await ref.read(focusLimitsRepositoryProvider).saveSettings(updated);
      if (kDebugMode) debugPrint('[FocusSettings] Set global limit: ${minutes}m');
      state = AsyncValue.data(updated);
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusSettingsNotifier.setGlobalLimit');
    }
  }

  /// Update per-app limits.
  Future<void> updatePerAppLimits(List<AppLimit> limits) async {
    try {
      final current = state.valueOrNull ?? FocusSettings.disabled;
      final updated = current.copyWith(perAppLimits: limits);
      await ref.read(focusLimitsRepositoryProvider).saveSettings(updated);
      if (kDebugMode) debugPrint('[FocusSettings] Updated ${limits.length} app limits');
      state = AsyncValue.data(updated);
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusSettingsNotifier.updatePerAppLimits');
    }
  }

  /// Grant a temporary break for an exceeded app limit.
  void grantBreak(String appName, int durationMinutes, {String? packageName}) {
    ref
        .read(limitExceededProvider.notifier)
        .grantBreak(appName, durationMinutes, packageName: packageName);
  }
}

final focusSettingsNotifierProvider =
    AsyncNotifierProvider<FocusSettingsNotifier, FocusSettings>(
  FocusSettingsNotifier.new,
);
