import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_control/features/blocking/domain/block_snapshot.dart';
import 'package:scroll_control/features/blocking/domain/blocker_platform.dart';
import 'package:scroll_control/features/blocking/domain/blocking_coordinator.dart';

import '../../helpers/fakes.dart';

const _insta = BlockedApp(packageName: 'com.insta', appName: 'Instagram');

BlockSnapshot _activeRules() => BlockSnapshot(
      session: SessionRule(
        endsAtMs: DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        apps: const [_insta],
      ),
    );

void main() {
  late FakeBlockerPlatform platform;
  late FakeBlockingEnabledStore store;
  late BlockSnapshot snapshot;
  late BlockingCoordinator coordinator;

  setUp(() {
    platform = FakeBlockerPlatform();
    store = FakeBlockingEnabledStore(enabled: true);
    snapshot = _activeRules();
    coordinator = BlockingCoordinator(
      platform: platform,
      enabledStore: store,
      buildSnapshot: () async => snapshot,
    );
  });

  group('opt-in', () {
    test('nothing starts until the user enables blocking', () async {
      store.enabled = false;

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.off);
      expect(platform.startCalls, 0);
      expect(platform.running, isFalse);
    });

    test('enabling starts blocking when permissions are in place', () async {
      store.enabled = false;

      final state = await coordinator.setEnabled(true);

      expect(state.status, BlockingStatus.active);
      expect(platform.running, isTrue);
      expect(platform.lastSnapshot!.session, isNotNull);
    });

    test('disabling stops the service and clears native rules', () async {
      await coordinator.sync();
      expect(platform.running, isTrue);

      final state = await coordinator.setEnabled(false);

      expect(state.status, BlockingStatus.off);
      expect(platform.running, isFalse);
      expect(platform.lastSnapshot!.hasRules, isFalse);
    });
  });

  group('permissions', () {
    test('granted: blocking becomes active', () async {
      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.active);
      expect(state.isEnforcing, isTrue);
      expect(platform.startCalls, 1);
    });

    test('denied: service is not started and the user is told what is missing',
        () async {
      platform.perms =
          const BlockerPermissions(usageAccess: true, overlay: false);

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.needsPermission);
      expect(state.message, contains('Display over other apps'));
      expect(platform.startCalls, 0);
      expect(platform.running, isFalse);
    });

    test('the coordinator never opens Settings by itself', () async {
      platform.perms = BlockerPermissions.none;

      await coordinator.sync();

      expect(platform.usageSettingsOpened, 0);
      expect(platform.overlaySettingsOpened, 0);
    });

    test('revoked while blocking: enforcement stops immediately', () async {
      await coordinator.sync();
      expect(platform.running, isTrue);

      platform.perms = const BlockerPermissions(usageAccess: false, overlay: true);
      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.needsPermission);
      expect(platform.running, isFalse);
      expect(platform.lastSnapshot!.hasRules, isFalse,
          reason: 'stale rules must not linger natively');
    });

    test('re-granting resumes blocking without re-enabling', () async {
      platform.perms = BlockerPermissions.none;
      await coordinator.sync();

      platform.perms = const BlockerPermissions(usageAccess: true, overlay: true);
      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.active);
      expect(platform.running, isTrue);
    });
  });

  group('rules', () {
    test('idle (and no service) when there is nothing to enforce', () async {
      snapshot = BlockSnapshot.empty;

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.idle);
      expect(platform.running, isFalse);
    });

    test('a session ending stops the service', () async {
      await coordinator.sync();
      expect(platform.running, isTrue);

      snapshot = BlockSnapshot.empty; // session finished
      await coordinator.sync();

      expect(platform.running, isFalse);
    });

    test('rapid syncs never leave more than one running service', () async {
      await Future.wait([
        coordinator.sync(),
        coordinator.sync(),
        coordinator.sync(),
      ]);

      expect(platform.running, isTrue);
      // start is idempotent natively; the coordinator serialises the calls.
      expect(platform.startCalls, 3);
      expect(platform.stopCalls, 0);
    });
  });

  group('blocking service unavailable', () {
    test('start failure is reported, not thrown', () async {
      platform.startFailure =
          const BlockerUnavailableException('BLOCKER_ERROR', 'boom');

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.unavailable);
      expect(state.message, isNotNull);
    });

    test('a missing native channel is reported, not thrown', () async {
      platform.permissionsFailure =
          const BlockerUnavailableException('unavailable');

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.unavailable);
      expect(platform.startCalls, 0);
    });

    test('a failing snapshot builder does not crash the coordinator', () async {
      final broken = BlockingCoordinator(
        platform: platform,
        enabledStore: store,
        buildSnapshot: () async => throw StateError('db closed'),
      );

      final state = await broken.sync();

      expect(state.status, BlockingStatus.unavailable);
    });
  });

  group('background execution restrictions', () {
    test('Android refusing the foreground service is surfaced as restricted',
        () async {
      platform.startFailure =
          const BlockerUnavailableException('background_restricted');

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.restricted);
      expect(state.message, contains('restricting'));
      expect(state.isEnforcing, isFalse);
    });

    test('battery optimisation is exposed so the UI can suggest a fix',
        () async {
      platform.runtime = const BlockerRuntimeStatus(
        serviceRunning: true,
        batteryOptimized: true,
      );

      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.active);
      expect(state.runtime.batteryOptimized, isTrue);
    });

    test('recovers once Android allows the service again', () async {
      platform.startFailure =
          const BlockerUnavailableException('background_restricted');
      await coordinator.sync();

      platform.startFailure = null;
      final state = await coordinator.sync();

      expect(state.status, BlockingStatus.active);
    });
  });
}
