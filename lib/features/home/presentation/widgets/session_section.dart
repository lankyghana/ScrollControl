import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../blocking/presentation/providers/blocking_providers.dart';
import '../../../blocking/presentation/widgets/app_picker.dart';
import '../providers/focus_session_provider.dart';

/// Focus Session status, setup (duration + apps to block) and controls.
class SessionSection extends ConsumerWidget {
  const SessionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(focusSessionProvider);
    final theme = Theme.of(context);
    final active = session.status == FocusSessionStatus.running ||
        session.status == FocusSessionStatus.paused;
    final notifier = ref.read(focusSessionProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: session.isRunning
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.dividerLight,
              ),
              child: Icon(
                Icons.schedule_rounded,
                color: session.isRunning
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.isRunning
                        ? '⏱️ Focus session active'
                        : session.status == FocusSessionStatus.paused
                            ? '⏸️ Focus session paused'
                            : '○ Focus Session: Not active',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: session.isRunning
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active
                        ? '${_clock(session.remainingSeconds)} left'
                            '${session.blockedApps.isEmpty ? '' : ' · ${session.blockedApps.length} app${session.blockedApps.length == 1 ? '' : 's'} blocked'}'
                        : 'Start a session to block distractions',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!active) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${session.totalSeconds ~/ 60} min · '
                  '${session.blockedApps.isEmpty ? 'no apps selected' : '${session.blockedApps.length} app${session.blockedApps.length == 1 ? '' : 's'} to block'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => _showSetup(context),
                child: const Text('Customize'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () {
                  if (session.isRunning) {
                    notifier.pause();
                  } else {
                    notifier.start();
                    if (session.status != FocusSessionStatus.paused) {
                      _explainIfNotEnforced(context, ref);
                    }
                  }
                },
                child: Text(
                  session.isRunning
                      ? 'Pause'
                      : session.status == FocusSessionStatus.paused
                          ? 'Resume'
                          : 'Start Focus Session',
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: notifier.stop,
                  child: const Text('End session'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// A session with apps selected only blocks them if app blocking is on and
  /// permitted. Say so instead of letting the user believe it is enforced.
  void _explainIfNotEnforced(BuildContext context, WidgetRef ref) {
    final session = ref.read(focusSessionProvider);
    if (session.blockedApps.isEmpty) return;
    final blocking = ref.read(blockingProvider);
    final String? message;
    if (!blocking.enabled) {
      message = 'Timer started. Turn on App blocking in the Focus tab to '
          'actually block these apps.';
    } else if (!blocking.permissions.ready) {
      message = 'Timer started, but blocking is paused until you grant the '
          'permissions in the Focus tab.';
    } else {
      message = null;
    }
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSetup(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SessionSetupSheet(),
    );
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _SessionSetupSheet extends ConsumerWidget {
  const _SessionSetupSheet();

  static const _durations = [15, 25, 45, 60, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(focusSessionProvider);
    final notifier = ref.read(focusSessionProvider.notifier);
    final theme = Theme.of(context);
    final minutes = session.totalSeconds ~/ 60;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Focus Session',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Text('Duration', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final d in _durations)
                  ChoiceChip(
                    label: Text('$d min'),
                    selected: minutes == d,
                    onSelected: (_) => notifier.setDurationMinutes(d),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Apps to block', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (session.blockedApps.isEmpty)
              Text(
                'None selected — the session is just a timer.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in session.blockedApps)
                    Chip(
                      label: Text(a.appName),
                      onDeleted: () => notifier.setBlockedApps([
                        for (final b in session.blockedApps)
                          if (b.packageName != a.packageName) b,
                      ]),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.apps_rounded),
              label: const Text('Choose apps'),
              onPressed: () async {
                final picked = await showAppPicker(
                  context,
                  selected: session.blockedApps,
                  title: 'Apps to block during the session',
                );
                if (picked != null) notifier.setBlockedApps(picked);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Blocked apps are restricted only while App blocking is on '
              '(Focus tab). The session works even if Daily Focus Mode is off.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
