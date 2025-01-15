import 'dart:io';
import 'dart:convert';
import 'package:feralfile/models/command.dart';
import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/logger.dart';

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

  // Handle messages received from website
  void _handleMessage(dynamic message) {
    try {
      logger.info('Received message: $message');

      final data = WebSocketResponseMessage.fromJson(jsonDecode(message));
      if (data.messageID == 'ping') {
        sendMessage(
          WebSocketRequestMessage(
            messageID: data.messageID,
          ),
        );

        Future.delayed(
          const Duration(seconds: 10),
          () {
            sendMessage(
              WebSocketRequestMessage(
                message: RequestMessageData(
                  command: Command.castListArtwork,
                  request: {
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
                  },
                ),
              ),
            );
          },
        );

        Future.delayed(
          const Duration(seconds: 30),
          () {
            sendMessage(
              WebSocketRequestMessage(
                message: RequestMessageData(
                  command: Command.disconnect,
                  request: {},
                ),
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

  // Send message to website
  void sendMessage(WebSocketRequestMessage message) {
    if (_socket != null) {
      logger.info('Sending message: ${jsonEncode(message.toJson())}');
      _socket!.add(jsonEncode(message.toJson()));
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
