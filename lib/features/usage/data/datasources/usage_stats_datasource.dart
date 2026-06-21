import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_usage_model.dart';

/// Contract for reading live usage stats from the device OS.
abstract interface class UsageStatsDatasource {
  /// Returns true when the app has been granted Usage Access by the user.
  Future<bool> hasUsagePermission();

  /// Returns usage stats for the given calendar day.
  /// Returns an empty list when:
  ///   - Permission has not been granted.
  ///   - Running on a non-Android platform (web, Windows).
  ///   - The OS returns no data for that day.
  Future<List<AppUsageModel>> fetchUsageStats(DateTime date);

  /// Returns the package name of the app currently in the foreground,
  /// determined by querying the last 60 seconds of usage stats.
  /// Returns null when permission is denied or platform is non-Android.
  Future<String?> getForegroundApp();

  /// Fetches the app icon for a given package name.
  /// Returns a Uint8List (PNG bytes) or null if not found/available.
  Future<Uint8List?> getAppIcon(String packageName);
}

/// Opens the Android Usage Access settings page so the user can grant
/// permission manually. No-op on non-Android platforms.
Future<void> openAndroidUsageSettings() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await const MethodChannel('scroll_control/usage')
        .invokeMethod<void>('openUsageSettings');
  } on PlatformException catch (e) {
    if (kDebugMode) {
      debugPrint('[UsageStats] openUsageSettings error: ${e.message}');
    }
  } on MissingPluginException {
    // Non-Android platform — silently ignore
  }
}

/// Android implementation backed by [UsageStatsManager] via a [MethodChannel].
class AndroidUsageStatsDatasource implements UsageStatsDatasource {
  const AndroidUsageStatsDatasource();

  static const _channel = MethodChannel('scroll_control/usage');

  @override
  Future<bool> hasUsagePermission() async {
    // Only meaningful on Android; other platforms always return false.
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsagePermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<AppUsageModel>> fetchUsageStats(DateTime date) async {
    if (defaultTargetPlatform != TargetPlatform.android) return [];

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getUsageStats',
        {
          'startTime': startOfDay.millisecondsSinceEpoch,
          'endTime': endOfDay.millisecondsSinceEpoch,
        },
      );

      if (raw == null || raw.isEmpty) return [];

      return raw
          .cast<Map<dynamic, dynamic>>()
          .map((map) => AppUsageModel(
                appName: (map['appName'] as String?) ?? 'Unknown',
                packageName: (map['packageName'] as String?) ?? '',
                usageTime: (map['usageTime'] as num?)?.toInt() ?? 0,
                date: date,
              ))
          .where((m) => m.usageTime > 0 && m.packageName.isNotEmpty)
          .toList();
    } on PlatformException catch (e) {
      // PERMISSION_DENIED → caller receives empty list (no crash)
      if (e.code == 'PERMISSION_DENIED') return [];
      if (kDebugMode) {
        debugPrint('[UsageStats] PlatformException: ${e.code} — ${e.message}');
      }
      return [];
    } on MissingPluginException {
      // Running on web or desktop for UI preview
      return [];
    }
  }

  @override
  Future<String?> getForegroundApp() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('getForegroundApp');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[UsageStats] getForegroundApp error: ${e.message}');
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Uint8List?> getAppIcon(String packageName) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final iconBytes = await _channel.invokeMethod<Uint8List>(
        'getAppIcon',
        {'packageName': packageName},
      );
      return iconBytes;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[UsageStats] getAppIcon error for $packageName: ${e.message}');
      }
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
