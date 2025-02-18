import 'dart:async';
import 'dart:convert';
import 'package:feralfile/services/metric_service.dart';
import 'package:http/http.dart' as http;
import 'logger.dart';

class CDPClient {
  static int _messageId = 0;
  static bool _isConnecting = false;
  static const _maxRetries = 10;
  static const _retryDelay = Duration(seconds: 5);
  static Timer? _fpsMonitorTimer;
  static const _fpsMonitorInterval = Duration(minutes: 2);
  static const _baseUrl = 'http://localhost:9222';

  static Future<void> startCDPConnection() async {
    if (_isConnecting) {
      logger.info('CDP connection already in progress');
      return;
    }

    _isConnecting = true;
    var retryCount = 0;
    Exception? lastError;

    while (retryCount < _maxRetries) {
      try {
        await _enableDomains();
        _isConnecting = false;
        logger.info('CDP connection established');
        startFPSMonitoring();
        return;
      } catch (e) {
        retryCount++;
        lastError = e as Exception;
        logger.severe('CDP connection attempt $retryCount failed: $e');

        if (retryCount < _maxRetries) {
          logger.info(
              'Retrying CDP connection in ${_retryDelay.inSeconds} seconds...');
          await Future.delayed(_retryDelay);
        }
      }
    }

    _isConnecting = false;
    final errorMessage =
        'Failed to establish CDP connection after $_maxRetries attempts. Last error: $lastError';
    logger.severe(errorMessage);
  }

  static Future<void> _enableDomains() async {
    await _sendCommand('Page.enable');
    await _sendCommand('Performance.enable');
    await _sendCommand('Rendering.enable');
    await _sendCommand('Rendering.setShowFPSCounter', {'show': true});
  }

  static void startFPSMonitoring() {
    _fpsMonitorTimer?.cancel();
    _fpsMonitorTimer =
        Timer.periodic(_fpsMonitorInterval, (_) => _monitorFPS());
    logger.info(
        'FPS monitoring started with ${_fpsMonitorInterval.inMinutes} minute interval');
  }

  static Future<void> _monitorFPS() async {
    try {
      final fps = await _getChromiumFPS();
      final url = await _getCurrentUrl();

      if (fps != null) {
        MetricService().sendEvent(
          'chromium_metrics',
          stringData: [url ?? 'unknown'],
          doubleData: [fps],
        );
        logger.info('Current Chromium FPS: $fps, URL: $url');
      }
    } catch (e) {
      logger.severe('Error monitoring FPS: $e');
    }
  }

  static Future<Map<String, dynamic>> _sendCommand(String method,
      [Map<String, dynamic>? params]) async {
    final id = _messageId++;
    final body = {
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'CDP command failed with status ${response.statusCode}: ${response.body}');
      }

      return jsonDecode(response.body);
    } catch (e) {
      logger.severe('Error sending CDP command: $e');
      rethrow;
    }
  }

  static Future<double?> _getChromiumFPS() async {
    try {
      final response = await _sendCommand('Performance.getMetrics');

      if (!response.containsKey('result') ||
          !response['result'].containsKey('metrics')) {
        logger.warning('Invalid metrics response format: $response');
        return null;
      }

      final metrics = response['result']['metrics'] as List;

      final fpsMetric = metrics.firstWhere(
        (metric) => metric['name'] == 'FramesPerSecond',
        orElse: () => null,
      );

      if (fpsMetric == null) {
        logger.warning('FPS metric not found in response');
        return null;
      }

      final fps = fpsMetric['value']?.toDouble();
      logger.fine('Raw FPS value: $fps');
      return fps;
    } catch (e) {
      logger.severe('Error getting Chromium FPS: $e');
      return null;
    }
  }

  static Future<String?> _getCurrentUrl() async {
    try {
      final response = await _sendCommand('Page.getNavigationHistory');

      if (!response.containsKey('result') ||
          !response['result'].containsKey('entries') ||
          !response['result'].containsKey('currentIndex')) {
        logger.warning('Invalid navigation history response format: $response');
        return null;
      }

      final entries = response['result']['entries'] as List;
      final currentIndex = response['result']['currentIndex'] as int;

      if (entries.isEmpty || currentIndex >= entries.length) {
        logger.warning('No navigation entries found or invalid current index');
        return null;
      }

      final currentEntry = entries[currentIndex];
      if (!currentEntry.containsKey('url')) {
        logger.warning(
            'URL not found in current navigation entry: $currentEntry');
        return null;
      }

      final url = currentEntry['url'] as String;
      logger.fine('Current URL: $url');
      return url;
    } catch (e) {
      logger.severe('Error getting current URL: $e');
      return null;
    }
  }

  static void dispose() {
    _sendCommand('Rendering.setShowFPSCounter', {'show': false})
        .catchError((e) {
      logger.warning('Error disabling FPS counter: $e');
    });

    _fpsMonitorTimer?.cancel();
    _fpsMonitorTimer = null;
  }
}
