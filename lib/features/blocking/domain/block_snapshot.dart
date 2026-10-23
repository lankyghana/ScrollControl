/// Why a package is currently restricted.
enum BlockReason { dailyApp, dailyTotal, session }

/// An app picked by the user (for a Focus Session).
class BlockedApp {
  const BlockedApp({required this.packageName, required this.appName});

  final String packageName;
  final String appName;

  Map<String, dynamic> toJson() => {'pkg': packageName, 'name': appName};

  factory BlockedApp.fromJson(Map<String, dynamic> json) => BlockedApp(
        packageName: json['pkg'] as String,
        appName: (json['name'] as String?) ?? json['pkg'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is BlockedApp &&
      other.packageName == packageName &&
      other.appName == appName;

  @override
  int get hashCode => Object.hash(packageName, appName);
}

class AppLimitRule {
  const AppLimitRule({
    required this.packageName,
    required this.appName,
    required this.limitSeconds,
  });

  final String packageName;
  final String appName;
  final int limitSeconds;

  Map<String, dynamic> toJson() =>
      {'pkg': packageName, 'name': appName, 'limitSec': limitSeconds};

  factory AppLimitRule.fromJson(Map<String, dynamic> json) => AppLimitRule(
        packageName: json['pkg'] as String,
        appName: (json['name'] as String?) ?? json['pkg'] as String,
        limitSeconds: (json['limitSec'] as num).toInt(),
      );
}

/// A running Focus Session as the blocker sees it. A paused or finished
/// session is simply absent from the snapshot.
class SessionRule {
  const SessionRule({required this.endsAtMs, required this.apps});

  final int endsAtMs;
  final List<BlockedApp> apps;

  Map<String, dynamic> toJson() => {
        'endsAtMs': endsAtMs,
        'apps': [for (final a in apps) a.toJson()],
      };

  factory SessionRule.fromJson(Map<String, dynamic> json) => SessionRule(
        endsAtMs: (json['endsAtMs'] as num).toInt(),
        apps: [
          for (final a in (json['apps'] as List<dynamic>? ?? const []))
            BlockedApp.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
      );
}

/// The outcome of evaluating one package against a [BlockSnapshot].
class BlockDecision {
  const BlockDecision({
    required this.reason,
    required this.packageName,
    required this.appName,
    required this.expiresAtMs,
    this.usedSeconds,
    this.limitSeconds,
  });

  final BlockReason reason;
  final String packageName;
  final String appName;

  /// Epoch ms at which this restriction stops applying (end of the session,
  /// the next local midnight for daily limits, or the end of a break).
  final int expiresAtMs;

  final int? usedSeconds;
  final int? limitSeconds;
}

/// Everything the native blocker needs, in one serialisable object.
///
/// This is the **contract** with `BlockPolicy.kt`: the native service
/// evaluates the same rules while Flutter is not running, so any change to
/// [decide] must be mirrored there.
class BlockSnapshot {
  const BlockSnapshot({
    this.dailyEnabled = false,
    this.globalLimitSeconds,
    this.appLimits = const [],
    this.breaksUntilMs = const {},
    this.session,
  });

  static const empty = BlockSnapshot();

  final bool dailyEnabled;

  /// Global daily limit; applies to the sum of all apps' usage.
  final int? globalLimitSeconds;
  final List<AppLimitRule> appLimits;

  /// package → epoch ms until which its per-app daily limit is waived.
  final Map<String, int> breaksUntilMs;
  final SessionRule? session;

  bool get hasDailyRules =>
      dailyEnabled &&
      ((globalLimitSeconds != null && globalLimitSeconds! > 0) ||
          appLimits.any((l) => l.limitSeconds > 0));

  /// True when anything could ever block, i.e. the service is worth running.
  bool get hasRules => hasDailyRules || session != null;

  /// Epoch ms of the next local midnight after [nowMs]. Daily limits reset on
  /// the user's calendar day, not on a rolling 24 hours.
  static int nextMidnightMs(int nowMs) {
    final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
    return DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch;
  }

  /// Decides whether [packageName] is blocked right now.
  ///
  /// [usedSecondsByPackage] is *today's* usage (since local midnight), so a
  /// new day starts with empty usage and therefore no daily block.
  ///
  /// When several restrictions apply, the stricter one wins: the one that
  /// lasts longest. A break only waives the per-app daily limit, never a
  /// Focus Session or the global limit.
  BlockDecision? decide({
    required String packageName,
    required Map<String, int> usedSecondsByPackage,
    required int nowMs,
  }) {
    final candidates = <BlockDecision>[];

    final s = session;
    if (s != null && s.endsAtMs > nowMs) {
      for (final app in s.apps) {
        if (app.packageName == packageName) {
          candidates.add(BlockDecision(
            reason: BlockReason.session,
            packageName: packageName,
            appName: app.appName,
            expiresAtMs: s.endsAtMs,
          ));
          break;
        }
      }
    }

    if (dailyEnabled) {
      final midnight = nextMidnightMs(nowMs);

      for (final limit in appLimits) {
        if (limit.packageName != packageName || limit.limitSeconds <= 0) {
          continue;
        }
        final used = usedSecondsByPackage[packageName] ?? 0;
        if (used < limit.limitSeconds) break;
        final breakUntil = breaksUntilMs[packageName];
        if (breakUntil != null && breakUntil > nowMs) break;
        candidates.add(BlockDecision(
          reason: BlockReason.dailyApp,
          packageName: packageName,
          appName: limit.appName,
          expiresAtMs: midnight,
          usedSeconds: used,
          limitSeconds: limit.limitSeconds,
        ));
        break; // first limit for a package wins, as in LimitEvaluator
      }

      final global = globalLimitSeconds;
      if (global != null && global > 0) {
        final total = usedSecondsByPackage.values.fold<int>(0, (a, b) => a + b);
        if (total >= global) {
          candidates.add(BlockDecision(
            reason: BlockReason.dailyTotal,
            packageName: packageName,
            appName: packageName,
            expiresAtMs: midnight,
            usedSeconds: total,
            limitSeconds: global,
          ));
        }
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final byExpiry = b.expiresAtMs.compareTo(a.expiresAtMs);
      if (byExpiry != 0) return byExpiry;
      return b.reason.index.compareTo(a.reason.index); // on a tie: session first
    });
    return candidates.first;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'dailyEnabled': dailyEnabled,
        'globalLimitSec': globalLimitSeconds,
        'appLimits': [for (final l in appLimits) l.toJson()],
        'breaks': [
          for (final e in breaksUntilMs.entries)
            {'pkg': e.key, 'untilMs': e.value},
        ],
        'session': session?.toJson(),
      };

  factory BlockSnapshot.fromJson(Map<String, dynamic> json) {
    final session = json['session'];
    return BlockSnapshot(
      dailyEnabled: json['dailyEnabled'] as bool? ?? false,
      globalLimitSeconds: (json['globalLimitSec'] as num?)?.toInt(),
      appLimits: [
        for (final l in (json['appLimits'] as List<dynamic>? ?? const []))
          AppLimitRule.fromJson(Map<String, dynamic>.from(l as Map)),
      ],
      breaksUntilMs: {
        for (final b in (json['breaks'] as List<dynamic>? ?? const []))
          (b as Map)['pkg'] as String: (b['untilMs'] as num).toInt(),
      },
      session: session == null
          ? null
          : SessionRule.fromJson(Map<String, dynamic>.from(session as Map)),
    );
  }
}
