import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../focus/presentation/providers/focus_providers.dart';
import '../../../focus/presentation/providers/limit_exceeded_provider.dart';
import '../../../home/presentation/providers/focus_session_provider.dart';
import '../../../usage/presentation/providers/permission_provider.dart';
import '../../data/method_channel_blocker_platform.dart';
import '../../data/prefs_blocking_enabled_store.dart';
import '../../domain/block_snapshot.dart';
import '../../domain/blocker_platform.dart';
import '../../domain/blocking_coordinator.dart';
import '../../domain/snapshot_composer.dart';

final blockerPlatformProvider = Provider<BlockerPlatform>(
  (_) => const MethodChannelBlockerPlatform(),
);

final blockingEnabledStoreProvider = Provider<BlockingEnabledStore>(
  (_) => const PrefsBlockingEnabledStore(),
);

final blockingCoordinatorProvider = Provider<BlockingCoordinator>((ref) {
  return BlockingCoordinator(
    platform: ref.watch(blockerPlatformProvider),
    enabledStore: ref.watch(blockingEnabledStoreProvider),
    buildSnapshot: () => _buildSnapshot(ref),
  );
});

Future<BlockSnapshot> _buildSnapshot(Ref ref) async {
  final settings = await ref.read(focusLimitsRepositoryProvider).loadSettings();
  final session = ref.read(focusSessionProvider);
  final now = DateTime.now();

  final breaks = <String, DateTime>{};
  for (final b in ref.read(limitExceededProvider).activeBreaks) {
    final pkg = b.packageName;
    if (pkg == null || !b.isActive) continue;
    final existing = breaks[pkg];
    if (existing == null || b.endsAt.isAfter(existing)) breaks[pkg] = b.endsAt;
  }

  return composeSnapshot(
    settings: settings,
    sessionApps: session.isRunning ? session.blockedApps : const [],
    sessionEndsAt: session.isRunning ? session.endsAt : null,
    breaksUntil: breaks,
    now: now,
  );
}

class BlockingNotifier extends Notifier<BlockingState> {
  Timer? _debounce;

  @override
  BlockingState build() {
    ref.onDispose(() => _debounce?.cancel());
    return BlockingState.initial;
  }

  /// Re-checks permissions and rules right now (app resume, user actions).
  Future<void> sync() async {
    _debounce?.cancel();
    final next = await ref.read(blockingCoordinatorProvider).sync();
    state = next;
  }

  /// Coalesces bursts of changes (e.g. dragging a limit slider) into one sync.
  void requestSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => unawaited(sync()));
  }

  Future<void> setEnabled(bool enabled) async {
    _debounce?.cancel();
    state = await ref.read(blockingCoordinatorProvider).setEnabled(enabled);
  }
}

final blockingProvider =
    NotifierProvider<BlockingNotifier, BlockingState>(BlockingNotifier.new);

/// Keeps the native blocker in step with settings, sessions, breaks and the
/// Usage Access permission. Watch it once from the root widget.
final blockingInitProvider = Provider<void>((ref) {
  void request() => ref.read(blockingProvider.notifier).requestSync();

  ref.listen(focusSessionProvider.select((s) => s.blockSignature), (_, __) => request());
  ref.listen(focusSettingsNotifierProvider, (_, __) => request());
  ref.listen(
    limitExceededProvider.select(
      (s) => s.activeBreaks
          .where((b) => b.isActive && b.packageName != null)
          .map((b) => '${b.packageName}:${b.endsAt.millisecondsSinceEpoch}')
          .join(','),
    ),
    (_, __) => request(),
  );
  ref.listen(usagePermissionProvider, (_, __) => request());

  unawaited(ref.read(blockingProvider.notifier).sync());
});

/// Launchable apps for pickers; loaded once per use of the picker.
final launchableAppsProvider =
    FutureProvider.autoDispose<List<LaunchableApp>>((ref) async {
  try {
    return await ref.watch(blockerPlatformProvider).launchableApps();
  } on BlockerUnavailableException {
    return const [];
  }
});
