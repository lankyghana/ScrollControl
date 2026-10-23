import '../../../core/errors/error_logger.dart';
import 'block_snapshot.dart';
import 'blocker_platform.dart';

enum BlockingStatus {
  /// The user has not enabled app blocking.
  off,

  /// Enabled, but a required Android permission is missing or was revoked.
  needsPermission,

  /// Enabled and permitted, but no limit or session currently needs enforcing.
  idle,

  /// The native service is enforcing restrictions.
  active,

  /// Android refused to run the service in the background.
  restricted,

  /// The native blocker is missing or failed.
  unavailable,
}

class BlockingState {
  const BlockingState({
    this.enabled = false,
    this.status = BlockingStatus.off,
    this.permissions = BlockerPermissions.none,
    this.runtime = const BlockerRuntimeStatus(),
    this.message,
  });

  static const initial = BlockingState();

  final bool enabled;
  final BlockingStatus status;
  final BlockerPermissions permissions;
  final BlockerRuntimeStatus runtime;

  /// Plain-language explanation for the UI when something needs attention.
  final String? message;

  bool get isEnforcing => status == BlockingStatus.active;
}

/// Persists whether the user opted in to app blocking.
abstract interface class BlockingEnabledStore {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

/// Decides what the native blocker should be doing and makes it so.
///
/// It is the only place that starts or stops the service, which is what keeps
/// a single instance running. It never requests or grants a permission; it
/// only observes them and tells the user what is missing.
class BlockingCoordinator {
  BlockingCoordinator({
    required BlockerPlatform platform,
    required BlockingEnabledStore enabledStore,
    required Future<BlockSnapshot> Function() buildSnapshot,
  })  : _platform = platform,
        _store = enabledStore,
        _buildSnapshot = buildSnapshot;

  final BlockerPlatform _platform;
  final BlockingEnabledStore _store;
  final Future<BlockSnapshot> Function() _buildSnapshot;

  /// Serialises calls so rapid state changes cannot interleave start/stop.
  Future<void> _queue = Future.value();

  Future<BlockingState> setEnabled(bool enabled) async {
    await _store.setEnabled(enabled);
    return sync();
  }

  /// Re-evaluates permissions and rules, then starts, updates or stops the
  /// service. Safe to call as often as needed; never throws.
  Future<BlockingState> sync() {
    final completer = _queue.then((_) => _syncNow());
    _queue = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  Future<BlockingState> _syncNow() async {
    var enabled = false;
    try {
      enabled = await _store.isEnabled();
      if (!enabled) {
        await _shutDown();
        return BlockingState.initial;
      }

      final BlockerPermissions permissions;
      try {
        permissions = await _platform.permissions();
      } on BlockerUnavailableException catch (e, st) {
        ErrorLogger.log(e, st, context: 'BlockingCoordinator.permissions');
        return _unavailable(enabled);
      }

      if (!permissions.ready) {
        // Permission missing, or revoked while blocking was running: stop
        // enforcing immediately and drop the stored rules.
        await _shutDown();
        return BlockingState(
          enabled: true,
          status: BlockingStatus.needsPermission,
          permissions: permissions,
          message: 'Blocking is paused. Grant ${permissions.missing.join(' and ')} '
              'to turn it on.',
        );
      }

      final snapshot = await _buildSnapshot();
      if (!snapshot.hasRules) {
        await _shutDown();
        return BlockingState(
          enabled: true,
          status: BlockingStatus.idle,
          permissions: permissions,
          runtime: await _safeStatus(),
        );
      }

      try {
        await _platform.applySnapshot(snapshot);
        await _platform.startService();
      } on BlockerUnavailableException catch (e, st) {
        ErrorLogger.log(e, st, context: 'BlockingCoordinator.start');
        return BlockingState(
          enabled: true,
          status: e.isBackgroundRestricted
              ? BlockingStatus.restricted
              : BlockingStatus.unavailable,
          permissions: permissions,
          runtime: await _safeStatus(),
          message: e.isBackgroundRestricted
              ? 'Android is restricting ScrollControl in the background, so '
                  'blocking cannot run. Open the app and check battery '
                  'settings.'
              : 'The blocking service could not start. Limits are still '
                  'tracked, but apps will not be blocked.',
        );
      }

      return BlockingState(
        enabled: true,
        status: BlockingStatus.active,
        permissions: permissions,
        runtime: await _safeStatus(),
      );
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'BlockingCoordinator.sync');
      return _unavailable(enabled);
    }
  }

  BlockingState _unavailable(bool enabled) => BlockingState(
        enabled: enabled,
        status: BlockingStatus.unavailable,
        message: 'App blocking is not available on this device right now.',
      );

  Future<BlockerRuntimeStatus> _safeStatus() async {
    try {
      return await _platform.status();
    } catch (_) {
      return const BlockerRuntimeStatus();
    }
  }

  /// Stops the service and clears native rules. Failures are logged only:
  /// there is nothing more to do if the native side is already gone.
  Future<void> _shutDown() async {
    try {
      await _platform.applySnapshot(BlockSnapshot.empty);
      await _platform.stopService();
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'BlockingCoordinator.shutDown');
    }
  }
}
