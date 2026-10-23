import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../focus/domain/entities/focus_settings.dart';
import '../../../focus/presentation/providers/focus_providers.dart';
import '../../../usage/presentation/providers/permission_provider.dart';
import '../providers/focus_session_provider.dart';
import '../providers/home_provider.dart';
import '../widgets/session_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(focusSessionProvider);
    final usageAsync = ref.watch(usageProvider);
    final stats = usageAsync.valueOrNull ?? TodayStats.empty;
    final focusSettingsAsync = ref.watch(focusSettingsProvider);
    final selectedRange = ref.watch(appUsageRangeProvider);
    final appUsageAsync = ref.watch(appUsageProvider(selectedRange));

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Minimal app bar
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: AppColors.background,
              elevation: 0,
              title: Text(
                'ScrollControl',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.go(AppRoutes.settings),
                    tooltip: 'Settings',
                  ),
                ),
              ],
            ),
            const SliverToBoxAdapter(child: _PermissionBanner()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting
                    GreetingHeader(sessionsToday: stats.focusSessionsDone),
                    const SizedBox(height: 24),

                    // Focus Status Card
                    FocusStatusCard(
                      focusSettingsAsync: focusSettingsAsync,
                      screenTimeMinutes: stats.screenTimeMinutes,
                      session: session,
                      ref: ref,
                    ),
                    const SizedBox(height: 20),

                    // Two stats in a row
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            icon: Icons.schedule_rounded,
                            title: 'Total Time',
                            value: usageAsync.isLoading
                                ? '-'
                                : _formatMinutes(stats.screenTimeMinutes),
                            subtitle: 'Today',
                            accentColor: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            icon: Icons.task_alt_rounded,
                            title: 'Sessions',
                            value: usageAsync.isLoading ? '-' : '${stats.focusSessionsDone}',
                            subtitle: 'Completed',
                            accentColor: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Insight
                    InsightText(
                      isLoading: usageAsync.isLoading,
                      screenTimeMinutes: stats.screenTimeMinutes,
                      sessionsToday: stats.focusSessionsDone,
                    ),
                    const SizedBox(height: 28),

                    // Per-app usage
                    PerAppUsageSection(
                      selectedRange: selectedRange,
                      isLoading: appUsageAsync.isLoading,
                      items: appUsageAsync.valueOrNull ?? const [],
                      focusSettings: focusSettingsAsync.valueOrNull,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key, required this.sessionsToday});

  final int sessionsToday;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning 👋';
    if (hour < 17) return 'Good Afternoon 👋';
    return 'Good Evening 👋';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _greeting,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ready to stay focused today?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (sessionsToday > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '✨ $sessionsToday focus session${sessionsToday == 1 ? '' : 's'} completed',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class FocusStatusCard extends StatelessWidget {
  const FocusStatusCard({
    super.key,
    required this.focusSettingsAsync,
    required this.screenTimeMinutes,
    required this.session,
    required this.ref,
  });

  final AsyncValue<FocusSettings> focusSettingsAsync;
  final int screenTimeMinutes;
  final FocusSessionState session;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return focusSettingsAsync.when(
      loading: () => const AppCard(
        child: SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => AppCard(
        child: Text(
          'Focus Mode unavailable',
          style: theme.textTheme.bodyMedium,
        ),
      ),
      data: (settings) {
        return AppCard(
          borderColor: AppColors.primary.withValues(alpha: 0.2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Focus Mode toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Focus Mode: ',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        settings.isEnabled ? 'ON' : 'OFF',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: settings.isEnabled
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                ],
              ),
              const SizedBox(height: 8),
              Text(
                settings.isEnabled
                    ? 'Daily limits are active'
                    : 'Enable to set app limits',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              const SessionSection(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.focus),
                  child: const Text('Edit Limits'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class InsightText extends StatelessWidget {
  const InsightText({
    super.key,
    required this.isLoading,
    required this.screenTimeMinutes,
    required this.sessionsToday,
  });

  final bool isLoading;
  final int screenTimeMinutes;
  final int sessionsToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final insight = isLoading
        ? 'Loading your summary...'
        : screenTimeMinutes == 0
            ? 'No usage yet. Perfect start to the day!'
            : sessionsToday > 0 && screenTimeMinutes < 60
                ? 'Great balance today. Keep it up! 💪'
                : screenTimeMinutes < 120
                    ? 'Good progress. Stay focused!'
                    : 'Time for a focus session? 🎯';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.1),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.lightbulb_outline_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              insight,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PerAppUsageSection extends StatelessWidget {
  const PerAppUsageSection({
    super.key,
    required this.selectedRange,
    required this.isLoading,
    required this.items,
    required this.focusSettings,
  });

  final AppUsageRange selectedRange;
  final bool isLoading;
  final List<AppUsageSummary> items;
  final FocusSettings? focusSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'App Usage Today',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            _RangeDropdown(selectedRange: selectedRange),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading)
          const AppCard(
            child: SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (items.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No usage data yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                AppUsageTile(
                  item: items[i],
                  focusSettings: focusSettings,
                  showProgress: selectedRange == AppUsageRange.today,
                ),
                if (i != items.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
      ],
    );
  }
}

class _RangeDropdown extends ConsumerWidget {
  const _RangeDropdown({required this.selectedRange});

  final AppUsageRange selectedRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.dividerLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppUsageRange>(
          value: selectedRange,
          borderRadius: BorderRadius.circular(14),
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          items: const [
            DropdownMenuItem(value: AppUsageRange.today, child: Text('Today')),
            DropdownMenuItem(value: AppUsageRange.last7Days, child: Text('7 Days')),
          ],
          onChanged: (value) {
            if (value == null) return;
            ref.read(appUsageRangeProvider.notifier).state = value;
          },
        ),
      ),
    );
  }
}

class AppUsageTile extends StatelessWidget {
  const AppUsageTile({
    super.key,
    required this.item,
    required this.focusSettings,
    required this.showProgress,
  });

  final AppUsageSummary item;
  final FocusSettings? focusSettings;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentForApp(item.packageName);
    final limitMinutes = _limitForApp(focusSettings, item.packageName);
    final usageLabel = _formatMinutes(item.usageMinutes);
    final progress = limitMinutes == null
        ? null
        : (item.usageMinutes / limitMinutes).clamp(0.0, 1.0);

    return AppCard(
      borderColor: accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_iconForApp(item.appName), color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.appName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      limitMinutes != null
                          ? '$usageLabel / ${_formatMinutes(limitMinutes)}'
                          : usageLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                usageLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (showProgress && progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progress,
                backgroundColor: AppColors.dividerLight,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionBanner extends ConsumerWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSkipped = ref.watch(permissionSkippedProvider);
    if (!isSkipped) return const SizedBox.shrink();

    final hasPermission =
        ref.watch(usagePermissionProvider).valueOrNull ?? true;
    if (hasPermission) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.go(AppRoutes.permission),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Enable usage access for full features',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              'Enable',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatMinutes(int minutes) {
  if (minutes == 0) return '0m';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours == 0) return '${mins}m';
  return '${hours}h ${mins}m';
}

int? _limitForApp(FocusSettings? settings, String packageName) {
  if (settings == null) return null;
  for (final limit in settings.perAppLimits) {
    if (limit.packageName == packageName) {
      return limit.dailyLimitMinutes;
    }
  }
  return settings.globalLimitMinutes;
}

Color _accentForApp(String packageName) {
  const palette = [
    AppColors.primary,
    Color(0xFF8B7CEE),
    Color(0xFF1498DA),
    Color(0xFF00D4AA),
    Color(0xFFFF6B6B),
  ];
  final index = packageName.hashCode.abs() % palette.length;
  return palette[index];
}

IconData _iconForApp(String appName) {
  final normalized = appName.toLowerCase();
  if (normalized.contains('instagram')) return Icons.camera_alt_rounded;
  if (normalized.contains('tiktok')) return Icons.music_note_rounded;
  if (normalized.contains('youtube')) return Icons.play_circle_fill_rounded;
  if (normalized.contains('facebook')) return Icons.facebook_rounded;
  if (normalized.contains('chrome')) return Icons.public_rounded;
  if (normalized.contains('whatsapp')) return Icons.chat_rounded;
  return Icons.apps_rounded;
}
