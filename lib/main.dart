import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/background/background_monitoring_task.dart';
import 'core/errors/app_provider_observer.dart';
import 'core/errors/error_logger.dart';
import 'core/providers/cleanup_provider.dart';
import 'features/home/presentation/providers/focus_session_provider.dart';
import 'features/interrupt/presentation/providers/interrupt_providers.dart';
import 'features/usage/presentation/providers/permission_provider.dart';
import 'features/focus/presentation/widgets/limit_exceeded_overlay.dart';
import 'features/focus/presentation/providers/limit_exceeded_provider.dart';
import 'features/focus/presentation/providers/focus_providers.dart';
import 'features/focus/domain/entities/app_limit.dart';
import 'core/theme/theme_provider.dart';

// ── Global handles ────────────────────────────────────────────────────────────

/// Lets notification callbacks (outside the widget tree) reach the app state.
final _appKey = GlobalKey<_ScrollControlAppState>();

/// Allows showing snackbars without a BuildContext.
final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// ── Entry point ───────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch everything the framework and the platform surface that isn't
  // already wrapped in a local try/catch, so nothing fails silently in a
  // release build. To enable real crash reporting later (Sentry,
  // Crashlytics, ...), assign `ErrorLogger.reporter` here.
  FlutterError.onError = (details) {
    ErrorLogger.log(
      details.exception,
      details.stack ?? StackTrace.current,
      context: 'FlutterError',
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogger.log(error, stack, context: 'PlatformDispatcher');
    return true;
  };

  await NotificationService.instance.init();
  await NotificationService.instance.requestPermission();

  // Check whether the app was opened via "Start Focus" from terminated state.
  await NotificationService.instance.handleInitialNotification();

  // Wire the "Start Focus" action for foreground / background states.
  NotificationService.instance.onStartFocusTapped = () {
    _appKey.currentState?.handleStartFocus();
  };

  // Workmanager is unsupported on web.
  if (!kIsWeb) {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Schedule periodic background monitoring (every 60 minutes)
    await Workmanager().registerPeriodicTask(
      'focus_mode_background_check',
      'backgroundMonitoringTask',
      frequency: const Duration(minutes: 60),
      initialDelay: const Duration(minutes: 1),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  }

  runApp(
    ProviderScope(
      observers: const [AppProviderObserver()],
      child: ScrollControlApp(key: _appKey),
    ),
  );
}

/// Callback dispatcher for WorkManager background tasks.
/// Must be a top-level function to be called by the platform.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName == 'backgroundMonitoringTask') {
        await backgroundMonitoringTask();
        return true;
      }
      return false;
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'Workmanager.callbackDispatcher');
      return false;
    }
  });
}

// ── Root widget ───────────────────────────────────────────────────────────────

class ScrollControlApp extends ConsumerStatefulWidget {
  const ScrollControlApp({super.key});

  @override
  ConsumerState<ScrollControlApp> createState() => _ScrollControlAppState();
}

class _ScrollControlAppState extends ConsumerState<ScrollControlApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Trigger data cleanup (runs at most once per 24 hours)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cleanupServiceProvider).runCleanupIfNeeded();
    });

    // Handle terminated-state "Start Focus" tap after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (NotificationService.instance.consumePendingStartFocus()) {
        handleStartFocus();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Restart the monitor and re-verify permission when the user returns.
        ref.read(usageMonitorServiceProvider).start();
        ref.read(focusLimitMonitorServiceProvider).start();
        ref.read(usagePermissionProvider.notifier).recheck();
      case AppLifecycleState.paused:
        // Pause the monitor while the app is fully backgrounded (battery saving).
        ref.read(usageMonitorServiceProvider).stop();
        ref.read(focusLimitMonitorServiceProvider).stop();
      default:
        break;
    }
  }

  // ── Notification action ────────────────────────────────────────────────────

  /// Called from the notification callback (background) or initState (terminated).
  void handleStartFocus() {
    debugPrint('[App] handleStartFocus called');
    try {
      ref.read(focusSessionProvider.notifier).start();
      ref.read(routerProvider).go(AppRoutes.home);
      _scaffoldMessengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text(
              'Focus session started',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.card,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      debugPrint('[App] handleStartFocus completed successfully');
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'ScrollControlApp.handleStartFocus');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    ref.watch(monitorInitProvider);
    final themeIsDarkAsync = ref.watch(themePreferenceProvider);
    final limitExceeded = ref.watch(limitExceededProvider);

    // Get the first blocked app (if any)
    final blockedApp = limitExceeded.getFirstBlockedApp();
    final isBlocked = blockedApp != null && blockedApp.isNotEmpty;

    // Find app details from focus limits
    final focusLimitsAsync = ref.watch(focusLimitsProvider);

    final themeMode =
        themeIsDarkAsync.valueOrNull ?? true ? ThemeMode.dark : ThemeMode.light;

    return MaterialApp.router(
      title: 'ScrollControl',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      routerConfig: router,
      builder: (context, child) {
        // Overlay the limit exceeded screen on top if needed
        return focusLimitsAsync.when(
          data: (limits) {
            AppLimit? blockedAppLimit;
            if (isBlocked) {
              final matched =
                  limits.where((l) => l.appName == blockedApp).toList();
              if (matched.isNotEmpty) {
                blockedAppLimit = matched.first;
              }
            }

            return Stack(
              children: [
                child!,
                if (isBlocked && blockedAppLimit != null)
                  LimitExceededOverlay(
                    appName: blockedApp,
                    usedMinutes: 0,
                    limitMinutes: blockedAppLimit.dailyLimitMinutes,
                  ),
              ],
            );
          },
          loading: () => child!,
          error: (_, __) => child!,
        );
      },
    );
  }
}
