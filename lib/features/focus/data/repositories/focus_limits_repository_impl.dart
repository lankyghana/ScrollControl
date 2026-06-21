import '../../domain/entities/app_limit.dart';
import '../../domain/entities/focus_settings.dart';
import '../../domain/repositories/focus_limits_repository.dart';
import '../datasources/focus_limits_local_datasource.dart';
import '../models/app_limit_model.dart';
import '../models/focus_settings_model.dart';

class FocusLimitsRepositoryImpl implements FocusLimitsRepository {
  FocusLimitsRepositoryImpl({required FocusLimitsLocalDatasource datasource})
      : _datasource = datasource;

  final FocusLimitsLocalDatasource _datasource;

  @override
  Future<FocusSettings> loadSettings() {
    return _datasource.loadSettings();
  }

  @override
  Future<void> saveSettings(FocusSettings settings) {
    final model = FocusSettingsModel.fromEntity(settings);
    return _datasource.saveSettings(model);
  }

  @override
  Future<AppLimit?> getAppLimit(String packageName) {
    return _datasource.getAppLimit(packageName);
  }

  @override
  Future<void> setAppLimit(AppLimit limit) {
    final model = AppLimitModel(
      packageName: limit.packageName,
      appName: limit.appName,
      dailyLimitMinutes: limit.dailyLimitMinutes,
    );
    return _datasource.setAppLimit(model);
  }

  @override
  Future<void> removeAppLimit(String packageName) {
    return _datasource.removeAppLimit(packageName);
  }

  @override
  Future<List<AppLimit>> getAllLimits() {
    return _datasource.getAllLimits();
  }
}
