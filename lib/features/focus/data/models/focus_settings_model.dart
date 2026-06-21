import 'dart:convert';
import 'app_limit_model.dart';
import '../../domain/entities/focus_settings.dart';

class FocusSettingsModel extends FocusSettings {
  const FocusSettingsModel({
    required super.isEnabled,
    super.globalLimitMinutes,
    required super.perAppLimits,
  });

  /// Convert to JSON for SharedPreferences storage.
  String toJson() {
    return jsonEncode({
      'isEnabled': isEnabled,
      'globalLimitMinutes': globalLimitMinutes,
      'perAppLimits': perAppLimits
          .map((limit) => {
                'packageName': limit.packageName,
                'appName': limit.appName,
                'dailyLimitMinutes': limit.dailyLimitMinutes,
              })
          .toList(),
    });
  }

  /// Reconstruct from JSON string.
  factory FocusSettingsModel.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return FocusSettingsModel(
      isEnabled: map['isEnabled'] as bool,
      globalLimitMinutes: map['globalLimitMinutes'] as int?,
      perAppLimits: (map['perAppLimits'] as List<dynamic>?)?.map((e) {
            final item = e as Map<String, dynamic>;
            return AppLimitModel(
              packageName: item['packageName'] as String,
              appName: item['appName'] as String,
              dailyLimitMinutes: item['dailyLimitMinutes'] as int,
            );
          }).toList() ??
          [],
    );
  }

  factory FocusSettingsModel.fromEntity(FocusSettings entity) {
    return FocusSettingsModel(
      isEnabled: entity.isEnabled,
      globalLimitMinutes: entity.globalLimitMinutes,
      perAppLimits: entity.perAppLimits,
    );
  }
}
