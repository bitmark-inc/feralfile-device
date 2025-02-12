import 'package:feralfile/services/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Environment {
  static String get supportURL => dotenv.env['SUPPORT_URL'] ?? '';

  static String get supportApiKey => dotenv.env['SUPPORT_API_KEY'] ?? '';

  static String get appVersion => dotenv.env['APP_VERSION'] ?? 'unknown';

  static String get metricsURL => dotenv.env['METRICS_URL'] ?? '';

  static String get metricsApiKey => dotenv.env['METRICS_API_KEY'] ?? '';

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      logger.severe('Error loading environment variables: $e');
    }
  }
}
