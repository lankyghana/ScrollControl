import 'package:shared_preferences/shared_preferences.dart';

class ThemePreferenceRepository {
  static const _keyIsDarkTheme = 'theme_is_dark';

  Future<bool> loadIsDarkTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsDarkTheme) ?? true;
  }

  Future<void> saveIsDarkTheme(bool isDarkTheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsDarkTheme, isDarkTheme);
  }
}
