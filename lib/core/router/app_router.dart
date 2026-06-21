import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/focus/presentation/screens/focus_screen.dart';
import '../../features/stats/presentation/screens/stats_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/usage/presentation/providers/permission_provider.dart';
import '../../features/usage/presentation/screens/usage_permission_screen.dart';

// ── Route paths ───────────────────────────────────────────────────────────────

class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String focus = '/focus';
  static const String stats = '/stats';
  static const String settings = '/settings';
  static const String permission = '/permission';
}

// ── Bottom-nav shell ──────────────────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.timer_outlined),
      selectedIcon: Icon(Icons.timer),
      label: 'Focus',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: 'Stats',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: _destinations,
      ),
    );
  }
}

// ── Permission-aware refresh notifier ────────────────────────────────────────
//
// GoRouter's [refreshListenable] calls [notifyListeners] whenever permission
// or skip state changes, causing the router to re-evaluate [redirect].

class _PermissionRouteNotifier extends ChangeNotifier {
  _PermissionRouteNotifier(Ref ref) : _ref = ref {
    // Fire immediately so the initial state is captured.
    _permSub = ref.listen<AsyncValue<bool>>(
      usagePermissionProvider,
      (_, __) => notifyListeners(),
      fireImmediately: true,
    );
    _skipSub = ref.listen<bool>(
      permissionSkippedProvider,
      (_, __) => notifyListeners(),
      fireImmediately: true,
    );
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<bool>> _permSub;
  late final ProviderSubscription<bool> _skipSub;

  /// Called synchronously by GoRouter before every navigation attempt.
  String? redirect(String? location) {
    final permAsync = _ref.read(usagePermissionProvider);
    final isSkipped = _ref.read(permissionSkippedProvider);
    final onPermScreen = location == AppRoutes.permission;

    // Still querying the OS — don't redirect; let the current route stand.
    if (permAsync.isLoading) return null;

    final hasPermission = permAsync.valueOrNull ?? false;

    // No permission, not skipped, not already on the permission screen.
    if (!hasPermission && !isSkipped && !onPermScreen) {
      return AppRoutes.permission;
    }

    // Permission granted (or user skipped) but still on the permission screen.
    if ((hasPermission || isSkipped) && onPermScreen) {
      return AppRoutes.home;
    }

    return null; // No redirect needed.
  }

  @override
  void dispose() {
    _permSub.close();
    _skipSub.close();
    super.dispose();
  }
}

// ── Router provider ───────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _PermissionRouteNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (_, state) => notifier.redirect(state.matchedLocation),
    routes: [
      // ── Permission screen (no bottom nav) ────────────────────────────────
      GoRoute(
        path: AppRoutes.permission,
        name: 'permission',
        builder: (_, __) => const UsagePermissionScreen(),
      ),

      // ── Main app shell (bottom nav) ──────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.home,
              name: 'home',
              builder: (_, __) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.focus,
              name: 'focus',
              builder: (_, __) => const FocusScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.stats,
              name: 'stats',
              builder: (_, __) => const StatsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.settings,
              name: 'settings',
              builder: (_, __) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});
