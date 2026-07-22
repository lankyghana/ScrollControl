import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Callback invoked when the user taps the "Start Focus" notification action.
typedef OnStartFocusTapped = void Function();

/// The subset of [NotificationService] that the monitor services depend on.
/// Extracted so tests can supply a fake — [NotificationService] itself has a
/// private constructor (it's a singleton), so it can't be subclassed or
/// mocked directly from outside this file.
abstract interface class NotificationSender {
  Future<void> showInterruptNotification({
    required String appName,
    required int minutes,
  });

  Future<void> showLimitExceededNotification({
    required String appName,
    required int usedMinutes,
    required int limitMinutes,
  });
}

class NotificationService implements NotificationSender {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  // ── Constants ────────────────────────────────────────────────────────────────

  static const _channelId = 'scroll_interrupt';
  static const _channelName = 'Scroll Interrupts';

  /// Distinct IDs so an interrupt notification and a limit-exceeded
  /// notification never overwrite each other if both are shown close
  /// together.
  static const _interruptNotificationId = 1001;
  static const _limitExceededNotificationId = 1002;

  /// Action IDs must match between showInterruptNotification and _onResponse.
  static const continueActionId = 'continue_action';
  static const startFocusActionId = 'start_focus_action';

  // ── State ────────────────────────────────────────────────────────────────────

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Fired when the user taps the "Start Focus" action (foreground/background).
  OnStartFocusTapped? onStartFocusTapped;

  /// Set to true when the app is launched from a terminated state via the
  /// "Start Focus" action. Consumed once by [consumePendingStartFocus].
  bool _pendingStartFocus = false;

  // ── Initialisation ───────────────────────────────────────────────────────────

  /// Initialises the plugin and creates the Android notification channel.
  /// Must be called once before showing any notification.
  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );

    // Create the persistent channel (no-op if it already exists).
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Alerts when you have been scrolling for too long.',
      importance: Importance.high,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Checks whether the app was launched by tapping a notification action
  /// while it was terminated. Call this in [main] after [init].
  ///
  /// If the "Start Focus" action was the trigger, [consumePendingStartFocus]
  /// will return true once, allowing the root widget to act on it.
  Future<void> handleInitialNotification() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true &&
        details?.notificationResponse?.actionId == startFocusActionId) {
      _pendingStartFocus = true;
    }
  }

  /// Returns true (and clears the flag) if the app was opened via the
  /// "Start Focus" action from a terminated state.
  bool consumePendingStartFocus() {
    if (!_pendingStartFocus) return false;
    _pendingStartFocus = false;
    return true;
  }

  // ── Requests ─────────────────────────────────────────────────────────────────

  /// Requests the POST_NOTIFICATIONS runtime permission (Android 13+).
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  // ── Notifications ─────────────────────────────────────────────────────────────

  /// Shows the Smart Interrupt notification with Continue and Start Focus actions.
  @override
  Future<void> showInterruptNotification({
    required String appName,
    required int minutes,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts when you have been scrolling for too long.',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      actions: [
        AndroidNotificationAction(
          continueActionId,
          'Continue',
          cancelNotification: true,
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          startFocusActionId,
          'Start Focus',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    await _plugin.show(
      _interruptNotificationId,
      'Take a break',
      "You've been on $appName for $minutes minutes",
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Shows a Focus Mode limit-exceeded notification.
  @override
  Future<void> showLimitExceededNotification({
    required String appName,
    required int usedMinutes,
    required int limitMinutes,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Focus Mode limit exceeded.',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      actions: [
        AndroidNotificationAction(
          continueActionId,
          'Dismiss',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    await _plugin.show(
      _limitExceededNotificationId,
      'Limit reached',
      "You've used $usedMinutes minutes of your ${limitMinutes}m daily limit for $appName",
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Dismisses any active interrupt and limit-exceeded notifications.
  Future<void> cancel() async {
    await _plugin.cancel(_interruptNotificationId);
    await _plugin.cancel(_limitExceededNotificationId);
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  /// Handles notification action taps from foreground and background states.
  /// Terminated-state taps are handled separately via [handleInitialNotification].
  void _onResponse(NotificationResponse response) {
    debugPrint('[Notification] Action tapped: actionId=${response.actionId}');
    switch (response.actionId) {
      case startFocusActionId:
        debugPrint('[Notification] Start Focus action triggered');
        onStartFocusTapped?.call();
        break;
      case continueActionId:
        debugPrint('[Notification] Continue action triggered');
        // User chose to keep scrolling — nothing to do.
        break;
      default:
        // Tapped the notification body (no action) → treat as Start Focus.
        if (response.actionId == null) {
          debugPrint('[Notification] Notification body tapped (no action)');
          onStartFocusTapped?.call();
        }
    }
  }
}
