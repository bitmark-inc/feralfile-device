// lib/services/logger.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import '../environment.dart';

final Logger logger = Logger('FeralFileApp');
late File _logFile;
HttpServer? _logServer;
final _logBuffer = <String>[];
const int _maxBufferSize = 1000; // Keep last 1000 log entries

String get logFilePath => _logFile.path;

List<String> get logBuffer => List.unmodifiable(_logBuffer);

Future<void> setupLogging() async {
  // Initialize log file
  final Directory appDir = await getApplicationDocumentsDirectory();
  _logFile = File('${appDir.path}/app.log');

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    final logMessage =
        '${record.level.name}: ${record.time}: ${record.message}\n';

    // Print to console
    print(logMessage);

    // Write to file
    _logFile.writeAsStringSync(logMessage, mode: FileMode.append);

    // Add to buffer
    _logBuffer.add(logMessage);
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
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

Future<void> sendLog(String? userID, String? title) async {
  try {
    if (Environment.supportURL.isEmpty || Environment.supportApiKey.isEmpty) {
      throw Exception(
          'Environment variables not properly initialized. Support URL: ${Environment.supportURL.isNotEmpty}, API Key exists: ${Environment.supportApiKey.isNotEmpty}');
    }

    const deviceID = 'unknown';
    const deviceName = 'FF Device';
    final ticketTitle = title ??
        '${deviceName}_${deviceID}_${DateTime.now().toIso8601String()}';

    var submitMessage = '';
    submitMessage += '**Version:** ${Environment.appVersion}\n';
    submitMessage += '**Device ID:** $deviceID\n**Device name:** $deviceName\n';

    final data = await _logFile.readAsBytes();
    final attachments = [
      {
        'data': base64Encode(data),
        'title': title,
        'content_type': 'logs',
      }
    ];

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
      'x-device-id': userID ?? deviceID,
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
