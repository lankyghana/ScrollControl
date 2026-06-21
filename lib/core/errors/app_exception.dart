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
