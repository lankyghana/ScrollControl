import 'dart:collection';
import 'dart:typed_data';
import 'usage_stats_datasource.dart';

/// In-memory cache for app icons to avoid repeated MethodChannel calls.
///
/// Bounded (least-recently-used eviction) so a device with hundreds of
/// installed apps cannot grow it without limit, and it remembers apps that
/// have no icon so they are not re-queried on every usage sync.
class AppIconCache {
  static final AppIconCache _instance = AppIconCache._internal();

  factory AppIconCache() {
    return _instance;
  }

  AppIconCache._internal();

  /// Maximum number of icons kept in memory. Icons are small PNGs (see
  /// MainActivity.getAppIconBytes), so this stays well under a few MB.
  static const maxEntries = 64;

  /// packageName → icon ByteArray, least recently used first.
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  /// Packages the OS reported no icon for (uninstalled, hidden, error).
  final Set<String> _missing = {};

  /// Singleton instance
  static AppIconCache get instance => _instance;

  /// Get icon from cache, or fetch if not cached.
  Future<Uint8List?> getIcon(
    String packageName,
    UsageStatsDatasource usageDataSource,
  ) async {
    final cached = _cache.remove(packageName);
    if (cached != null) {
      _cache[packageName] = cached; // mark as most recently used
      return cached;
    }
    if (_missing.contains(packageName)) return null;

    // Fetch from Android
    final icon = await usageDataSource.getAppIcon(packageName);

    if (icon == null) {
      _missing.add(packageName);
      return null;
    }

    _cache[packageName] = icon;
    if (_cache.length > maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return icon;
  }

  /// Clear the cache (useful for testing or memory cleanup)
  void clear() {
    _cache.clear();
    _missing.clear();
  }

  /// Get current cache size (for debugging)
  int get size => _cache.length;
}
