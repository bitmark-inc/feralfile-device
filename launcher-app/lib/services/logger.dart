// lib/services/logger.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../environment.dart';
import '../services/metric_service.dart';

final Logger logger = Logger('FeralFileApp');
late File _appLogFile;
late File _systemLogFile;
HttpServer? _logServer;
final _logBuffer = <String>[];
const int _maxBufferSize = 100;
late SendPort _logIsolateSendPort;
late Isolate _logIsolate;
ReceivePort? _logReceivePort;

String get appLogFilePath => _appLogFile.path;
String get systemLogFilePath => _systemLogFile.path;

List<String> get logBuffer => List.unmodifiable(_logBuffer);

class _LogMessage {
  final String message;
  final bool isError;

  _LogMessage(this.message, this.isError);
}

Future<void> _logFileHandler(SendPort mainSendPort) async {
  final port = ReceivePort();
  mainSendPort.send(port.sendPort);

  // Initialize log file using the same path as in main thread
  final Directory appDir = await getApplicationDocumentsDirectory();

  // Ensure the directory exists
  if (!await appDir.exists()) {
    try {
      await appDir.create(recursive: true);
    } catch (e) {
      mainSendPort.send('Error creating log directory: $e');
    }
  }

  final File appLogFile = File('${appDir.path}/app.log');
  final File systemLogFile = File('${appDir.path}/system.log');

  // Send the log file paths back to main thread
  mainSendPort.send('APP_FILE_PATH:${appLogFile.path}');
  mainSendPort.send('SYSTEM_FILE_PATH:${systemLogFile.path}');

  port.listen((message) async {
    if (message is _LogMessage) {
      try {
        final logLine = message.message.trim() + '\n';
        await appLogFile.writeAsString(logLine, mode: FileMode.append, flush: true);
        if (message.isError) {
          mainSendPort.send(message.message);
        }
      } catch (e) {
        mainSendPort.send('Error in log isolate writing to file: $e');
      }
    }
  });
}

Future<void> setupLogging() async {
  // Initialize log file paths
  final Directory appDir = await getApplicationDocumentsDirectory();
  _appLogFile = File('${appDir.path}/app.log');
  _systemLogFile = File('${appDir.path}/system.log');

  // Create the log isolate
  _logReceivePort = ReceivePort();
  try {
    _logIsolate =
        await Isolate.spawn(_logFileHandler, _logReceivePort!.sendPort);

    // Get the send port from the isolate
    _logIsolateSendPort = await _logReceivePort!.first;

    // Create another receive port for error messages from the isolate
    final errorPort = ReceivePort();
    _logIsolate.setErrorsFatal(false);
    _logIsolate.addErrorListener(errorPort.sendPort);

    // Listen for messages from the isolate
    _logReceivePort!.listen((message) {
      if (message is String) {
        if (message.startsWith('APP_FILE_PATH:')) {
          // Update the app log file path if needed
          final path = message.substring('APP_FILE_PATH:'.length);
          _appLogFile = File(path);
        } else if (message.startsWith('SYSTEM_FILE_PATH:')) {
          // Update the system log file path if needed
          final path = message.substring('SYSTEM_FILE_PATH:'.length);
          _systemLogFile = File(path);
        } else {
          // Handle error tracking here in the main isolate
          MetricService().trackError(message);
        }
      }
    });
  } catch (e) {
    print('Failed to spawn log isolate: $e');
    // Fall back to synchronous logging
    _setupSyncLogging();
    return;
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final logMessage =
        '${record.level.name}: ${record.time}: ${record.message}';

    // Print to console
    print('$logMessage');

    // Send to isolate for file writing
    final isError =
        record.level == Level.WARNING || record.level == Level.SEVERE;
    _logIsolateSendPort.send(_LogMessage('$logMessage', isError));

    // Add to in-memory buffer
    _logBuffer.add('$logMessage\n');
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }

    // Track warnings and errors as metrics in main isolate
    if (isError) {
      MetricService().trackError('${record.level.name}: ${record.message}');
    }
  });
}

void _setupSyncLogging() {
  // Fallback synchronous logging function if isolate fails
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final logMessage =
        '${record.level.name}: ${record.time}: ${record.message}';

    // Print to console
    print('$logMessage');

    try {
      final logLine = logMessage.trim() + '\n';
      _appLogFile.writeAsStringSync(logLine, mode: FileMode.append, flush: true);
    } catch (e) {
      print('Error writing to log file (sync): $e');
    }

    // Add to in-memory buffer
    _logBuffer.add('$logMessage\n');
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }

    // Track warnings and errors as metrics
    final isError =
        record.level == Level.WARNING || record.level == Level.SEVERE;
    if (isError) {
      MetricService().trackError('${record.level.name}: ${record.message}');
    }
  });
}

