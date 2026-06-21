import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'usage_providers.dart';

/// Manages the current Usage Access permission state.
///
/// Use [UsagePermissionNotifier.recheck] after the user returns from
/// Android Settings so GoRouter re-evaluates the redirect.
class UsagePermissionNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(usageRepositoryProvider).hasUsagePermission();
  }

  /// Re-queries the OS permission state.
  /// Called when the app is resumed from the Settings page.
  Future<void> recheck() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(usageRepositoryProvider).hasUsagePermission(),
    );
  }
}

final usagePermissionProvider =
    AsyncNotifierProvider<UsagePermissionNotifier, bool>(
  UsagePermissionNotifier.new,
);

/// True when the user has explicitly chosen to continue without Usage Access.
/// Persisted only for the current app session (not to disk).
final permissionSkippedProvider = StateProvider<bool>((_) => false);
