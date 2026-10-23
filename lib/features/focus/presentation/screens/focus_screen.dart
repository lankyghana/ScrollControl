import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/app_limit.dart';
import '../../domain/entities/focus_settings.dart';
import '../providers/focus_providers.dart';
import '../../../usage/presentation/providers/permission_provider.dart';
import '../../../usage/data/datasources/usage_stats_datasource.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../blocking/presentation/widgets/app_picker.dart';
import '../../../blocking/presentation/widgets/blocking_card.dart';

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissionAsync = ref.watch(usagePermissionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Mode'),
        centerTitle: true,
        elevation: 0,
      ),
      body: permissionAsync.when(
        data: (hasPermission) {
          if (!hasPermission) {
            return _buildPermissionDeniedUI(context, ref);
          }
          return _buildFocusModeScreen(context, ref);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 56,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedUI(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 56,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Enable Usage Access',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Focus Mode requires usage access to monitor and limit app usage',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                openAndroidUsageSettings();
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusModeScreen(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(focusSettingsNotifierProvider);

    return settingsAsync.when(
      data: (settings) => _buildFocusContent(context, ref, settings),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load settings',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.refresh(focusSettingsNotifierProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusContent(
    BuildContext context,
    WidgetRef ref,
    FocusSettings settings,
  ) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            borderColor: AppColors.primary.withValues(alpha: 0.2),
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Focus Mode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: settings.isEnabled
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.dividerLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        settings.isEnabled ? '✓ Active' : '○ Disabled',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: settings.isEnabled
                              ? AppColors.success
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: settings.isEnabled,
                  onChanged: (value) {
                    ref
                        .read(focusSettingsNotifierProvider.notifier)
                        .toggleFocusMode(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const BlockingCard(),
          const SizedBox(height: 24),
          if (settings.isEnabled) ...[
            Text(
              'Daily Usage Limit',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              borderColor: AppColors.primary.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${settings.globalLimitMinutes ?? 120} min',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        '${((settings.globalLimitMinutes ?? 120) / 60).toStringAsFixed(1)}h',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Slider(
                    value: (settings.globalLimitMinutes ?? 120).toDouble(),
                    min: 5,
                    max: 1440,
                    divisions: 287,
                    label: '${settings.globalLimitMinutes ?? 120} min',
                    onChanged: (value) {
                      ref
                          .read(focusSettingsNotifierProvider.notifier)
                          .setGlobalLimit(value.toInt());
                    },
                  ),
                  Text(
                    'Adjust the daily limit for all apps',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Per-App Limits',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _buildAppLimitsList(context, ref, settings),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _addAppLimit(context, ref, settings),
              icon: const Icon(Icons.add),
              label: const Text('Add app limit'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppLimitsList(
    BuildContext context,
    WidgetRef ref,
    FocusSettings settings,
  ) {
    if (settings.perAppLimits.isEmpty) {
      return AppCard(
        borderColor: AppColors.dividerLight,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: Column(
          children: [
            const Icon(
              Icons.apps_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'No app limits yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Set limits from your usage stats',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: settings.perAppLimits.map((limit) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            borderColor: AppColors.dividerLight,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        limit.appName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${limit.dailyLimitMinutes} min/day',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: () {
                    _showEditLimitDialog(context, ref, limit, settings);
                  },
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _addAppLimit(
    BuildContext context,
    WidgetRef ref,
    FocusSettings settings,
  ) async {
    final picked = await showAppPicker(
      context,
      single: true,
      title: 'Limit which app?',
      excludePackages: {for (final l in settings.perAppLimits) l.packageName},
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    final app = picked.first;
    final newLimit = AppLimit(
      packageName: app.packageName,
      appName: app.appName,
      dailyLimitMinutes: 30,
    );
    // The dialog saves the whole list on "Save", so the new app only becomes a
    // limit if the user confirms.
    _showEditLimitDialog(
      context,
      ref,
      newLimit,
      settings.copyWith(perAppLimits: [...settings.perAppLimits, newLimit]),
    );
  }

  void _showEditLimitDialog(
    BuildContext context,
    WidgetRef ref,
    AppLimit limit,
    FocusSettings settings,
  ) {
    int limitMinutes = limit.dailyLimitMinutes;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Edit ${limit.appName}'),
              contentPadding: const EdgeInsets.all(24),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$limitMinutes min/day',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Slider(
                    value: limitMinutes.toDouble(),
                    min: 5,
                    max: 1440,
                    divisions: 287,
                    label: '$limitMinutes min',
                    onChanged: (value) {
                      setState(() {
                        limitMinutes = value.toInt();
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final updated = settings.perAppLimits
                        .map((l) =>
                            l.packageName == limit.packageName
                                ? AppLimit(
                                    packageName: limit.packageName,
                                    appName: limit.appName,
                                    dailyLimitMinutes: limitMinutes,
                                  )
                                : l)
                        .toList();

                    ref
                        .read(focusSettingsNotifierProvider.notifier)
                        .updatePerAppLimits(updated);

                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
