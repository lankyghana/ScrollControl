import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a break granted for an app (temporary bypass of limit).
class BreakGrant {
  final String appName;
  final DateTime grantedAt;
  final int durationMinutes;

  BreakGrant({
    required this.appName,
    required this.grantedAt,
    required this.durationMinutes,
  });

  /// Check if this break is still active.
  bool get isActive {
    final elapsed = DateTime.now().difference(grantedAt).inMinutes;
    return elapsed < durationMinutes;
  }
}

/// Tracks which apps have exceeded their daily limits and are currently blocked.
class LimitExceededState {
  /// App name → when it exceeded the limit
  final Map<String, DateTime> exceededApps;

  /// Active breaks granted by the user
  final List<BreakGrant> activeBreaks;

  const LimitExceededState({
    required this.exceededApps,
    required this.activeBreaks,
  });

  /// Check if an app is currently blocked (exceeded limit and no active break).
  bool isAppBlocked(String appName) {
    if (!exceededApps.containsKey(appName)) return false;

    // Check if there's an active break for this app
    final hasActivBreak =
        activeBreaks.any((b) => b.appName == appName && b.isActive);
    return !hasActivBreak;
  }

  /// Returns the first blocked app name if any (for overlay).
  String? getFirstBlockedApp() {
    return exceededApps.keys
        .firstWhere((appName) => isAppBlocked(appName), orElse: () => '');
  }
}

/// Notifier for managing limit exceeded state.
class LimitExceededNotifier extends StateNotifier<LimitExceededState> {
  LimitExceededNotifier()
      : super(const LimitExceededState(
          exceededApps: {},
          activeBreaks: [],
        ));

  /// Mark an app as having exceeded its limit.
  void markLimitExceeded(String appName) {
    final updated = state.exceededApps;
    if (!updated.containsKey(appName)) {
      updated[appName] = DateTime.now();
      state = LimitExceededState(
        exceededApps: updated,
        activeBreaks: state.activeBreaks,
      );
    }
  }

  /// Grant a temporary break for an app.
  void grantBreak(String appName, int durationMinutes) {
    final newBreak = BreakGrant(
      appName: appName,
      grantedAt: DateTime.now(),
      durationMinutes: durationMinutes,
    );

    final updated = [...state.activeBreaks, newBreak];
    state = LimitExceededState(
      exceededApps: state.exceededApps,
      activeBreaks: updated,
    );
  }

  /// Clear expired breaks and reset state at midnight.
  void refreshExpiredBreaks() {
    final active = state.activeBreaks.where((b) => b.isActive).toList();
    state = LimitExceededState(
      exceededApps: state.exceededApps,
      activeBreaks: active,
    );
  }

  /// Reset exceeded limits at midnight (new day).
  void resetLimits() {
    state = const LimitExceededState(
      exceededApps: {},
      activeBreaks: [],
    );
  }
}

/// Provider for tracking limit exceeded state.
final limitExceededProvider =
    StateNotifierProvider<LimitExceededNotifier, LimitExceededState>((ref) {
  return LimitExceededNotifier();
});
