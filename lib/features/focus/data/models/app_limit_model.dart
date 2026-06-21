import '../../domain/entities/app_limit.dart';

class AppLimitModel extends AppLimit {
  const AppLimitModel({
    required super.packageName,
    required super.appName,
    required super.dailyLimitMinutes,
  });

  /// Converts entity to SQLite-friendly map.
  Map<String, dynamic> toMap() {
    return {
      'package_name': packageName,
      'app_name': appName,
      'daily_limit_minutes': dailyLimitMinutes,
    };
  }

  /// Reconstructs from SQLite row.
  factory AppLimitModel.fromMap(Map<String, dynamic> map) {
    return AppLimitModel(
      packageName: map['package_name'] as String,
      appName: map['app_name'] as String,
      dailyLimitMinutes: map['daily_limit_minutes'] as int,
    );
  }
}
