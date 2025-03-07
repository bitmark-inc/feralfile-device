import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:feralfile/models/command.dart';
import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/logger.dart';

class WebSocketService {
  static WebSocketService? _instance;
  // Set of WebSocket connections for clients
  final Set<WebSocket> _clientSockets = {};
  // WebSocket connection for watchdog service
  WebSocket? _watchdogSocket;
  HttpServer? _server;
  final Set<Function(dynamic)> _messageListeners = {};
  final Map<String, Function(WebSocketResponseMessage)> _messageCallbacks = {};
  Timer? _heartbeatTimer;

  // Singleton pattern
  factory WebSocketService() {
    _instance ??= WebSocketService._internal();
    return _instance!;
  }

  WebSocketService._internal();

  bool isServerRunning() {
    return _server != null;
  }

  /// Returns the number of connected clients
  int get clientConnectionCount => _clientSockets.length;

  /// Initializes the WebSocket server, handling connections from clients and watchdogs, start heartbeat
  Future<void> initServer() async {
    try {
      if (isServerRunning()) {
        logger.info('WebSocket server already running');
        return;
      }
      // Bind the server to localhost:8080
      _server = await HttpServer.bind('localhost', 8080);
      logger.info('WebSocket server running on ws://localhost:8080');

      // Trigger the heart beat
      _startHeartbeat();

      // Listen for incoming HTTP requests and upgrade to WebSocket based on path
      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/watchdog') {
          // Handle watchdog connection
          WebSocket ws = await WebSocketTransformer.upgrade(request);
          _watchdogSocket = ws;
          logger.info('[WebSocket] Watchdog connected');

          ws.listen(
            (dynamic message) {
              // do nothing since we won't receive anything from watchdog service
            },
            onError: (error) {
              logger.warning('Watchdog WebSocket error: $error');
            },
            onDone: () {
              logger.info('[WebSocket] Watchdog disconnected');
              _watchdogSocket = null;
            },
          );
        } else if (request.uri.path == '/') {
          // Handle client connection
          WebSocket ws = await WebSocketTransformer.upgrade(request);
          _clientSockets.add(ws);
          logger.info(
              '[WebSocket] Client connected (total: ${_clientSockets.length})');

          ws.listen(
            (dynamic message) {
              _handleClientMessage(message);
            },
            onError: (error) {
              logger.warning('Client WebSocket error: $error');
            },
            onDone: () {
              _clientSockets.remove(ws);
              logger.info(
                  '[WebSocket] Client disconnected (remaining: ${_clientSockets.length})');
            },
          );
        } else {
          // Handle invalid paths
          request.response.write('Not found');
          await request.response.close();
        }
      });
    } catch (e) {
      logger.warning('Failed to start WebSocket server: $e');
    }
  }

  /// Handles messages received from clients
  void _handleClientMessage(dynamic message) {
    try {
      logger.info('Received message from client: $message');
      final data = WebSocketResponseMessage.fromJson(jsonDecode(message));

      // Execute callback if registered for this messageID
      if (_messageCallbacks.containsKey(data.messageID)) {
        _messageCallbacks[data.messageID]?.call(data);
        _messageCallbacks.remove(data.messageID);
      }

      for (var listener in _messageListeners) {
        listener(data);
      }
    } catch (e, s) {
      logger.warning('Error handling client message: $e \n stack: $s');
    }
  }

  void _startHeartbeat({Duration interval = const Duration(seconds: 10)}) {
    _stopHeartbeat(); // Cancel any existing timer
    _heartbeatTimer = Timer.periodic(interval, (_) {
      try {
        if (_watchdogSocket != null &&
            _watchdogSocket!.readyState == WebSocket.open) {
          _sendMessage(
            WebSocketRequestMessage(
                message: RequestMessageData(command: Command.ping)),
            false,
            callback: (response) {
              _watchdogSocket!.add(jsonEncode(response.toJson()));
            },
          );
        }
      } catch (e, s) {
        logger.warning('Error trying to heart beat clients: $e \n stack: $s');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Sends a message to all connected clients with an optional callback
  void _sendMessage(WebSocketRequestMessage message, bool logging,
      {Function(WebSocketResponseMessage)? callback}) {
    if (_clientSockets.isEmpty) {
      logger.warning(
          'Sending message failed. No client WebSocket connections available');
      return;
    }

    if (callback != null && message.messageID != null) {
      _messageCallbacks[message.messageID!] = callback;
    }

    if (logging) {
      logger.info(
          'Sending message to ${_clientSockets.length} client(s): ${jsonEncode(message.toJson())}');
    }

    final encodedMessage = jsonEncode(message.toJson());
    final deadSockets = <WebSocket>[];

    // Send to all connected clients
    for (final socket in _clientSockets) {
      if (socket.readyState == WebSocket.open) {
        socket.add(encodedMessage);
      } else {
        // Mark for removal if not open
        deadSockets.add(socket);
      }
    }

    // Clean up any dead connections
    for (final deadSocket in deadSockets) {
      _clientSockets.remove(deadSocket);
    }

    if (deadSockets.isNotEmpty) {
      logger.info('Removed ${deadSockets.length} dead WebSocket connection(s)');
    }

    if (logging) {
      logger.info('Message sent to ${_clientSockets.length} client(s)');
    }
  }

  /// Public method to send a message to all connected clients
  void sendMessage(WebSocketRequestMessage message) {
    _sendMessage(message, true);
  }

  /// Public method to send a message to all connected clients and register a callback
  void sendMessageWithCallback(WebSocketRequestMessage message,
      Function(WebSocketResponseMessage) callback) {
    _sendMessage(message, true, callback: callback);
  }

  /// Adds an internal message listener
  void addMessageListener(Function(dynamic) listener) {
    _messageListeners.add(listener);
  }

  /// Removes an internal message listener
  void removeMessageListener(Function(dynamic) listener) {
    _messageListeners.remove(listener);
  }

  /// Cleans up resources when the service is no longer needed
  void dispose() {
    _stopHeartbeat();

    // Close all client connections
    for (final socket in _clientSockets) {
      socket.close();
    }
    _clientSockets.clear();

    _watchdogSocket?.close();
    _server?.close();
    _messageListeners.clear();
    _messageCallbacks.clear();
    logger.info('WebSocketService disposed');
  }
}