Future<void> startLogServer() async {
  // Don't create a new server if one already exists
  if (_logServer != null) {
    logger.info('Log server is already running');
    return;
  }

  try {
    _logServer = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    logger.info('Log server listening on port 8080');

    _logServer?.listen((HttpRequest request) async {
      if (request.method == 'GET') {
        switch (request.uri.path) {
          case '/logs/download/app':
            // Serve the app log file directly
            try {
              if (await _appLogFile.exists()) {
                final bytes = await _appLogFile.readAsBytes();
                request.response
                  ..headers.set('Content-Type', 'text/plain')
                  ..headers.set(
                    'Content-Disposition',
                    'attachment; filename="feralfile_app.log"',
                  )
                  ..add(bytes)
                  ..close();
              } else {
                request.response
                  ..statusCode = HttpStatus.notFound
                  ..close();
              }
            } catch (e) {
              logger.severe('Error serving app log file: $e');
              request.response
                ..statusCode = HttpStatus.internalServerError
                ..close();
            }
            break;

          case '/logs/download/system':
            // Serve the system log file directly
            try {
              if (await _systemLogFile.exists()) {
                final bytes = await _systemLogFile.readAsBytes();
                request.response
                  ..headers.set('Content-Type', 'text/plain')
                  ..headers.set(
                    'Content-Disposition',
                    'attachment; filename="feralfile_system.log"',
                  )
                  ..add(bytes)
                  ..close();
              } else {
                request.response
                  ..statusCode = HttpStatus.notFound
                  ..close();
              }
            } catch (e) {
              logger.severe('Error serving system log file: $e');
              request.response
                ..statusCode = HttpStatus.internalServerError
                ..close();
            }
            break;

          case '/logs.html':
            final appLogExists = await _appLogFile.exists();
            final systemLogExists = await _systemLogFile.exists();

            final html = '''
<!DOCTYPE html>
<html>
<head>
    <title>FeralFile Device Logs</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body { font-family: monospace; background: #1e1e1e; color: #d4d4d4; padding: 20px; }
        pre { white-space: pre-wrap; }
        .error { color: #f14c4c; }
        .warning { color: #cca700; }
        .info { color: #3794ff; }
        .download-btn {
            display: inline-block;
            margin: 10px;
            background: #3794ff;
            color: white;
            padding: 10px 20px;
            border-radius: 4px;
            text-decoration: none;
            font-weight: bold;
        }
        .download-btn:hover {
            background: #2d7acc;
        }
        .btn-container {
            position: fixed;
            top: 20px;
            right: 20px;
        }
    </style>
</head>
<body>
    <div class="btn-container">
        ${appLogExists ? '<a href="/logs/download/app" class="download-btn">Download App Log</a>' : ''}
        ${systemLogExists ? '<a href="/logs/download/system" class="download-btn">Download System Log</a>' : ''}
    </div>
    <h1>FeralFile Device Logs</h1>
    <pre>${_formatLogsHtml(_logBuffer.join())}</pre>
</body>
</html>
''';
            request.response
              ..headers.contentType = ContentType.html
              ..write(html)
              ..close();
            break;

          case '/logs':
            request.response
              ..headers.contentType = ContentType.text
              ..write(_logBuffer.join())
              ..close();
            break;

          default:
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
        }
      } else {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..close();
      }
    });
  } catch (e) {
    logger.severe('Failed to start log server: $e');
  }
}

String _formatLogsHtml(String logs) {
  return logs
      .replaceAll('SEVERE:', '<span class="error">SEVERE:</span>')
      .replaceAll('WARNING:', '<span class="warning">WARNING:</span>')
      .replaceAll('INFO:', '<span class="info">INFO:</span>')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}


void stopLogServer() {
  if (_logServer != null) {
    logger.info('Stopping log server');
    _logServer?.close(
        force: true); // Force close to ensure resources are released
    _logServer = null;
  }
}

void disposeLogger() {
  stopLogServer();
  if (_logIsolate != null) {
    try {
      _logIsolate.kill(priority: Isolate.immediate);
    } catch (e) {
      print('Error disposing logger isolate: $e');
    }
  }
  logger.info('Logger disposed');
}

String _deviceId = 'unknown';

// Add this function to update the device ID
void updateDeviceId(String deviceId) {
  _deviceId = deviceId;
  logger.info('Device ID updated to: $deviceId');
}

Future<void> sendLog(String? userID, String? title) async {
  try {
    if (Environment.supportURL.isEmpty || Environment.supportApiKey.isEmpty) {
      throw Exception(
          'Environment variables not properly initialized. Support URL: ${Environment.supportURL.isNotEmpty}, API Key exists: ${Environment.supportApiKey.isNotEmpty}');
    }
    const deviceName = 'FF-X1 Pilot';
    final ticketTitle =
        "${deviceName}_${title ?? '${_deviceId}_${DateTime.now().toIso8601String()}'}";

    var submitMessage = '';
    submitMessage += '**Version:** ${Environment.appVersion}\n';
    submitMessage +=
        '**Device ID:** $_deviceId\n**Device name:** $deviceName\n';

    // Create list of attachments
    final attachments = <Map<String, dynamic>>[];

    // Add app log
    if (await _appLogFile.exists()) {
      final appLogData = await _appLogFile.readAsBytes();
      attachments.add({
        'data': base64Encode(appLogData),
        'title': 'app_log',
        'content_type': 'logs',
      });
    }

    // Add system log
    if (await _systemLogFile.exists()) {
      final systemLogData = await _systemLogFile.readAsBytes();
      attachments.add({
        'data': base64Encode(systemLogData),
        'title': 'system_log',
        'content_type': 'logs',
      });
    }

    // Add Chromium debug log if it exists
    final chromiumLogFile = File('/var/log/chromium/chrome_debug.log');
    if (await chromiumLogFile.exists()) {
      logger.info('Chromium debug log found');
      final chromiumLogData = await chromiumLogFile.readAsBytes();
      attachments.add({
        'data': base64Encode(chromiumLogData),
        'title': 'chromium_debug_log',
        'content_type': 'logs',
      });
    }

    final tags = ['FF Device'];

    final payload = {
      'title': ticketTitle,
      'message': submitMessage,
      'attachments': attachments,
      'tags': tags,
    };

    final uri = Uri.parse('${Environment.supportURL}/v1/issues/');

    final request = http.Request('POST', uri);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'x-device-id': userID ?? _deviceId,
      'x-api-key': Environment.supportApiKey,
    });

    request.body = jsonEncode(payload);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != HttpStatus.created) {
      throw Exception(
          'statusCode: ${response.statusCode}, reason: ${response.reasonPhrase}');
    }
  } catch (e) {
    logger.severe('Error sending log: ${e.toString()}');
  }
}
