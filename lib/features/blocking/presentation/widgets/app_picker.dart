import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../usage/data/datasources/app_icon_cache.dart';
import '../../../usage/data/datasources/usage_stats_datasource.dart';
import '../../domain/block_snapshot.dart';
import '../../domain/blocker_platform.dart';
import '../providers/blocking_providers.dart';

/// Bottom sheet listing launchable apps. Returns the chosen apps, or null if
/// dismissed. With [single] the first tap returns immediately.
Future<List<BlockedApp>?> showAppPicker(
  BuildContext context, {
  List<BlockedApp> selected = const [],
  bool single = false,
  Set<String> excludePackages = const {},
  String title = 'Choose apps',
}) {
  return showModalBottomSheet<List<BlockedApp>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AppPickerSheet(
      selected: selected,
      single: single,
      excludePackages: excludePackages,
      title: title,
    ),
  );
}

class _AppPickerSheet extends ConsumerStatefulWidget {
  const _AppPickerSheet({
    required this.selected,
    required this.single,
    required this.excludePackages,
    required this.title,
  });

  final List<BlockedApp> selected;
  final bool single;
  final Set<String> excludePackages;
  final String title;

  @override
  ConsumerState<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends ConsumerState<_AppPickerSheet> {
  late final Map<String, BlockedApp> _chosen = {
    for (final a in widget.selected) a.packageName: a,
  };
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(launchableAppsProvider);
    final theme = Theme.of(context);
    final height = MediaQuery.of(context).size.height * 0.8;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!widget.single)
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _chosen.values.toList()),
                    child: Text('Done (${_chosen.length})'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search apps',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: appsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const _EmptyMessage('Could not load apps.'),
                data: (apps) {
                  final visible = apps
                      .where((a) =>
                          !widget.excludePackages.contains(a.packageName) &&
                          (_query.isEmpty ||
                              a.appName.toLowerCase().contains(_query)))
                      .toList();
                  if (visible.isEmpty) {
                    return const _EmptyMessage('No apps found.');
                  }
                  return ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final app = visible[i];
                      final picked = _chosen.containsKey(app.packageName);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _AppIcon(packageName: app.packageName),
                        title: Text(app.appName),
                        trailing: widget.single
                            ? null
                            : Checkbox(
                                value: picked,
                                activeColor: AppColors.primary,
                                onChanged: (_) => _toggle(app),
                              ),
                        onTap: () {
                          if (widget.single) {
                            Navigator.pop(context, [
                              BlockedApp(
                                packageName: app.packageName,
                                appName: app.appName,
                              ),
                            ]);
                          } else {
                            _toggle(app);
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(LaunchableApp app) {
    setState(() {
      final pkg = app.packageName;
      if (_chosen.remove(pkg) == null) {
        _chosen[pkg] = BlockedApp(packageName: pkg, appName: app.appName);
      }
    });
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary)),
      );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: FutureBuilder(
        future: AppIconCache.instance
            .getIcon(packageName, const AndroidUsageStatsDatasource()),
        builder: (_, snap) {
          final bytes = snap.data;
          if (bytes == null) {
            return const Icon(Icons.apps_rounded, color: AppColors.textSecondary);
          }
          return Image.memory(bytes, gaplessPlayback: true);
        },
      ),
    );
  }
}
