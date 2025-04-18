import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:feralfile/models/websocket_message.dart';
import 'package:feralfile/services/bluetooth_service.dart';
import 'package:feralfile/services/commands/javascript_handler.dart';
import 'package:feralfile/services/internet_connectivity_service.dart';
import 'package:feralfile/services/logger.dart';
import 'package:feralfile/services/rotate_service.dart';

const webRequestRotateMessageId = 'rotateDevice';

class WebSocketService {
  static WebSocketService? _instance;
  // WebSocket connection for the website
  WebSocket? _websiteSocket;
  // WebSocket connection for watchdog service
  WebSocket? _watchdogSocket;
  HttpServer? _server;
  final Set<Function(dynamic)> _messageListeners = {};
  final Map<String, Function(WebSocketResponseMessage)> _messageCallbacks = {};
  Timer? _heartbeatTimer;
  bool internetConnected = InternetConnectivityService().isOnline;

  // Singleton pattern
  factory WebSocketService() {
    _instance ??= WebSocketService._internal();
    return _instance!;
  }

  WebSocketService._internal() {
    // Subscribe to connectivity changes.
    InternetConnectivityService().onStatusChange.listen((status) {
      if (status && !internetConnected) {
        logger.info('Internet is online. Starting heartbeat.');
        internetConnected = true;
      } else if (!status && internetConnected) {
        logger.info('Internet is offline. Pausing heartbeat.');
        internetConnected = false;
      }
    });
  }

  bool isServerRunning() {
    return _server != null;
  }

  /// Initializes the WebSocket server, handling connections from website and watchdogs, start heartbeat the website
  Future<void> initServer() async {
    try {
      logger.info('Starting WebSocket server...');
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
          // Handle website connection
          WebSocket ws = await WebSocketTransformer.upgrade(request);
          _websiteSocket = ws;
          logger.info('[WebSocket] Website connected');

          ws.listen(
            (dynamic message) {
              _handleWebsiteMessage(message);
            },
            onError: (error) {
              logger.warning('Website WebSocket error: $error');
            },
            onDone: () {
              logger.info('[WebSocket] Website disconnected');
              _websiteSocket = null;
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

  /// Handles messages received from the website
  void _handleWebsiteMessage(dynamic message) async {
    try {
      logger.info('Received message from website: $message');
      final data = WebSocketResponseMessage.fromJson(jsonDecode(message));

      // Execute callback if registered for this messageID
      if (_messageCallbacks.containsKey(data.messageID)) {
        _messageCallbacks[data.messageID]?.call(data);
        _messageCallbacks.remove(data.messageID);
      }

      // Call bluetoothService.notify if messageID is statusChanged
      if (data.messageID == 'statusChanged') {
        try {
          final message = jsonDecode(data.message) as Map<String, dynamic>;
          BluetoothService().notify(data.messageID!, message);
        } catch (e) {
          logger.warning('Error sending notification: $e');
        }
      }

      if (data.messageID == webRequestRotateMessageId) {
        final message = jsonDecode(data.message) as Map<String, dynamic>;
        logger.info('Received rotate message: $message');
        final orientation = message['orientation'];
        logger.info('Received rotate orientation: $orientation');

        final rotation = orientation == null
            ? await RotateService.loadSavedRotation()
            : ScreenRotation.fromString(orientation);
        logger.info('Rotation: $rotation');

        if (rotation != null) {
          RotateService.rotateScreen(rotation, shouldSaveRotation: false);
        }
      }

      for (var listener in _messageListeners) {
        listener(data);
      }
    } catch (e, s) {
      logger.warning('Error handling website message: $e \n stack: $s');
    }
  }

  void _startHeartbeat({Duration interval = const Duration(seconds: 10)}) {
    _stopHeartbeat(); // Cancel any existing timer
    _heartbeatTimer = Timer.periodic(interval, (_) {
      try {
        if (_watchdogSocket != null &&
            _watchdogSocket!.readyState == WebSocket.open &&
            internetConnected) {
          _sendMessage(
            WebSocketRequestMessage(
                message: RequestMessageData(command: pingCommand)),
            false,
            callback: (response) {
              _watchdogSocket!.add(jsonEncode(response.toJson()));
            },
          );
        }
      } catch (e, s) {
        logger
            .warning('Error trying to heart beating website: $e \n stack: $s');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Sends a message to the website with an optional callback
  void _sendMessage(WebSocketRequestMessage message, bool logging,
      {Function(WebSocketResponseMessage)? callback}) {
    if (_websiteSocket?.readyState == WebSocket.open) {
      if (callback != null && message.messageID != null) {
        _messageCallbacks[message.messageID!] = callback;
      }
      if (logging) {
        logger.info(
            'Sending message to website: ${jsonEncode(message.toJson())}');
      }
      _websiteSocket!.add(jsonEncode(message.toJson()));
      if (logging) {
        logger.info('Message sent');
      }
    } else {
      logger.warning(
          'Sending message failed. Website WebSocket connection not available');
    }
  }

  /// Public method to send a message to the website
  void sendMessage(WebSocketRequestMessage message) {
    _sendMessage(message, true);
  }

  /// Public method to send a message to the website and register a callback
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
    _websiteSocket?.close();
    _watchdogSocket?.close();
    _server?.close();
    _messageListeners.clear();
    _messageCallbacks.clear();
    logger.info('WebSocketService disposed');
  }
}
