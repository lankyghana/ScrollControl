import 'dart:typed_data';

class AppUsage {
  const AppUsage({
    required this.appName,
    required this.packageName,
    required this.usageTime,
    required this.date,
    this.icon,
  });

  final String appName;
  final String packageName;

  /// Total usage in seconds for this entry.
  final int usageTime;

  /// The calendar day this usage belongs to (time component is ignored).
  final DateTime date;

  /// App icon as PNG ByteArray (optional, loaded asynchronously)
  final Uint8List? icon;

  /// Copy with method to create a new instance with optional field updates
  AppUsage copyWith({
    String? appName,
    String? packageName,
    int? usageTime,
    DateTime? date,
    Uint8List? icon,
  }) {
    return AppUsage(
      appName: appName ?? this.appName,
      packageName: packageName ?? this.packageName,
      usageTime: usageTime ?? this.usageTime,
      date: date ?? this.date,
      icon: icon ?? this.icon,
    );
  }
}
