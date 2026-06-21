import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/datasources/usage_stats_datasource.dart';
import '../providers/permission_provider.dart';

class UsagePermissionScreen extends ConsumerStatefulWidget {
  const UsagePermissionScreen({super.key});

  @override
  ConsumerState<UsagePermissionScreen> createState() =>
      _UsagePermissionScreenState();
}

class _UsagePermissionScreenState extends ConsumerState<UsagePermissionScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    // Watch for app lifecycle changes so we can re-check permission
    // the moment the user returns from Android Settings.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-query the OS — GoRouter will automatically redirect to HomeScreen
      // if permission is now granted.
      ref.read(usagePermissionProvider.notifier).recheck();
    }
  }

  Future<void> _onGrantTapped() async {
    await openAndroidUsageSettings();
    // The lifecycle observer will trigger recheck() when the user returns.
  }

  void _onSkipTapped() {
    ref.read(permissionSkippedProvider.notifier).state = true;
    // GoRouter redirect picks up the skip flag and navigates to HomeScreen.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Icon ──────────────────────────────────────────────────────
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.primary,
                  size: 48,
                ),
              ),
              const SizedBox(height: 32),

              // ── Title ─────────────────────────────────────────────────────
              Text(
                'Enable Usage Access',
                style: AppTextStyles.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // ── Description ───────────────────────────────────────────────
              Text(
                'ScrollControl needs access to your app usage data to help you '
                'track screen time and reduce excessive scrolling.\n\n'
                'Your data stays on your device and is never shared.',
                style: AppTextStyles.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // ── How-to hint ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'After tapping "Grant Permission", find ScrollControl '
                        'in the list and toggle it on.',
                        style: AppTextStyles.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // ── Primary CTA ───────────────────────────────────────────────
              FilledButton.icon(
                onPressed: _onGrantTapped,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Grant Permission'),
              ),
              const SizedBox(height: 12),

              // ── Skip option ───────────────────────────────────────────────
              TextButton(
                onPressed: _onSkipTapped,
                child: Text(
                  'Continue without permission',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
