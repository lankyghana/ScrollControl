import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../focus/domain/entities/focus_session.dart';
import '../../../focus/presentation/providers/focus_providers.dart';

enum FocusSessionStatus { idle, running, paused, finished }

class FocusSessionState {
  const FocusSessionState({
    required this.status,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  final FocusSessionStatus status;
  final int remainingSeconds;
  final int totalSeconds;

  bool get isRunning => status == FocusSessionStatus.running;
  bool get isIdle => status == FocusSessionStatus.idle;
  double get progress =>
      totalSeconds == 0 ? 0 : remainingSeconds / totalSeconds;

  FocusSessionState copyWith({
    FocusSessionStatus? status,
    int? remainingSeconds,
    int? totalSeconds,
  }) {
    return FocusSessionState(
      status: status ?? this.status,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
    );
  }
}

class FocusSessionNotifier extends Notifier<FocusSessionState> {
  Timer? _timer;
  DateTime? _sessionStartTime;

  @override
  FocusSessionState build() {
    ref.onDispose(() => _timer?.cancel());

    const totalSecs = AppConstants.defaultFocusDuration * 60;
    return const FocusSessionState(
      status: FocusSessionStatus.idle,
      remainingSeconds: totalSecs,
      totalSeconds: totalSecs,
    );
  }

  void start() {
    if (state.isRunning) return;
    _sessionStartTime = DateTime.now();
    state = state.copyWith(status: FocusSessionStatus.running);
    _tick();
  }

  void pause() {
    _timer?.cancel();
    state = state.copyWith(status: FocusSessionStatus.paused);
  }

  void resume() {
    if (!state.isRunning) {
      state = state.copyWith(status: FocusSessionStatus.running);
      _tick();
    }
  }

  void stop() {
    _timer?.cancel();
    _sessionStartTime = null;
    const totalSecs = AppConstants.defaultFocusDuration * 60;
    state = const FocusSessionState(
      status: FocusSessionStatus.idle,
      remainingSeconds: totalSecs,
      totalSeconds: totalSecs,
    );
  }

  void reset() {
    _timer?.cancel();
    _sessionStartTime = null;
    const totalSecs = AppConstants.defaultFocusDuration * 60;
    state = const FocusSessionState(
      status: FocusSessionStatus.idle,
      remainingSeconds: totalSecs,
      totalSeconds: totalSecs,
    );
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.remainingSeconds <= 1) {
        _timer?.cancel();
        state = state.copyWith(
          remainingSeconds: 0,
          status: FocusSessionStatus.finished,
        );
        _persistSession();
      } else {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      }
    });
  }

  void _persistSession() {
    final startTime = _sessionStartTime;
    if (startTime == null) return;

    final session = FocusSession(
      startTime: startTime,
      endTime: DateTime.now(),
      duration: state.totalSeconds,
    );

    ref.read(focusRepositoryProvider).saveSession(session).then((_) {
      // Invalidate so home and stats screens see the new session immediately.
      ref.invalidate(dailyFocusSessionsProvider);
    });
  }
}

final focusSessionProvider =
    NotifierProvider<FocusSessionNotifier, FocusSessionState>(
  FocusSessionNotifier.new,
);
