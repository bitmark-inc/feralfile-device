// lib/services/logger.dart
import 'package:logging/logging.dart';

final Logger logger = Logger('FeralFileApp');

void setupLogging() {
  Logger.root.level =
      Level.ALL; // Set to Level.INFO or Level.SEVERE in production
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}
