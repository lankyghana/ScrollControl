import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/block_snapshot.dart';
import '../domain/blocker_platform.dart';

/// [BlockerPlatform] backed by the `scroll_control/blocker` MethodChannel.
/// Returns safe defaults on non-Android platforms.
class MethodChannelBlockerPlatform implements BlockerPlatform {
  const MethodChannelBlockerPlatform();

  static const _channel = MethodChannel('scroll_control/blocker');

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw BlockerUnavailableException(
        e.code == 'BACKGROUND_RESTRICTED' ? 'background_restricted' : e.code,
        e.message,
      );
    } on MissingPluginException {
      throw const BlockerUnavailableException('unavailable', 'No native blocker');
    }
  }

  @override
  Future<BlockerPermissions> permissions() async {
    if (!_isAndroid) return BlockerPermissions.none;
    final map = await _invoke<Map<dynamic, dynamic>>('permissions');
    return BlockerPermissions(
      usageAccess: map?['usageAccess'] == true,
      overlay: map?['overlay'] == true,
      notifications: map?['notifications'] != false,
    );
  }

  @override
  Future<BlockerRuntimeStatus> status() async {
    if (!_isAndroid) return const BlockerRuntimeStatus();
    final map = await _invoke<Map<dynamic, dynamic>>('status');
    return BlockerRuntimeStatus(
      serviceRunning: map?['serviceRunning'] == true,
      batteryOptimized: map?['batteryOptimized'] == true,
      suspendedReason: map?['suspendedReason'] as String?,
    );
  }

  @override
  Future<void> openOverlaySettings() async {
    if (_isAndroid) await _invoke<void>('openOverlaySettings');
  }

  @override
  Future<void> openUsageSettings() async {
    if (_isAndroid) await _invoke<void>('openUsageSettings');
  }

  @override
  Future<void> openBatterySettings() async {
    if (_isAndroid) await _invoke<void>('openBatterySettings');
  }

  @override
  Future<void> applySnapshot(BlockSnapshot snapshot) async {
    if (!_isAndroid) return;
    await _invoke<void>('applySnapshot', jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> startService() async {
    if (!_isAndroid) {
      throw const BlockerUnavailableException('unsupported_platform');
    }
    await _invoke<void>('startService');
  }

  @override
  Future<void> stopService() async {
    if (_isAndroid) await _invoke<void>('stopService');
  }

  @override
  Future<List<LaunchableApp>> launchableApps() async {
    if (!_isAndroid) return const [];
    final raw = await _invoke<List<dynamic>>('launchableApps');
    return [
      for (final item in raw ?? const [])
        LaunchableApp(
          packageName: (item as Map)['packageName'] as String,
          appName: (item['appName'] as String?) ?? item['packageName'] as String,
        ),
    ];
  }

  @override
  Future<String?> consumePendingRoute() async {
    if (!_isAndroid) return null;
    try {
      return await _invoke<String>('consumePendingRoute');
    } on BlockerUnavailableException {
      return null;
    }
  }
}
