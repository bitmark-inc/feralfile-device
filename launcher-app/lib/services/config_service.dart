import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_config.dart';
import '../models/wifi_credentials.dart';
import 'logger.dart';

class ConfigService {
  static const String _configFileName = 'app_config.json';
  static AppConfig? _cachedConfig;

  static Future<String> get _configFilePath async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/$_configFileName';
  }

  static Future<AppConfig?> loadConfig() async {
    try {
      if (_cachedConfig != null) return _cachedConfig;

      final file = File(await _configFilePath);
      if (!await file.exists()) {
        logger.info('No config file found at: ${file.path}');
        return null;
      }

      final contents = await file.readAsString();
      _cachedConfig = AppConfig.fromJson(contents);
      logger.info('Loaded config from: ${file.path}');
      return _cachedConfig;
    } catch (e) {
      logger.warning('Failed to load config: $e');
      return null;
    }
  }

  static Future<bool> saveConfig(AppConfig config) async {
    try {
      final file = File(await _configFilePath);
      await file.writeAsString(config.toJson());
      _cachedConfig = config;
      logger.info('Saved config to: ${file.path}');
      return true;
    } catch (e) {
      logger.warning('Failed to save config: $e');
      return false;
    }
  }

  static Future<bool> updateWifiCredentials(WifiCredentials credentials) async {
    final currentConfig = await loadConfig();
    final newConfig = AppConfig(
      wifiCredentials: credentials,
      screenRotation: currentConfig?.screenRotation,
    );
    return saveConfig(newConfig);
  }

  static Future<bool> updateScreenRotation(String rotation) async {
    final currentConfig = await loadConfig();
    final newConfig = AppConfig(
      wifiCredentials: currentConfig?.wifiCredentials,
      screenRotation: rotation,
    );
    return saveConfig(newConfig);
  }
}
