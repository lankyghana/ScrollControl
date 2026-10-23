import 'package:shared_preferences/shared_preferences.dart';

/// Remembers when an event last produced a notification.
abstract interface class NotificationCooldownStore {
  Future<DateTime?> lastNotified(String key);
  Future<void> markNotified(String key, DateTime at);
}

/// Non-persistent store, used by tests and as the default for services that
/// are not given a persistent one.
class InMemoryCooldownStore implements NotificationCooldownStore {
  final Map<String, DateTime> _times = {};

  @override
  Future<DateTime?> lastNotified(String key) async => _times[key];

  @override
  Future<void> markNotified(String key, DateTime at) async {
    _times[key] = at;
  }
}

/// SharedPreferences-backed store. Shared by the UI isolate and the
/// WorkManager background isolate, so a notification sent by one is seen by
/// the other.
class PrefsCooldownStore implements NotificationCooldownStore {
  const PrefsCooldownStore();

  static const _prefix = 'notif_last_';

  @override
  Future<DateTime?> lastNotified(String key) async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate may have written since this isolate cached its values.
    await prefs.reload();
    final millis = prefs.getInt('$_prefix$key');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  @override
  Future<void> markNotified(String key, DateTime at) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix$key', at.millisecondsSinceEpoch);
  }
}

/// Decides whether an event may notify now, and records it when it does.
class NotificationGate {
  NotificationGate(this._store);

  final NotificationCooldownStore _store;

  /// Returns true (and records [now]) when [key] may notify.
  ///
  /// Suppressed when it last notified less than [cooldown] ago, or, if
  /// [oncePerDay] is set, at any earlier time on the same calendar day. A
  /// record from a previous calendar day never suppresses (daily reset), nor
  /// does one in the future (clock was changed).
  Future<bool> tryAcquire(
    String key, {
    required Duration cooldown,
    bool oncePerDay = false,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final last = await _store.lastNotified(key);

    if (last != null && !last.isAfter(at) && _sameDay(last, at)) {
      if (oncePerDay) return false;
      if (at.difference(last) < cooldown) return false;
    }

    await _store.markNotified(key, at);
    return true;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
