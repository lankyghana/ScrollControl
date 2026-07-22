import 'dart:developer' as developer;

import 'app_exception.dart';

/// Forwards a classified error to an external crash-reporting service
/// (Sentry, Crashlytics, ...). Assign [ErrorLogger.reporter] once at startup
/// to enable it; left `null` by default so the app has zero external
/// reporting dependencies out of the box.
typedef ErrorReporter = void Function(
  AppException error,
  StackTrace stackTrace, {
  required String context,
});

/// Central error-logging sink.
///
/// Unlike the old `if (kDebugMode) debugPrint(...)` pattern, [log] always
/// emits — including in release builds, where it's visible via
/// `adb logcat` — and classifies every error through [classifyError] first,
/// so the [AppException] hierarchy is a real, inspectable signal instead of
/// dead code.
class ErrorLogger {
  ErrorLogger._();

  /// Set this in `main()` to forward errors to a real crash reporter, e.g.:
  /// `ErrorLogger.reporter = (e, st, {required context}) => Sentry.captureException(e, stackTrace: st);`
  static ErrorReporter? reporter;

  static void log(Object error, StackTrace stackTrace, {required String context}) {
    final appError = classifyError(error);

    developer.log(
      appError.message,
      name: 'ScrollControl.$context',
      error: appError,
      stackTrace: stackTrace,
      // Denied permissions are an expected user state, not a bug — log them
      // at a lower level than storage/unexpected failures.
      level: appError is PermissionException ? 900 : 1000,
    );

    reporter?.call(appError, stackTrace, context: context);
  }
}
