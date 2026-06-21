import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../usage/presentation/providers/usage_providers.dart';
import '../../data/datasources/focus_local_datasource.dart';
import '../../data/datasources/focus_limits_local_datasource.dart';
import '../../data/repositories/focus_repository_impl.dart';
import '../../data/repositories/focus_limits_repository_impl.dart';
import '../../domain/entities/app_limit.dart';
import '../../domain/entities/daily_focus_summary.dart';
import '../../domain/entities/focus_session.dart';
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
final weeklyFocusProvider = FutureProvider<List<DailyFocusSummary>>((ref) {
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

/// Notifier for updating focus settings.
class FocusSettingsNotifier extends AsyncNotifier<FocusSettings> {
  @override
  Future<FocusSettings> build() async {
    try {
      debugPrint('[FocusSettings] Loading settings...');
      final settings =
          await ref.read(focusLimitsRepositoryProvider).loadSettings().timeout(
                const Duration(seconds: 5),
                onTimeout: () {
                  debugPrint('[FocusSettings] loadSettings timed out, using disabled');
                  return FocusSettings.disabled;
                },
              );
      debugPrint('[FocusSettings] Loaded: enabled=${settings.isEnabled}');
      return settings;
    } catch (e) {
      debugPrint('[FocusSettings] Error loading: $e');
      return FocusSettings.disabled;
    }
  }

  /// Toggle Focus Mode on/off.
  Future<void> toggleFocusMode(bool enabled) async {
    try {
      final current = state.valueOrNull ?? FocusSettings.disabled;
      final updated = current.copyWith(isEnabled: enabled);
      await ref.read(focusLimitsRepositoryProvider).saveSettings(updated);
      debugPrint('[FocusSettings] Toggled to: $enabled');
      state = AsyncValue.data(updated);
    } catch (e) {
      debugPrint('[FocusSettings] Error toggling: $e');
    }
  }

  /// Update the global daily limit.
  Future<void> setGlobalLimit(int? minutes) async {
    try {
      final current = state.valueOrNull ?? FocusSettings.disabled;
      final updated = current.copyWith(globalLimitMinutes: minutes);
      await ref.read(focusLimitsRepositoryProvider).saveSettings(updated);
      debugPrint('[FocusSettings] Set global limit: ${minutes}m');
      state = AsyncValue.data(updated);
    } catch (e) {
      debugPrint('[FocusSettings] Error setting limit: $e');
    }
  }

  /// Update per-app limits.
  Future<void> updatePerAppLimits(List<AppLimit> limits) async {
    try {
      final current = state.valueOrNull ?? FocusSettings.disabled;
      final updated = current.copyWith(perAppLimits: limits);
      await ref.read(focusLimitsRepositoryProvider).saveSettings(updated);
      debugPrint('[FocusSettings] Updated ${limits.length} app limits');
      state = AsyncValue.data(updated);
    } catch (e) {
      debugPrint('[FocusSettings] Error updating limits: $e');
    }
  }

  /// Grant a temporary break for an exceeded app limit.
  void grantBreak(String appName, int durationMinutes) {
    ref.read(limitExceededProvider.notifier).grantBreak(appName, durationMinutes);
  }
}

final focusSettingsNotifierProvider =
    AsyncNotifierProvider<FocusSettingsNotifier, FocusSettings>(
  FocusSettingsNotifier.new,
);
