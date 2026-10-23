import 'app_limit.dart';

class FocusSettings {
  const FocusSettings({
    required this.isEnabled,
    this.globalLimitMinutes,
    required this.perAppLimits,
  });

  final bool isEnabled;

  /// Optional global daily usage limit. If set, applies across all apps.
  final int? globalLimitMinutes;

  /// Per-app daily usage limits.
  final List<AppLimit> perAppLimits;

  /// Creates a disabled FocusSettings with empty per-app limits.
  static const FocusSettings disabled = FocusSettings(
    isEnabled: false,
    globalLimitMinutes: null,
    perAppLimits: [],
  );

  /// [clearGlobalLimit] removes the global limit (a null [globalLimitMinutes]
  /// alone means "keep the current value").
  FocusSettings copyWith({
    bool? isEnabled,
    int? globalLimitMinutes,
    bool clearGlobalLimit = false,
    List<AppLimit>? perAppLimits,
  }) {
    return FocusSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      globalLimitMinutes: clearGlobalLimit
          ? null
          : (globalLimitMinutes ?? this.globalLimitMinutes),
      perAppLimits: perAppLimits ?? this.perAppLimits,
    );
  }
}
