// lib/services/logger.dart
import 'package:logging/logging.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

final Logger logger = Logger('FeralFileApp');
late File _logFile;

String get logFilePath => _logFile.path;

Future<void> setupLogging() async {
  // Initialize log file
  final Directory appDir = await getApplicationDocumentsDirectory();
  _logFile = File('${appDir.path}/app.log');

  Logger.root.level =
      Level.ALL; // Set to Level.INFO or Level.SEVERE in production
  Logger.root.onRecord.listen((record) {
    final logMessage =
        '${record.level.name}: ${record.time}: ${record.message}\n';
    // Print to console
    print(logMessage);
    // Write to file
    _logFile.writeAsStringSync(logMessage, mode: FileMode.append);
  });
}
