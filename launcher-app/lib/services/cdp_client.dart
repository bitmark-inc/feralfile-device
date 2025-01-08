import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'logger.dart';

class CDPClient {
  static Socket? _socket;
  static int _messageId = 0;
  static final _responseCompleters = <int, Completer<String>>{};
  static StreamSubscription? _subscription;

  static Future<void> connect() async {
    try {
      // Connect to Chromium's debug socket
      _socket = await Socket.connect(InternetAddress('localhost'), 9222);

      // Listen for responses
      _subscription = _socket?.listen(
        (data) {
          final String message = utf8.decode(data);
          _handleMessage(message);
        },
        onError: (error) {
          logger.severe('CDP socket error: $error');
        },
        onDone: () {
          logger.info('CDP socket closed');
          dispose();
        },
      );

      logger.info('Connected to Chrome DevTools Protocol via Unix socket');
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
    if (_socket == null) {
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

      _socket?.add(utf8.encode(jsonEncode(message)));

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
    _subscription?.cancel();
    _socket?.close();
    _socket = null;
    _responseCompleters.clear();
  }
}
