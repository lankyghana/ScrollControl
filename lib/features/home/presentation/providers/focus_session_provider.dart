import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../blocking/domain/block_snapshot.dart';
import '../../../focus/domain/entities/focus_session.dart';
import '../../../focus/presentation/providers/focus_providers.dart';
import 'focus_session_store.dart';

enum FocusSessionStatus { idle, running, paused, finished }

class FocusSessionState {
  const FocusSessionState({
    required this.status,
    required this.remainingSeconds,
    required this.totalSeconds,
    this.blockedApps = const [],
    this.endsAt,
  });

  final FocusSessionStatus status;
  final int remainingSeconds;
  final int totalSeconds;

  /// Apps restricted while the session runs. Chosen before starting.
  final List<BlockedApp> blockedApps;

  /// Wall-clock moment a running session ends; null unless running.
  final DateTime? endsAt;

  bool get isRunning => status == FocusSessionStatus.running;
  bool get isIdle => status == FocusSessionStatus.idle;
  double get progress =>
      totalSeconds == 0 ? 0 : remainingSeconds / totalSeconds;

  /// Changes only when what the blocker must enforce changes (not every
  /// second of the countdown).
  String get blockSignature => isRunning && endsAt != null
      ? '${endsAt!.millisecondsSinceEpoch}|'
          '${blockedApps.map((a) => a.packageName).join(',')}'
      : 'none';

  FocusSessionState copyWith({
    FocusSessionStatus? status,
    int? remainingSeconds,
    int? totalSeconds,
    List<BlockedApp>? blockedApps,
    DateTime? endsAt,
    bool clearEndsAt = false,
  }) {
    return FocusSessionState(
      status: status ?? this.status,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      blockedApps: blockedApps ?? this.blockedApps,
      endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
    );
  }
}

class FocusSessionNotifier extends Notifier<FocusSessionState> {
  Timer? _timer;
  DateTime? _sessionStartTime;

  /// Wall-clock moment the running countdown reaches zero. The remaining time
  /// is derived from this on every tick, so it stays correct when Android
  /// suspends the app's timers in the background.
  DateTime? _endsAt;

  bool _disposed = false;

