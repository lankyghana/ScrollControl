import 'dart:typed_data';
import 'usage_stats_datasource.dart';

/// In-memory cache for app icons to avoid repeated MethodChannel calls.
class AppIconCache {
  static final AppIconCache _instance = AppIconCache._internal();

  factory AppIconCache() {
    return _instance;
  }

  AppIconCache._internal();

  /// packageName → icon ByteArray
  final Map<String, Uint8List> _cache = {};

  /// Singleton instance
  static AppIconCache get instance => _instance;

  /// Get icon from cache, or fetch if not cached.
  Future<Uint8List?> getIcon(
    String packageName,
    UsageStatsDatasource usageDataSource,
  ) async {
    // Return from cache if available
    if (_cache.containsKey(packageName)) {
      return _cache[packageName];
    }

    // Fetch from Android
    final icon = await usageDataSource.getAppIcon(packageName);

    // Cache the result (including null)
    if (icon != null) {
      _cache[packageName] = icon;
    }

    return icon;
  }

  /// Clear the cache (useful for testing or memory cleanup)
  void clear() {
    _cache.clear();
  }

  /// Get current cache size (for debugging)
  int get size => _cache.length;
}
