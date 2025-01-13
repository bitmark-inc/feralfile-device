import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'logger.dart';

class CDPClient {
  static WebSocketChannel? _channel;
  static int _messageId = 0;
  static final _responseCompleters = <int, Completer<String>>{};

  static Future<void> connect() async {
    try {
      // First get the WebSocket debugger URL from Chrome's HTTP endpoint
      final response =
          await http.get(Uri.parse('http://localhost:9222/json/version'));
      if (response.statusCode != 200) {
        throw Exception('Failed to get debugger URL: ${response.statusCode}');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final String webSocketDebuggerUrl = data['webSocketDebuggerUrl'];

      // Connect to Chrome's WebSocket endpoint
      _channel = WebSocketChannel.connect(Uri.parse(webSocketDebuggerUrl));

      // Listen for responses
      _channel?.stream.listen(
        (data) {
          final String message = data.toString();
          _handleMessage(message);
        },
        onError: (error) {
          logger.severe('CDP WebSocket error: $error');
        },
        onDone: () {
          logger.info('CDP WebSocket closed');
          dispose();
        },
      );

      logger.info('Connected to Chrome DevTools Protocol via WebSocket');
    } catch (e) {
      logger.severe('Failed to connect to CDP: $e');
    }
  }

  static void _handleMessage(String message) {
    try {
      final Map<String, dynamic> parsed = jsonDecode(message);
      final int? id = parsed['id'];

      if (id != null && _responseCompleters.containsKey(id)) {
        _responseCompleters[id]?.complete(message);
        _responseCompleters.remove(id);
      }
    } catch (e) {
      logger.severe('Error handling CDP message: $e');
    }
  }

  static Future<String?> evaluateJavaScript(String expression) async {
    if (_channel == null) {
      await connect();
    }

    try {
      final id = _messageId++;
      final message = {
        'id': id,
        'method': 'Runtime.evaluate',
        'params': {'expression': expression, 'returnByValue': true}
      };

      final completer = Completer<String>();
      _responseCompleters[id] = completer;

      _channel?.sink.add(jsonEncode(message));

      final response = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _responseCompleters.remove(id);
          logger.warning('CDP command timed out');
          throw TimeoutException('CDP command timed out');
        },
      );

      final decoded = jsonDecode(response);
      return decoded['result']['result']['value']?.toString();
    } catch (e) {
      logger.severe('Error evaluating JavaScript: $e');
    }
    return null;
  }

  static void dispose() {
    _channel?.sink.close();
    _channel = null;
    _responseCompleters.clear();
  }
}
