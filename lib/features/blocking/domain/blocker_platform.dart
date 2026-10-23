import 'block_snapshot.dart';

/// The special permissions blocking depends on. None of them can be granted
/// from a dialog: the user must flip each one in Android Settings.
class BlockerPermissions {
  const BlockerPermissions({
    required this.usageAccess,
    required this.overlay,
    this.notifications = true,
  });

  static const none = BlockerPermissions(usageAccess: false, overlay: false);

  /// Usage Access: lets the service see which app is in the foreground.
  final bool usageAccess;

  /// "Display over other apps": lets the service show the block screen.
  final bool overlay;

  /// Notification permission (Android 13+). Only affects the visibility of the
  /// service's status notification, so it is not required for blocking.
  final bool notifications;

  bool get ready => usageAccess && overlay;

  List<String> get missing => [
        if (!usageAccess) 'Usage Access',
        if (!overlay) 'Display over other apps',
      ];
}

/// What the native side reports about itself.
class BlockerRuntimeStatus {
  const BlockerRuntimeStatus({
    this.serviceRunning = false,
    this.batteryOptimized = false,
    this.suspendedReason,
  });

  final bool serviceRunning;

  /// True when Android may restrict the service in the background. Advisory.
  final bool batteryOptimized;

  /// Set when the native service stopped itself, e.g. `permission_revoked`.
  final String? suspendedReason;
}

class LaunchableApp {
  const LaunchableApp({required this.packageName, required this.appName});

  final String packageName;
  final String appName;
}

/// The native blocker could not do what was asked.
class BlockerUnavailableException implements Exception {
  const BlockerUnavailableException(this.code, [this.message]);

  /// `background_restricted` when Android refused to start the foreground
  /// service; anything else is a generic failure.
  final String code;
  final String? message;

  bool get isBackgroundRestricted => code == 'background_restricted';

  @override
  String toString() => 'BlockerUnavailableException($code, $message)';
}

/// Boundary to the Android blocking service. Implemented over a
/// MethodChannel in production and faked in tests.
abstract interface class BlockerPlatform {
  Future<BlockerPermissions> permissions();

  Future<BlockerRuntimeStatus> status();

  /// Opens the matching Android Settings page. Nothing is granted silently.
  Future<void> openOverlaySettings();
  Future<void> openUsageSettings();
  Future<void> openBatterySettings();

  /// Replaces the rules the native service enforces (persisted natively so
  /// they survive process death and reboot).
  Future<void> applySnapshot(BlockSnapshot snapshot);

  /// Starts the foreground service. Throws [BlockerUnavailableException].
  Future<void> startService();

  Future<void> stopService();

  /// Launchable apps for the picker (no QUERY_ALL_PACKAGES needed).
  Future<List<LaunchableApp>> launchableApps();

  /// A route the native block screen asked the app to open, once.
  Future<String?> consumePendingRoute();
}
