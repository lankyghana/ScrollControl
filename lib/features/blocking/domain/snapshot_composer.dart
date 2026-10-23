import '../../focus/domain/entities/focus_settings.dart';
import 'block_snapshot.dart';

/// Builds the rules the native blocker enforces from the app's own state.
///
/// Daily Focus Mode and Focus Sessions are independent: a session is included
/// whenever one is running, whether or not Focus Mode is on.
BlockSnapshot composeSnapshot({
  required FocusSettings settings,
  required List<BlockedApp> sessionApps,
  required DateTime? sessionEndsAt,
  required Map<String, DateTime> breaksUntil,
  required DateTime now,
}) {
  final nowMs = now.millisecondsSinceEpoch;

  final session = sessionEndsAt != null &&
          sessionEndsAt.millisecondsSinceEpoch > nowMs &&
          sessionApps.isNotEmpty
      ? SessionRule(
          endsAtMs: sessionEndsAt.millisecondsSinceEpoch,
          apps: sessionApps,
        )
      : null;

  final globalMinutes = settings.globalLimitMinutes;

  return BlockSnapshot(
    dailyEnabled: settings.isEnabled,
    globalLimitSeconds:
        globalMinutes != null && globalMinutes > 0 ? globalMinutes * 60 : null,
    appLimits: [
      for (final l in settings.perAppLimits)
        if (l.dailyLimitMinutes > 0)
          AppLimitRule(
            packageName: l.packageName,
            appName: l.appName,
            limitSeconds: l.dailyLimitMinutes * 60,
          ),
    ],
    breaksUntilMs: {
      for (final e in breaksUntil.entries)
        if (e.value.millisecondsSinceEpoch > nowMs)
          e.key: e.value.millisecondsSinceEpoch,
    },
    session: session,
  );
}
