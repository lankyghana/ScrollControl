import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/errors/error_logger.dart';
import '../../../blocking/domain/block_snapshot.dart';

/// What gets written to disk for a Focus Session, so it survives the process
/// being killed or the device rebooting.
class SavedFocusSession {
  const SavedFocusSession({
    required this.status,
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.apps,
    this.startedAtMs,
    this.endsAtMs,
  });

  /// `idle`, `running`, `paused` or `finished`.
  final String status;
  final int totalSeconds;
  final int remainingSeconds;
  final List<BlockedApp> apps;
  final int? startedAtMs;
  final int? endsAtMs;

  String toJson() => jsonEncode({
        'status': status,
        'total': totalSeconds,
        'remaining': remainingSeconds,
        'startedAtMs': startedAtMs,
        'endsAtMs': endsAtMs,
        'apps': [for (final a in apps) a.toJson()],
      });

  static SavedFocusSession? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SavedFocusSession(
        status: m['status'] as String,
        totalSeconds: (m['total'] as num).toInt(),
        remainingSeconds: (m['remaining'] as num).toInt(),
        startedAtMs: (m['startedAtMs'] as num?)?.toInt(),
        endsAtMs: (m['endsAtMs'] as num?)?.toInt(),
        apps: [
          for (final a in (m['apps'] as List<dynamic>? ?? const []))
            BlockedApp.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
      );
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'SavedFocusSession.tryParse');
      return null;
    }
  }
}

abstract interface class FocusSessionStore {
  Future<SavedFocusSession?> load();
  Future<void> save(SavedFocusSession session);
}

class PrefsFocusSessionStore implements FocusSessionStore {
  const PrefsFocusSessionStore();

  static const _key = 'focus_session_state_v1';

  @override
  Future<SavedFocusSession?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SavedFocusSession.tryParse(prefs.getString(_key));
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusSessionStore.load');
      return null;
    }
  }

  @override
  Future<void> save(SavedFocusSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, session.toJson());
    } catch (e, st) {
      ErrorLogger.log(e, st, context: 'FocusSessionStore.save');
    }
  }
}