  /// Injectable clock for tests.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  @override
  FocusSessionState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });

    const totalSecs = AppConstants.defaultFocusDuration * 60;
    return const FocusSessionState(
      status: FocusSessionStatus.idle,
      remainingSeconds: totalSecs,
      totalSeconds: totalSecs,
    );
  }

  // ── Setup (only while no session is counting down) ────────────────────────

  bool get _canConfigure =>
      state.status == FocusSessionStatus.idle ||
      state.status == FocusSessionStatus.finished;

  void setDurationMinutes(int minutes) {
    if (!_canConfigure || minutes <= 0) return;
    final secs = minutes * 60;
    state = state.copyWith(
      status: FocusSessionStatus.idle,
      totalSeconds: secs,
      remainingSeconds: secs,
    );
    _save();
  }

  void setBlockedApps(List<BlockedApp> apps) {
    if (!_canConfigure) return;
    state = state.copyWith(blockedApps: List.unmodifiable(apps));
    _save();
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  void start() {
    if (state.isRunning) return;
    if (state.status == FocusSessionStatus.paused) {
      resume();
      return;
    }
    // A finished (or otherwise empty) session must start from a full timer;
    // otherwise it would complete instantly and save a bogus session.
    if (state.status == FocusSessionStatus.finished ||
        state.remainingSeconds <= 0) {
      state = state.copyWith(
        status: FocusSessionStatus.idle,
        remainingSeconds: state.totalSeconds,
      );
    }
    _sessionStartTime = clock();
    state = state.copyWith(status: FocusSessionStatus.running);
    _tick();
  }

  void pause() {
    if (!state.isRunning) return;
    _syncRemaining();
    if (!state.isRunning) return; // it had already run out
    _timer?.cancel();
    _endsAt = null;
    state = state.copyWith(
      status: FocusSessionStatus.paused,
      clearEndsAt: true,
    );
    _save();
  }

  void resume() {
    if (state.status != FocusSessionStatus.paused) return;
    state = state.copyWith(status: FocusSessionStatus.running);
    _tick();
  }

  /// Re-derives the remaining time from the wall clock. Call when the app
  /// returns to the foreground; also used by every tick.
  void syncWithClock() {
    if (!state.isRunning) return;
    _syncRemaining();
  }

  void stop() => _returnToIdle();

  void reset() => _returnToIdle();

  void _returnToIdle() {
    _timer?.cancel();
    _sessionStartTime = null;
    _endsAt = null;
    // Keep the chosen duration and apps for the next session.
    state = FocusSessionState(
      status: FocusSessionStatus.idle,
      remainingSeconds: state.totalSeconds,
      totalSeconds: state.totalSeconds,
      blockedApps: state.blockedApps,
    );
    _save();
  }

  /// Rebuilds the session from disk after the process was killed or the
  /// device rebooted. A session whose time ran out while the app was dead is
  /// recorded as completed.
  Future<void> restore() async {
    final saved = await ref.read(focusSessionStoreProvider).load();
    if (saved == null || _disposed) return;
    // The user already started something this launch; don't clobber it.
    if (state.status != FocusSessionStatus.idle || _sessionStartTime != null) {
      return;
    }

    final base = FocusSessionState(
      status: FocusSessionStatus.idle,
      remainingSeconds: saved.totalSeconds,
      totalSeconds: saved.totalSeconds,
      blockedApps: saved.apps,
    );

    switch (saved.status) {
      case 'paused':
        state = base.copyWith(
          status: FocusSessionStatus.paused,
          remainingSeconds: saved.remainingSeconds,
        );
        _sessionStartTime =
            saved.startedAtMs == null ? null : _fromMs(saved.startedAtMs!);
      case 'running':
        final endsAtMs = saved.endsAtMs;
        if (endsAtMs == null) {
          state = base;
          break;
        }
        final remaining =
            _fromMs(endsAtMs).difference(clock()).inSeconds;
        _sessionStartTime =
            saved.startedAtMs == null ? null : _fromMs(saved.startedAtMs!);
        if (remaining <= 0) {
          state = base.copyWith(
            status: FocusSessionStatus.finished,
            remainingSeconds: 0,
          );
          _persistSession(endTime: _fromMs(endsAtMs));
          _save();
        } else {
          state = base.copyWith(
            status: FocusSessionStatus.running,
            remainingSeconds: remaining,
          );
          _tick();
        }
      default:
        state = base;
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  DateTime _fromMs(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  void _tick() {
    _timer?.cancel();
    _endsAt = clock().add(Duration(seconds: state.remainingSeconds));
    state = state.copyWith(endsAt: _endsAt);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _syncRemaining());
    _save();
  }

  void _syncRemaining() {
    final endsAt = _endsAt;
    if (endsAt == null || !state.isRunning) return;
    final remaining = endsAt.difference(clock()).inSeconds;
    if (remaining <= 0) {
      _timer?.cancel();
      _endsAt = null;
      state = state.copyWith(
        remainingSeconds: 0,
        status: FocusSessionStatus.finished,
        clearEndsAt: true,
      );
      _persistSession();
      _save();
    } else if (remaining != state.remainingSeconds) {
      state = state.copyWith(remainingSeconds: remaining);
    }
  }

  void _save() {
    final s = state;
    final status = switch (s.status) {
      FocusSessionStatus.running => 'running',
      FocusSessionStatus.paused => 'paused',
      FocusSessionStatus.finished => 'finished',
      FocusSessionStatus.idle => 'idle',
    };
    unawaited(ref.read(focusSessionStoreProvider).save(SavedFocusSession(
          status: status,
          totalSeconds: s.totalSeconds,
          remainingSeconds: s.remainingSeconds,
          apps: s.blockedApps,
          startedAtMs: _sessionStartTime?.millisecondsSinceEpoch,
          endsAtMs: s.endsAt?.millisecondsSinceEpoch,
        )));
  }

  void _persistSession({DateTime? endTime}) {
    final startTime = _sessionStartTime;
    if (startTime == null) return;

    final session = FocusSession(
      startTime: startTime,
      endTime: endTime ?? clock(),
      duration: state.totalSeconds,
    );

    ref.read(focusRepositoryProvider).saveSession(session).then((_) {
      if (_disposed) return;
      // Invalidate so home and stats screens see the new session immediately.
      ref.invalidate(dailyFocusSessionsProvider);
      ref.invalidate(weeklyFocusProvider);
    });
  }
}

final focusSessionStoreProvider = Provider<FocusSessionStore>(
  (_) => const PrefsFocusSessionStore(),
);

final focusSessionProvider =
    NotifierProvider<FocusSessionNotifier, FocusSessionState>(
  FocusSessionNotifier.new,
);
