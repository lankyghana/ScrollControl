/// User-configurable settings for the Smart Interrupt system.
class InterruptSettings {
  const InterruptSettings({
    required this.enabled,
    required this.thresholdMinutes,
    required this.cooldownMinutes,
  });

  final bool enabled;

  /// Continuous app usage above this triggers an interrupt.
  final int thresholdMinutes;

  /// Minimum gap between two interrupts for the same app.
  final int cooldownMinutes;

  static const defaults = InterruptSettings(
    enabled: true,
    thresholdMinutes: 5,
    cooldownMinutes: 15,
  );

  InterruptSettings copyWith({
    bool? enabled,
    int? thresholdMinutes,
    int? cooldownMinutes,
  }) {
    return InterruptSettings(
      enabled: enabled ?? this.enabled,
      thresholdMinutes: thresholdMinutes ?? this.thresholdMinutes,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
    );
  }
}
