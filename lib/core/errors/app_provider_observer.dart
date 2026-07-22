import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'error_logger.dart';

/// Logs every provider failure through [ErrorLogger].
///
/// Several repositories (settings, theme, focus limits) have no local
/// try/catch — they let SharedPreferences/sqflite errors propagate, which is
/// correct since Riverpod already captures them as `AsyncValue.error`. This
/// observer is the single place that turns those captured errors into
/// diagnostics, instead of them disappearing silently into `AsyncValue`.
class AppProviderObserver extends ProviderObserver {
  const AppProviderObserver();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    ErrorLogger.log(error, stackTrace, context: 'Riverpod.${provider.name ?? provider.runtimeType}');
  }
}
