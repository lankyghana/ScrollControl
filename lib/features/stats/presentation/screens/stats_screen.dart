import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/extensions/duration_ext.dart';
import '../../../focus/domain/entities/daily_focus_summary.dart';
import '../../../focus/domain/entities/focus_session.dart';
import '../../../focus/presentation/providers/focus_providers.dart';
import '../../../usage/domain/entities/daily_usage_summary.dart';
import '../../../usage/presentation/providers/usage_providers.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionsAsync = ref.watch(dailyFocusSessionsProvider(today));
    final usageAsync = ref.watch(dailyUsageProvider(today));
    final weeklyUsageAsync = ref.watch(weeklyUsageProvider);
    final weeklyFocusAsync = ref.watch(weeklyFocusProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            title: Text('Stats'),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Today ───────────────────────────────────────────────────
                const _SectionHeader(title: 'Screen Time Today'),
                const SizedBox(height: 8),
                usageAsync.when(
                  data: (u) => _UsageSummaryCard(usages: u),
                  loading: () => const _LoadingCard(),
                  error: (_, __) => const _ErrorCard(),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(title: 'Focus Sessions Today'),
                const SizedBox(height: 8),
                sessionsAsync.when(
                  data: (s) => s.isEmpty
                      ? const _EmptyCard(label: 'No focus sessions yet today.')
                      : _SessionList(sessions: s),
                  loading: () => const _LoadingCard(),
                  error: (_, __) => const _ErrorCard(),
                ),

                // ── Last 7 Days ─────────────────────────────────────────────
                const SizedBox(height: 32),
                const _SectionHeader(title: 'Last 7 Days — Screen Time'),
                const SizedBox(height: 8),
                weeklyUsageAsync.when(
                  data: (summaries) => _WeeklyUsageChart(summaries: summaries),
                  loading: () => const _LoadingCard(),
                  error: (_, __) => const _ErrorCard(),
                ),
                const SizedBox(height: 24),
                const _SectionHeader(title: 'Last 7 Days — Focus Sessions'),
                const SizedBox(height: 8),
                weeklyFocusAsync.when(
                  data: (summaries) => _WeeklyFocusChart(summaries: summaries),
                  loading: () => const _LoadingCard(),
                  error: (_, __) => const _ErrorCard(),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Weekly screen-time chart ──────────────────────────────────────────────────

class _WeeklyUsageChart extends StatelessWidget {
  const _WeeklyUsageChart({required this.summaries});
  final List<DailyUsageSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final days = _last7Days();
    final dataMap = {
      for (final s in summaries) _dateKey(s.date): s.totalSeconds,
    };
    final values =
        days.map((d) => (dataMap[_dateKey(d)] ?? 0) / 3600.0).toList();
    final maxY = values.isEmpty
        ? 2.0
        : (values.reduce((a, b) => a > b ? a : b) * 1.25)
            .clamp(1.0, double.infinity);

    if (values.every((v) => v == 0)) {
      return const _EmptyCard(
          label: 'No data yet — grant Usage Access to see trends.');
    }

    return _chartCard(
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barGroups: List.generate(7, (i) {
            final isToday = i == 6;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: isToday
                      ? AppColors.primary
                      : AppColors.primary.withValues(alpha: 0.35),
                  width: 22,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) {
                  final day = days[value.toInt()];
                  final label = _dayLabel(day, value.toInt() == 6);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: value.toInt() == 6
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: value.toInt() == 6
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceVariant,
              getTooltipItem: (group, _, rod, __) {
                final dur =
                    Duration(seconds: dataMap[_dateKey(days[group.x])] ?? 0);
                return BarTooltipItem(
                  dur.toHoursMinutes(),
                  const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Weekly focus chart ─────────────────────────────────────────────────────────

class _WeeklyFocusChart extends StatelessWidget {
  const _WeeklyFocusChart({required this.summaries});
  final List<DailyFocusSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final days = _last7Days();
    final dataMap = {
      for (final s in summaries) _dateKey(s.date): s.sessionCount,
    };
    final values =
        days.map((d) => (dataMap[_dateKey(d)] ?? 0).toDouble()).toList();
    final maxY = values.isEmpty
        ? 3.0
        : (values.reduce((a, b) => a > b ? a : b) + 1.5)
            .clamp(3.0, double.infinity);

    if (values.every((v) => v == 0)) {
      return const _EmptyCard(label: 'No focus sessions in the last 7 days.');
    }

    return _chartCard(
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barGroups: List.generate(7, (i) {
            final isToday = i == 6;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: isToday
                      ? AppColors.secondary
                      : AppColors.secondary.withValues(alpha: 0.35),
                  width: 22,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) {
                  final day = days[value.toInt()];
                  final isToday = value.toInt() == 6;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _dayLabel(day, isToday),
                      style: TextStyle(
                        color: isToday
                            ? AppColors.secondary
                            : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            isToday ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.surfaceVariant,
              getTooltipItem: (group, _, rod, __) {
                final count = dataMap[_dateKey(days[group.x])] ?? 0;
                return BarTooltipItem(
                  '$count session${count == 1 ? '' : 's'}',
                  const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Today — screen-time summary ───────────────────────────────────────────────

class _UsageSummaryCard extends StatelessWidget {
  const _UsageSummaryCard({required this.usages});
  final List<dynamic> usages;

  @override
  Widget build(BuildContext context) {
    if (usages.isEmpty) {
      return const _EmptyCard(
          label: 'No screen-time data — grant Usage Access to see stats.');
    }
    final totalSecs = usages.fold<int>(0, (s, u) => s + (u.usageTime as int));
    final totalDur = Duration(seconds: totalSecs);

    return _infoCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            totalDur.toHoursMinutes(),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total across ${usages.length} apps',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...usages.take(5).map((u) => _AppRow(u: u)),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.u});
  final dynamic u;

  @override
  Widget build(BuildContext context) {
    final dur = Duration(seconds: u.usageTime as int);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              u.appName as String,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            dur.toHoursMinutes(),
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── Today — focus session list ────────────────────────────────────────────────

class _SessionList extends StatelessWidget {
  const _SessionList({required this.sessions});
  final List<FocusSession> sessions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: sessions
          .map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SessionCard(session: s),
              ))
          .toList(),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session});
  final FocusSession session;

  @override
  Widget build(BuildContext context) {
    final dur = Duration(seconds: session.duration);
    final fmt = DateFormat('h:mm a');
    return _infoCard(
      context,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.timer_outlined,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dur.toHoursMinutes(),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  '${fmt.format(session.startTime)} – ${fmt.format(session.endTime)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

List<DateTime> _last7Days() {
  final today = DateTime.now();
  return List.generate(
    7,
    (i) => DateTime(today.year, today.month, today.day - (6 - i)),
  );
}

String _dateKey(DateTime dt) => '${dt.year.toString().padLeft(4, '0')}-'
    '${dt.month.toString().padLeft(2, '0')}-'
    '${dt.day.toString().padLeft(2, '0')}';

String _dayLabel(DateTime day, bool isToday) =>
    isToday ? 'Today' : DateFormat('E').format(day).substring(0, 2);

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
    );
  }
}

// ── Card wrappers ─────────────────────────────────────────────────────────────

Widget _infoCard(BuildContext context, {required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

Widget _chartCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
    ),
    child: SizedBox(height: 160, child: child),
  );
}

// ── Empty / loading / error ───────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        height: 64,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Failed to load data.',
            style: TextStyle(color: AppColors.error)),
      );
}
