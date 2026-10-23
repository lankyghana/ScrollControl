import 'package:shared_preferences/shared_preferences.dart';
import '../domain/blocking_coordinator.dart';

/// Stores the user's explicit opt-in. Defaults to off: nothing is enforced
/// until the user turns app blocking on themselves.
class PrefsBlockingEnabledStore implements BlockingEnabledStore {
  const PrefsBlockingEnabledStore();

  static const _key = 'app_blocking_enabled';

  @override
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
