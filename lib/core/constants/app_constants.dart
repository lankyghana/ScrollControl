class AppConstants {
  AppConstants._();

  static const String appName = 'ScrollControl';

  // Focus session defaults (in minutes)
  static const int defaultFocusDuration = 25;
  static const int shortBreakDuration = 5;
  static const int longBreakDuration = 15;

  // Database
  static const String dbName = 'scroll_control.db';
  static const int dbVersion = 4;

  // SharedPreferences keys
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyDailyGoalMinutes = 'daily_goal_minutes';
  static const String keyNotificationsEnabled = 'notifications_enabled';

  // Daily screen time goal default (2 hours in minutes)
  static const int defaultDailyGoalMinutes = 120;

  // TODO: Replace with the real hosted URL before submitting to the Play
  // Store — a privacy-policy link is required for apps that request
  // PACKAGE_USAGE_STATS. Host `Privacy Policy.docx` (repo root) somewhere
  // public (e.g. GitHub Pages) and point this at it.
  static const String privacyPolicyUrl =
      'https://example.com/scrollcontrol/privacy-policy';
}
