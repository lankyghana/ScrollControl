import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme_preference_repository.dart';

final themePreferenceRepositoryProvider = Provider<ThemePreferenceRepository>(
  (_) => ThemePreferenceRepository(),
);

class ThemePreferenceNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(themePreferenceRepositoryProvider).loadIsDarkTheme();
  }

  Future<void> setDarkTheme(bool isDarkTheme) async {
    state = const AsyncLoading<bool>();
    await ref
        .read(themePreferenceRepositoryProvider)
        .saveIsDarkTheme(isDarkTheme);
    state = AsyncData(isDarkTheme);
  }
}

final themePreferenceProvider =
    AsyncNotifierProvider<ThemePreferenceNotifier, bool>(
  ThemePreferenceNotifier.new,
);
