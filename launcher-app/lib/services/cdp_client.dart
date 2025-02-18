import 'dart:async';
import 'dart:convert';
import 'package:feralfile/services/metric_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'logger.dart';

class CDPClient {
  static WebSocketChannel? _channel;
  static int _messageId = 0;
  static final _responseCompleters = <int, Completer<String>>{};
  static bool _isConnecting = false;
  static const _maxRetries = 10;
  static const _retryDelay = Duration(seconds: 5);
  static Timer? _fpsMonitorTimer;
  static const _fpsMonitorInterval = Duration(minutes: 2);

  static Future<void> startCDPConnection() async {
    if (_isConnecting || _channel != null) {
      logger.info('CDP connection already in progress or established');
      return;
    }

    _isConnecting = true;
    var retryCount = 0;
    Exception? lastError;

    while (retryCount < _maxRetries) {
      try {
        await connect();
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

  static Future<void> connect() async {
    try {
      final response =
          await http.get(Uri.parse('http://localhost:9222/json/version'));
      if (response.statusCode != 200) {
        logger.severe(
            'Failed to get debugger URL. Status code: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to get debugger URL: ${response.statusCode}');
      }

      logger.fine('CDP Response body: ${response.body}');
      final Map<String, dynamic> data = jsonDecode(response.body);
      logger.fine('CDP Parsed data: $data');

      if (!data.containsKey('webSocketDebuggerUrl')) {
        logger.severe('Missing webSocketDebuggerUrl in response: $data');
        throw Exception('Missing webSocketDebuggerUrl in Chrome response');
      }

      final String webSocketDebuggerUrl = data['webSocketDebuggerUrl'];
      logger.fine('CDP WebSocket URL: $webSocketDebuggerUrl');

      final channel = WebSocketChannel.connect(Uri.parse(webSocketDebuggerUrl));
      await channel.ready;

      channel.stream.listen(
        (data) {
          final String message = data.toString();
          _handleMessage(message);
        },
        onError: (error) {
          logger.severe('CDP WebSocket error: $error');
        },
        onDone: () {
          logger.fine('CDP WebSocket closed');
          dispose();
        },
      );

      _channel = channel;
      logger.info('Connected to Chrome DevTools Protocol via WebSocket');

      // Enable required domains
      await _sendCommand('Page.enable');
      await _sendCommand('Performance.enable');
      await _sendCommand('Rendering.enable');

      // Enable FPS counter overlay for visual debugging
      await _sendCommand('Rendering.setShowFPSCounter', {'show': true});
    } catch (e, stackTrace) {
      logger.severe('Failed to connect to CDP: $e\n$stackTrace');
      rethrow;
    }
  }

  static void _handleMessage(String message) {
    try {
      logger.fine('CDP Received message: $message');
      final Map<String, dynamic> parsed = jsonDecode(message);
      logger.fine('CDP Parsed message: $parsed');
      final int? id = parsed['id'];

      if (id != null && _responseCompleters.containsKey(id)) {
        logger.fine('CDP Completing request with id: $id');
        _responseCompleters[id]?.complete(message);
        _responseCompleters.remove(id);
      } else {
        logger.fine('CDP Event or unmatched response with id: $id');
      }
    } catch (e) {
      logger.severe('Error handling CDP message: $e');
    }
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
      await _sendCommand('Page.enable');
      final fps = await _getChromiumFPS();
      final url = await _getCurrentUrl();
      await _sendCommand('Page.disable');

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

  static void dispose() {
    // Disable FPS counter before closing
    _sendCommand('Rendering.setShowFPSCounter', {'show': false})
        .catchError((e) {
      logger.warning('Error disabling FPS counter: $e');
    });

    _channel?.sink.close();
    _channel = null;
    _responseCompleters.clear();
    _fpsMonitorTimer?.cancel();
    _fpsMonitorTimer = null;
  }

  static Future<double?> _getChromiumFPS() async {
    if (_channel == null) {
      await startCDPConnection();
    }

    try {
      // Get metrics including FPS
      final metricsResponse = await _sendCommand('Performance.getMetrics');
      final decoded = jsonDecode(metricsResponse);

      if (!decoded.containsKey('result') ||
          !decoded['result'].containsKey('metrics')) {
        logger.warning('Invalid metrics response format: $decoded');
        return null;
      }

      final metrics = decoded['result']['metrics'] as List;

      // Find the FPS metric
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
    } catch (e, stackTrace) {
      logger.severe('Error getting Chromium FPS: $e\n$stackTrace');
      return null;
    }
  }

  static Future<String> _sendCommand(String method,
      [Map<String, dynamic>? params]) async {
    final id = _messageId++;
    final message = {
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    final completer = Completer<String>();
    _responseCompleters[id] = completer;

    _channel?.sink.add(jsonEncode(message));

    return await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _responseCompleters.remove(id);
        logger.warning('CDP command timed out');
        throw TimeoutException('CDP command timed out');
      },
    );
  }

  static Future<String?> _getCurrentUrl() async {
    try {
      final response = await _sendCommand('Page.getNavigationHistory');
      final decoded = jsonDecode(response);

      if (!decoded.containsKey('result') ||
          !decoded['result'].containsKey('entries') ||
          !decoded['result'].containsKey('currentIndex')) {
        logger.warning('Invalid navigation history response format: $decoded');
        return null;
      }

      final entries = decoded['result']['entries'] as List;
      final currentIndex = decoded['result']['currentIndex'] as int;

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
    } catch (e, stackTrace) {
      logger.severe('Error getting current URL: $e\n$stackTrace');
      return null;
    }
  }
}
