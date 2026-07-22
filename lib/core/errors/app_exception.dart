import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

final class StorageException extends AppException {
  const StorageException(super.message);
}

final class PermissionException extends AppException {
  const PermissionException(super.message);
}

final class UnexpectedException extends AppException {
  const UnexpectedException(super.message);
}

/// Classifies a raw caught error into the typed [AppException] hierarchy.
///
/// Every catch site in the app should route through this before logging, so
/// [ErrorLogger] (and any crash reporter wired into it later) can branch on
/// error *kind* — e.g. treat a denied permission as a warning and a database
/// failure as severe — instead of re-parsing message strings.
AppException classifyError(Object error) {
  if (error is AppException) return error;
  if (error is DatabaseException) {
    return StorageException('Database error: $error');
  }
  if (error is PlatformException) {
    if (error.code.toUpperCase().contains('PERMISSION')) {
      return PermissionException(
        'Permission error: ${error.message ?? error.code}',
      );
    }
    return UnexpectedException(
      'Platform error (${error.code}): ${error.message ?? error.code}',
    );
  }
  return UnexpectedException(error.toString());
}
