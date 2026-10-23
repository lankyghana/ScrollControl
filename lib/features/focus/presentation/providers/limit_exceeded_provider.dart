import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents a break granted for an app (temporary bypass of limit).
class BreakGrant {
  final String appName;

  /// Lets the native blocker honour the break. Null for breaks granted
  /// without a known package.
  final String? packageName;
  final DateTime grantedAt;
  final int durationMinutes;

  BreakGrant({
    required this.appName,
    required this.grantedAt,
    required this.durationMinutes,
    this.packageName,
  });

  DateTime get endsAt => grantedAt.add(Duration(minutes: durationMinutes));

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
  ///
  /// An exceeded flag recorded on an earlier calendar day is ignored: usage
  /// resets at midnight, so yesterday's breach must not block today.
  bool isAppBlocked(String appName, {DateTime? now}) {
    final exceededAt = exceededApps[appName];
    if (exceededAt == null) return false;
    final today = now ?? DateTime.now();
    if (exceededAt.year != today.year ||
        exceededAt.month != today.month ||
        exceededAt.day != today.day) {
      return false;
    }

    // Check if there's an active break for this app
    final hasActivBreak =
        activeBreaks.any((b) => b.appName == appName && b.isActive);
    return !hasActivBreak;
  }

  /// Returns the first blocked app name if any (for overlay).
  String? getFirstBlockedApp({DateTime? now}) {
    return exceededApps.keys.firstWhere(
      (appName) => isAppBlocked(appName, now: now),
      orElse: () => '',
    );
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
  void markLimitExceeded(String appName, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final existing = state.exceededApps[appName];
    // Already flagged today � nothing to do. A stale flag from a previous
    // day is replaced.
    if (existing != null &&
        existing.year == at.year &&
        existing.month == at.month &&
        existing.day == at.day) {
      return;
    }
    // Copy: the initial map is a const (unmodifiable) literal.
    state = LimitExceededState(
      exceededApps: {...state.exceededApps, appName: at},
      activeBreaks: state.activeBreaks,
    );
  }

  /// Hide the blocking overlay for [appName] without granting a break. It
  /// comes back the next time the limit monitor sees the app over its limit.
  void dismiss(String appName) {
    if (!state.exceededApps.containsKey(appName)) return;
    final updated = {...state.exceededApps}..remove(appName);
    state = LimitExceededState(
      exceededApps: updated,
      activeBreaks: state.activeBreaks,
    );
  }

  /// Grant a temporary break for an app.
  void grantBreak(String appName, int durationMinutes, {String? packageName}) {
    final newBreak = BreakGrant(
      appName: appName,
      packageName: packageName,
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
