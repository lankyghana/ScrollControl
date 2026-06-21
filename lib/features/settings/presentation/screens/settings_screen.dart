import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../domain/interrupt_settings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(interruptSettingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            title: const Text('Settings'),
          ),
          settingsAsync.when(
            data: (settings) => _SettingsBody(settings: settings),
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SliverFillRemaining(
              child: Center(
                child: Text(
                  'Failed to load settings.',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.settings});

  final InterruptSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(interruptSettingsProvider.notifier);
    final themeAsync = ref.watch(themePreferenceProvider);
    final theme = Theme.of(context);
    final textPrimary = theme.colorScheme.onSurface;
    final textSecondary = theme.textTheme.bodyMedium?.color ?? textPrimary;
    final cardColor = theme.colorScheme.surface;
    final sectionColor = theme.colorScheme.secondary;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _SectionHeader(title: 'Appearance', color: sectionColor),
          const SizedBox(height: 8),
          _Card(
            color: cardColor,
            child: themeAsync.when(
              data: (isDarkTheme) => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Dark theme',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Switch between light and dark mode',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                  ),
                ),
                value: isDarkTheme,
                activeColor: AppColors.primary,
                onChanged: (value) {
                  ref
                      .read(themePreferenceProvider.notifier)
                      .setDarkTheme(value);
                },
              ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Text(
                'Unable to load theme preference',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Smart Interrupt', color: sectionColor),
          const SizedBox(height: 8),
          _Card(
            color: cardColor,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Enable Smart Interrupt',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Send a notification when you scroll for too long',
                style: TextStyle(color: textSecondary, fontSize: 13),
              ),
              value: settings.enabled,
              activeColor: AppColors.primary,
              onChanged: (v) => notifier.setEnabled(v),
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'Thresholds', color: sectionColor),
          const SizedBox(height: 8),
          _SliderCard(
            label: 'Interrupt after',
            value: settings.thresholdMinutes.toDouble(),
            min: 1,
            max: 15,
            enabled: settings.enabled,
            onChanged: (v) => notifier.setThreshold(v.round()),
            cardColor: cardColor,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 12),
          _SliderCard(
            label: 'Reminder cooldown',
            value: settings.cooldownMinutes.toDouble(),
            min: 5,
            max: 30,
            enabled: settings.enabled,
            onChanged: (v) => notifier.setCooldown(v.round()),
            cardColor: cardColor,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
          ),
          const SizedBox(height: 32),
          _SectionHeader(title: 'Privacy', color: sectionColor),
          const SizedBox(height: 8),
          _Card(
            color: cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your data stays on your device',
                  style: TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ScrollControl does not collect, transmit, or share any personal data. '
                  'Usage statistics are stored locally in an on-device SQLite database '
                  'and are never uploaded to external servers.',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Usage Access permission is required only to detect which app is in '
                  'the foreground so the interrupt reminder can fire at the right time. '
                  'This data is read locally and never leaves your device.',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'About', color: sectionColor),
          const SizedBox(height: 8),
          _Card(
            color: cardColor,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AboutRow(label: 'App', value: 'ScrollControl'),
                SizedBox(height: 8),
                _AboutRow(label: 'Version', value: '1.0.0'),
                SizedBox(height: 8),
                _AboutRow(
                  label: 'Purpose',
                  value: 'Reduce mindless scrolling through gentle interrupts',
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _SliderCard extends StatelessWidget {
  const _SliderCard({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.cardColor,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final Color cardColor;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.primary : textSecondary;

    return _Card(
      color: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: enabled ? textPrimary : textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${value.round()} min',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: Theme.of(context).dividerColor,
              overlayColor: color.withValues(alpha: 0.12),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              onChanged: enabled ? onChanged : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${min.round()} min',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                '${max.round()} min',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: theme.textTheme.bodyMedium?.color,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
