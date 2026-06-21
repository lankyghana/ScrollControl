/// Hardcoded thresholds for the Smart Interrupt System.
/// These will be moved to user-configurable settings in a later phase.
class InterruptConfig {
  InterruptConfig._();

  /// Continuous foreground usage above this triggers an interrupt (seconds).
  static const int thresholdSeconds = 5 * 60; // 5 minutes

  /// Minimum gap between two interrupts for the same app (seconds).
  static const int cooldownSeconds = 15 * 60; // 15 minutes

  /// How often the monitor checks usage stats (seconds).
  static const int checkIntervalSeconds = 60; // 1 minute
}
