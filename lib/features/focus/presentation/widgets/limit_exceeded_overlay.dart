import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/focus_providers.dart';

/// Full-screen overlay shown when an app limit is exceeded.
/// Prevents accidental dismissal with prominent messaging and limited actions.
class LimitExceededOverlay extends ConsumerWidget {
  final String appName;
  final int usedMinutes;
  final int limitMinutes;

  const LimitExceededOverlay({
    super.key,
    required this.appName,
    required this.usedMinutes,
    required this.limitMinutes,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.background,
      child: Stack(
        children: [
          // ── Background gradient ──────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary.withValues(alpha: 0.1),
                  AppColors.background,
                ],
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Icon ──────────────────────────────────────────────────
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pause_circle_filled,
                      color: Colors.red,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Heading ───────────────────────────────────────────────
                  Text(
                    'Daily Limit Reached',
                    style: AppTextStyles.headlineMedium.copyWith(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // ── App name ──────────────────────────────────────────────
                  Text(
                    appName,
                    style: AppTextStyles.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // ── Usage stats ───────────────────────────────────────────
                  Text(
                    'You\'ve used $usedMinutes minutes of your ${limitMinutes}m daily limit',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // ── Break options ─────────────────────────────────────────
                  Text(
                    'Request a break to continue:',
                    style: AppTextStyles.titleMedium,
                  ),
                  const SizedBox(height: 16),

                  // 5 min break
                  _BreakButton(
                    label: '5-Minute Break',
                    minutes: 5,
                    onPressed: () {
                      ref
                          .read(focusSettingsNotifierProvider.notifier)
                          .grantBreak(appName, 5);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 12),

                  // 15 min break
                  _BreakButton(
                    label: '15-Minute Break',
                    minutes: 15,
                    onPressed: () {
                      ref
                          .read(focusSettingsNotifierProvider.notifier)
                          .grantBreak(appName, 15);
                      Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 32),

                  // ── Dismiss option ────────────────────────────────────────
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Dismiss',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Button for requesting a break.
class _BreakButton extends StatelessWidget {
  final String label;
  final int minutes;
  final VoidCallback onPressed;

  const _BreakButton({
    required this.label,
    required this.minutes,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelLarge.copyWith(
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
