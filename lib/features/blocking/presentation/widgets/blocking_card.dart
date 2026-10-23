import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/blocking_coordinator.dart';
import '../providers/blocking_providers.dart';

/// Opt-in control for real app blocking, with a plain-language explanation of
/// every permission it needs. Nothing is requested until the user asks.
class BlockingCard extends ConsumerWidget {
  const BlockingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(blockingProvider);
    final theme = Theme.of(context);

    return AppCard(
      borderColor: AppColors.primary.withValues(alpha: 0.2),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App blocking',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusLabel(state),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: state.isEnforcing
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: state.enabled,
                onChanged: (value) => _onToggle(context, ref, value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Show a block screen when you open an app that has hit its daily '
            'limit or is part of a running Focus Session.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
          if (state.enabled) ...[
            const SizedBox(height: 16),
            _PermissionRow(
              title: 'Usage Access',
              why: 'Lets ScrollControl see which app is open so it knows '
                  'when a restricted app is opened.',
              granted: state.permissions.usageAccess,
              onGrant: () => ref.read(blockerPlatformProvider).openUsageSettings(),
            ),
            const SizedBox(height: 12),
            _PermissionRow(
              title: 'Display over other apps',
              why: 'Lets ScrollControl draw the block screen on top of a '
                  'restricted app.',
              granted: state.permissions.overlay,
              onGrant: () => ref.read(blockerPlatformProvider).openOverlaySettings(),
            ),
            if (state.message != null) ...[
              const SizedBox(height: 12),
              Text(
                state.message!,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            ],
            if (state.runtime.batteryOptimized &&
                state.status != BlockingStatus.needsPermission) ...[
              const SizedBox(height: 12),
              Text(
                'Battery optimisation is on for ScrollControl. Some phones stop '
                'background services to save power, which can pause blocking.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(blockerPlatformProvider).openBatterySettings(),
                child: const Text('Open battery settings'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Blocking is best-effort. Android can stop background apps, and '
              'you can switch it off here at any time. Nothing leaves your device.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(BlockingState s) => switch (s.status) {
        BlockingStatus.off => 'Off',
        BlockingStatus.needsPermission => 'Paused — permission needed',
        BlockingStatus.idle => 'On — nothing to enforce right now',
        BlockingStatus.active => 'Active',
        BlockingStatus.restricted => 'Restricted by Android',
        BlockingStatus.unavailable => 'Unavailable',
      };

  Future<void> _onToggle(BuildContext context, WidgetRef ref, bool value) async {
    final notifier = ref.read(blockingProvider.notifier);
    if (!value) {
      await notifier.setEnabled(false);
      return;
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Turn on app blocking?'),
        content: const Text(
          'To block apps, ScrollControl needs two permissions that you grant '
          'yourself in Android Settings:\n\n'
          '• Usage Access — to see which app is open.\n'
          '• Display over other apps — to show the block screen.\n\n'
          'ScrollControl does not read your screen or what you type, and '
          'nothing leaves your device. You can turn blocking off at any time, '
          'and the home screen, phone and Settings are never blocked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (agreed == true) await notifier.setEnabled(true);
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.why,
    required this.granted,
    required this.onGrant,
  });

  final String title;
  final String why;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          granted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: granted ? AppColors.success : AppColors.textSecondary,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                why,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        if (!granted)
          TextButton(onPressed: onGrant, child: const Text('Grant')),
      ],
    );
  }
}
