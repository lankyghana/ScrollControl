class AppLimit {
  const AppLimit({
    required this.packageName,
    required this.appName,
    required this.dailyLimitMinutes,
  });

  final String packageName;
  final String appName;
  final int dailyLimitMinutes;
}
