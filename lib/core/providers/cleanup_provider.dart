import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/cleanup_datasource.dart';
import '../data/cleanup_repository.dart';
import '../services/cleanup_service.dart';
import '../../core/database/database_helper.dart';

/// Provides access to the cleanup datasource.
final cleanupDataSourceProvider = Provider<CleanupDataSource>((ref) {
  return CleanupDataSource(DatabaseHelper.instance);
});

/// Provides access to the cleanup repository.
final cleanupRepositoryProvider = Provider<CleanupRepository>((ref) {
  final dataSource = ref.watch(cleanupDataSourceProvider);
  return CleanupRepository(dataSource);
});

/// Provides access to the cleanup service.
final cleanupServiceProvider = Provider<CleanupService>((ref) {
  final repository = ref.watch(cleanupRepositoryProvider);
  return CleanupService(repository: repository);
});
