import 'package:shared_preferences/shared_preferences.dart';
import '../domain/interrupt_settings.dart';

class SettingsRepository {
  static const _keyEnabled = 'interrupt_enabled';
  static const _keyThreshold = 'threshold_minutes';
  static const _keyCooldown = 'cooldown_minutes';

  Future<InterruptSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return InterruptSettings(
      enabled: prefs.getBool(_keyEnabled) ?? InterruptSettings.defaults.enabled,
      thresholdMinutes: prefs.getInt(_keyThreshold) ??
          InterruptSettings.defaults.thresholdMinutes,
      cooldownMinutes: prefs.getInt(_keyCooldown) ??
          InterruptSettings.defaults.cooldownMinutes,
    );
  }

  Future<void> save(InterruptSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, settings.enabled);
    await prefs.setInt(_keyThreshold, settings.thresholdMinutes);
    await prefs.setInt(_keyCooldown, settings.cooldownMinutes);
  }
}
