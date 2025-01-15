import 'dart:io';
import 'dart:convert';
import 'package:feralfile/services/logger.dart';

class WebSocketMessage {
  String messageID;
  Object? message;

  WebSocketMessage({required this.messageID, this.message});

  Map<String, String> toJson() => {
        'messageID': messageID,
        'message': jsonEncode(message ?? {}),
      };
}

class WebSocketService {
  static WebSocketService? _instance;
  WebSocket? _socket;
  HttpServer? _server;
  final Set<Function(dynamic)> _messageListeners = {};

  // Singleton pattern
  factory WebSocketService() {
    _instance ??= WebSocketService._internal();
    return _instance!;
  }

  WebSocketService._internal();

  Future<void> initServer() async {
    try {
      // Create HTTP server
      _server = await HttpServer.bind('localhost', 8080);
      logger.info('WebSocket server running on ws://localhost:8080');

      // Listen for WebSocket connections
      _server!.transform(WebSocketTransformer()).listen((WebSocket ws) {
        _socket = ws;
        logger.info('Client connected');

        // Handle messages from website
        ws.listen(
          (dynamic message) {
            _handleMessage(message);
          },
          onError: (error) {
            logger.warning('WebSocket error: $error');
          },
          onDone: () {
            logger.info('Client disconnected');
            _socket = null;
          },
        );
      });
    } catch (e) {
      logger.warning('Failed to start WebSocket server: $e');
    }
  }

  // Send message to website
  void sendMessage(WebSocketMessage message) {
    if (_socket != null) {
      _socket!.add(jsonEncode(message.toJson()));
    }
  }

  // Handle messages received from website
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      logger.info('Received message: $data');

      final messageID = jsonDecode(message)['messageID'];
      if (messageID == 'ping') {
        sendMessage(WebSocketMessage(
          messageID: messageID,
          message: {},
        ));

        Future.delayed(
          const Duration(seconds: 10),
          () {
            sendMessage(
              WebSocketMessage(
                messageID: '9bd42631-a992-4207-b1f7-ff1d63d65777',
                message: {
                  'command': 'castListArtwork',
                  'request': {
                    'artworks': [
                      {
                        'token': {
                          'id':
                              'eth-0x90e951F1BC16A0ECe75844D12371B81512718DA7-72359935895858646181951013458866965984551984693877025456801350144502744957515',
                        },
                        'artwork': null,
                        'duration': 0,
                      },
                    ],
                    'startTime': null,
                  }
                },
              ),
            );
          },
        );

        Future.delayed(
          const Duration(seconds: 30),
          () {
            sendMessage(
              WebSocketMessage(
                messageID: '377189a7-95e0-4a18-b9db-9bea9c26c4e3',
                message: {
                  'command': 'disconnect',
                  'request': {},
                },
              ),
            );
          },
        );
      }

      // Notify to all listeners
      for (var listener in _messageListeners) {
        listener(data);
      }
    } catch (e) {
      logger.warning('Error handling message: $e');
    }
  }

  // Add/remove listener
  void addMessageListener(Function(dynamic) listener) {
    _messageListeners.add(listener);
  }

  void removeMessageListener(Function(dynamic) listener) {
    _messageListeners.remove(listener);
  }

  void dispose() {
    _socket?.close();
    _server?.close();
    _messageListeners.clear();
  }
}
