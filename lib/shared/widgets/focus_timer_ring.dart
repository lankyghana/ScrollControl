import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../core/theme/app_colors.dart';

class FocusTimerRing extends StatelessWidget {
  const FocusTimerRing({
    super.key,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isRunning,
  });

  final int remainingSeconds;
  final int totalSeconds;
  final bool isRunning;

  String get _timeLabel {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get _progress =>
      totalSeconds == 0 ? 0 : remainingSeconds / totalSeconds;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow background
        Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 20,
              ),
            ],
          ),
        ),
        // Circular progress ring
        CircularPercentIndicator(
          radius: 130.0,
          lineWidth: 14.0,
          percent: _progress,
          animation: true,
          animateFromLastPercent: true,
          animationDuration: 800,
          circularStrokeCap: CircularStrokeCap.round,
          backgroundColor: AppColors.timerRingBg,
          progressColor: AppColors.primary,
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _timeLabel,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'min left',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
