// lib/services/logger.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../environment.dart';
import '../services/metric_service.dart';

final Logger logger = Logger('FeralFileApp');
late File _logFile;
HttpServer? _logServer;
final _logBuffer = <String>[];
const int _maxBufferSize = 100; // Keep last 100 log entries
const int _maxFileLines = 100; // Keep only last 100 lines in log file
late SendPort _logIsolateSendPort;
late Isolate _logIsolate;

String get logFilePath => _logFile.path;

List<String> get logBuffer => List.unmodifiable(_logBuffer);

class _LogMessage {
  final String message;
  final bool isError;

  _LogMessage(this.message, this.isError);
}

Future<void> _logFileHandler(SendPort mainSendPort) async {
  final port = ReceivePort();
  mainSendPort.send(port.sendPort);

  // Initialize log file
  final Directory appDir = await getApplicationDocumentsDirectory();
  final File logFile = File('${appDir.path}/app.log');

  await port.listen((message) async {
    if (message is _LogMessage) {
      try {
        // Read existing log file if it exists
        List<String> lines = [];
        if (await logFile.exists()) {
          lines = await logFile.readAsLines();
        }

        // Add new log line
        lines.add(message.message.trim());

        // Keep only the last _maxFileLines
        if (lines.length > _maxFileLines) {
          lines = lines.sublist(lines.length - _maxFileLines);
        }

        // Write back to file
        await logFile.writeAsString(lines.join('\n') + '\n');

        // Track errors in main isolate if needed
        if (message.isError) {
          mainSendPort.send(message.message);
        }
      } catch (e) {
        mainSendPort.send('Error in log isolate: $e');
      }
    }
  });
}

Future<void> setupLogging() async {
  // Initialize log file path (actual file operations will happen in isolate)
  final Directory appDir = await getApplicationDocumentsDirectory();
  _logFile = File('${appDir.path}/app.log');

  // Create the log isolate
  final receivePort = ReceivePort();
  try {
    _logIsolate = await Isolate.spawn(_logFileHandler, receivePort.sendPort);

    // Get the send port from the isolate
    _logIsolateSendPort = await receivePort.first;

    // Create another receive port for error messages from the isolate
    final errorPort = ReceivePort();
    _logIsolate.setErrorsFatal(false);
    _logIsolate.addErrorListener(errorPort.sendPort);

    // Listen for error tracking messages from the isolate
    receivePort.listen((message) {
      if (message is String) {
        // Handle error tracking here in the main isolate
        MetricService().trackError(message);
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
      // Read existing log file if it exists
      List<String> lines = [];
      if (_logFile.existsSync()) {
        lines = _logFile.readAsLinesSync();
      }

      // Add new log line
      lines.add(logMessage.trim());

      // Keep only the last _maxFileLines
      if (lines.length > _maxFileLines) {
        lines = lines.sublist(lines.length - _maxFileLines);
      }

      // Write back to file
      _logFile.writeAsStringSync(lines.join('\n') + '\n');
    } catch (e) {
      print('Error writing to log file: $e');
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
          case '/logs/download':
            // Serve the log file as a download
            final file = File(_logFile.path);
            final bytes = await file.readAsBytes();
            request.response
              ..headers.set('Content-Type', 'text/plain')
              ..headers.set(
                'Content-Disposition',
                'attachment; filename="feralfile_device.log"',
              )
              ..add(bytes)
              ..close();
            break;

          case '/logs.html':
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
            position: fixed;
            top: 20px;
            right: 20px;
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
    </style>
</head>
<body>
    <a href="/logs/download" class="download-btn">Download Log File</a>
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
            // Serve logs as plain text
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
    final appLogData = await _logFile.readAsBytes();
    attachments.add({
      'data': base64Encode(appLogData),
      'title': 'app_log',
      'content_type': 'logs',
    });

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
