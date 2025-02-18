import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:feralfile/services/metric_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'logger.dart';

class CDPClient {
  static WebSocketChannel? _channel;
  static int _messageId = 0;
  static final _responseCompleters = <int, Completer<String>>{};
  static Isolate? _cdpIsolate;
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
    final receivePort = ReceivePort();

    try {
      _cdpIsolate = await Isolate.spawn(
        _cdpConnectionIsolate,
        receivePort.sendPort,
      );

      receivePort.listen((message) {
        if (message is String) {
          logger.fine('CDP Isolate message: $message');
        } else if (message is Map) {
          _handleIsolateMessage(message);
        }
      });
    } catch (e) {
      logger.severe('Failed to start CDP isolate: $e');
      _isConnecting = false;
    }
  }

  static void _handleIsolateMessage(Map message) {
    if (message['type'] == 'connection_established') {
      _channel = message['channel'] as WebSocketChannel?;
      _isConnecting = false;
      logger.info('CDP connection established in isolate');
      startFPSMonitoring();
    }
  }

  static Future<void> _cdpConnectionIsolate(SendPort sendPort) async {
    var retryCount = 0;
    Exception? lastError;

    while (retryCount < _maxRetries) {
      try {
        await connect(sendPort);
        return; // Success, exit the isolate
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

    final errorMessage =
        'Failed to establish CDP connection after $_maxRetries attempts. Last error: $lastError';
    logger.severe(errorMessage);
    sendPort.send(errorMessage);
  }

  static Future<void> connect(SendPort sendPort) async {
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
      await channel.ready; // Wait for the connection to be established

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

      sendPort.send({
        'type': 'connection_established',
        'channel': channel,
      });

      logger.info('Connected to Chrome DevTools Protocol via WebSocket');
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
      // Enable the Performance API
      await _sendCommand('Performance.enable');

      // Get metrics including FPS
      final metricsResponse = await _sendCommand('Performance.getMetrics');

      // Disable the Performance API after getting metrics
      await _sendCommand('Performance.disable');

      final decoded = jsonDecode(metricsResponse);
      final metrics = decoded['result']['metrics'] as List;

      // Find the FPS metric
      final fpsMetric = metrics.firstWhere(
        (metric) => metric['name'] == 'FramesPerSecond',
        orElse: () => null,
      );

      return fpsMetric?['value']?.toDouble();
    } catch (e) {
      logger.severe('Error getting Chromium FPS: $e');
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
      final entries = decoded['result']['entries'] as List;
      final currentEntry = entries.last;
      return currentEntry['url'] as String;
    } catch (e) {
      logger.severe('Error getting current URL: $e');
      return null;
    }
  }
}
