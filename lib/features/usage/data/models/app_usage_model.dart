import 'dart:typed_data';
import '../../domain/entities/app_usage.dart';

class AppUsageModel extends AppUsage {
  const AppUsageModel({
    this.id,
    required super.appName,
    required super.packageName,
    required super.usageTime,
    required super.date,
    super.icon,
  });

  final int? id;

  /// Construct from a SQLite row map.
  factory AppUsageModel.fromMap(Map<String, dynamic> map) {
    return AppUsageModel(
      id: map['id'] as int?,
      appName: map['app_name'] as String,
      packageName: map['package_name'] as String,
      usageTime: map['usage_time'] as int,
      // Stored as ISO-8601 date string (YYYY-MM-DD)
      date: DateTime.parse(map['date'] as String),
      // Icon is NOT stored in SQLite — loaded separately
      icon: null,
    );
  }

  /// Convert to a SQLite row map (omits id when null — for INSERT).
  /// Icon is NOT persisted to SQLite.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'app_name': appName,
      'package_name': packageName,
      'usage_time': usageTime,
      'date': _dateKey(date),
    };
  }

  /// Convenience constructor that promotes a domain entity to a model.
  factory AppUsageModel.fromEntity(AppUsage entity) {
    return AppUsageModel(
      appName: entity.appName,
      packageName: entity.packageName,
      usageTime: entity.usageTime,
      date: entity.date,
      icon: entity.icon,
    );
  }

  /// Create a copy with optional field updates (including icon).
  @override
  AppUsageModel copyWith({
    int? id,
    String? appName,
    String? packageName,
    int? usageTime,
    DateTime? date,
    Uint8List? icon,
  }) {
    return AppUsageModel(
      id: id ?? this.id,
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      usageTime: usageTime ?? this.usageTime,
      date: date ?? this.date,
      icon: icon ?? this.icon,
    );
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}
