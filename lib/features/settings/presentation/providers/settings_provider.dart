import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/settings_repository.dart';
import '../../domain/interrupt_settings.dart';

// ── Repository ────────────────────────────────────────────────────────────────

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (_) => SettingsRepository(),
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class InterruptSettingsNotifier
    extends AsyncNotifier<InterruptSettings> {
  @override
  Future<InterruptSettings> build() {
    return ref.watch(settingsRepositoryProvider).load();
  }

  Future<void> setEnabled(bool value) => _update(
        (s) => s.copyWith(enabled: value),
      );

  Future<void> setThreshold(int minutes) => _update(
        (s) => s.copyWith(thresholdMinutes: minutes),
      );

  Future<void> setCooldown(int minutes) => _update(
        (s) => s.copyWith(cooldownMinutes: minutes),
      );

  Future<void> _update(InterruptSettings Function(InterruptSettings) fn) async {
    final current = state.valueOrNull ?? InterruptSettings.defaults;
    final next = fn(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);
  }
}

final interruptSettingsProvider =
    AsyncNotifierProvider<InterruptSettingsNotifier, InterruptSettings>(
  InterruptSettingsNotifier.new,
);
